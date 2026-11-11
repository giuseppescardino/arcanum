use std::path::Path;
use std::time::{SystemTime, UNIX_EPOCH};

use arcanum_crypto::account::{self, EncryptedAccountKeys};
use arcanum_crypto::kdf::AuthKey;
use arcanum_crypto::{aead, hierarchy, Aad, CryptoError, KdfParams, SecretKey, SymmetricKey};
use serde::{Deserialize, Serialize};
use uuid::Uuid;
use zeroize::{Zeroize, ZeroizeOnDrop, Zeroizing};

use crate::model::{normalize_group, ItemKind};
use crate::store::{ItemRow, Store};
use crate::{Item, ItemData, Result, VaultError};

const META_ACCOUNT_ID: &str = "account_id";
const META_ACCOUNT_KEYS: &str = "account_keys";
pub(crate) const META_SYNC_LINK: &str = "sync_link";
pub(crate) const META_SYNC_CURSOR: &str = "sync_cursor";
pub(crate) const META_SYNC_EPOCH: &str = "sync_epoch";
pub(crate) const META_RESYNC: &str = "sync_resync";
const SYNC_LINK_LABEL: &str = "pm/sync-link/v1";
const DEVICE_NAME_LABEL: &str = "pm/device-name/v1";
/// Longer device names are cut before encryption.
pub const MAX_DEVICE_NAME_CHARS: usize = 100;

/// Keys held in memory only while unlocked; wiped on drop.
pub(crate) struct Session {
    pub account_id: String,
    pub account_key: SymmetricKey,
    pub vault_id: String,
    pub vault_key: SymmetricKey,
}

/// Everything another device needs (besides password and Secret Key) to
/// open this account. All of it is safe to hand to the server.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct AccountBundle {
    pub account_id: String,
    pub keys: EncryptedAccountKeys,
    pub vault_id: String,
    pub wrapped_vault_key: Vec<u8>,
}

/// Where this vault syncs. Stored encrypted under the Account Key, so the
/// session token is unreadable while locked. The account is identified by
/// the login id derived from the Secret Key, so it isn't stored here (links
/// saved by older versions still carry an `email`, which is ignored).
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize, Zeroize, ZeroizeOnDrop)]
pub struct SyncLink {
    pub server_url: String,
    pub token: String,
}

/// A computed but not yet applied password change: push `keys` and
/// `auth_key` to the server first, then [`Vault::commit_password_change`].
pub struct PasswordChange {
    pub keys: EncryptedAccountKeys,
    pub auth_key: AuthKey,
}

pub struct Vault {
    pub(crate) store: Store,
    pub(crate) session: Option<Session>,
}

impl Vault {
    pub fn open(path: impl AsRef<Path>) -> Result<Self> {
        Ok(Self {
            store: Store::open(path.as_ref())?,
            session: None,
        })
    }

    pub fn open_in_memory() -> Result<Self> {
        Ok(Self {
            store: Store::open_in_memory()?,
            session: None,
        })
    }

    pub fn is_initialized(&self) -> Result<bool> {
        Ok(self.store.get_meta(META_ACCOUNT_KEYS)?.is_some())
    }

    pub fn is_unlocked(&self) -> bool {
        self.session.is_some()
    }

    /// Creates the account and its default vault, leaving it unlocked.
    /// Returns the Secret Key, which the caller must show to the user once
    /// (Emergency Kit) and keep in the platform keychain.
    pub fn create(&mut self, password: &[u8], kdf: KdfParams) -> Result<SecretKey> {
        if self.is_initialized()? {
            return Err(VaultError::AlreadyInitialized);
        }
        let account_id = Uuid::new_v4().to_string();
        let account::NewAccount {
            secret_key,
            account_key,
            keys,
            ..
        } = account::create(account_id.as_bytes(), password, kdf)?;

        let vault_id = Uuid::new_v4().to_string();
        let vault_key = SymmetricKey::generate()?;
        let wrapped_vault_key =
            hierarchy::wrap_vault_key(&account_key, vault_id.as_bytes(), &vault_key)?;
        self.store_account(&AccountBundle {
            account_id: account_id.clone(),
            keys,
            vault_id: vault_id.clone(),
            wrapped_vault_key,
        })?;

        self.session = Some(Session {
            account_id,
            account_key,
            vault_id,
            vault_key,
        });
        self.record_password_unlock()?;
        Ok(secret_key)
    }

    /// Sets up this (empty) database for an existing account fetched from
    /// the server. The vault stays locked until [`Vault::unlock`].
    pub fn import_account(&mut self, bundle: &AccountBundle) -> Result<()> {
        if self.is_initialized()? {
            return Err(VaultError::AlreadyInitialized);
        }
        self.store_account(bundle)
    }

    fn store_account(&mut self, b: &AccountBundle) -> Result<()> {
        let keys_json =
            serde_json::to_vec(&b.keys).map_err(|_| VaultError::Corrupt("account keys"))?;
        self.store.transaction(|s| {
            s.set_meta(META_ACCOUNT_ID, b.account_id.as_bytes())?;
            s.set_meta(META_ACCOUNT_KEYS, &keys_json)?;
            s.insert_vault(&b.vault_id, &b.wrapped_vault_key)
        })
    }

    pub fn account_bundle(&self) -> Result<AccountBundle> {
        let (account_id, keys) = self.account()?;
        let (vault_id, wrapped_vault_key) = self.default_vault()?;
        Ok(AccountBundle {
            account_id,
            keys,
            vault_id,
            wrapped_vault_key,
        })
    }

    pub fn unlock(&mut self, password: &[u8], secret_key: &SecretKey) -> Result<()> {
        let (account_id, keys) = self.account()?;
        let account_key = account::unlock(account_id.as_bytes(), password, secret_key, &keys)
            .map_err(wrong_credentials)?;
        self.open_session(account_id, account_key)?;
        self.record_password_unlock()
    }

    pub(crate) fn open_session(
        &mut self,
        account_id: String,
        account_key: SymmetricKey,
    ) -> Result<()> {
        let (vault_id, wrapped) = self.default_vault()?;
        let vault_key = hierarchy::unwrap_vault_key(&account_key, vault_id.as_bytes(), &wrapped)?;
        self.session = Some(Session {
            account_id,
            account_key,
            vault_id,
            vault_key,
        });
        Ok(())
    }

    pub fn lock(&mut self) {
        self.session = None;
    }

    /// Locks and erases the local account, leaving an empty database as
    /// on first launch. Anything not synced to a server is lost.
    pub fn reset(&mut self) -> Result<()> {
        self.lock();
        self.store.transaction(|s| s.wipe())?;
        self.store.checkpoint()
    }

    /// Server authentication key; also proves `password` is correct.
    pub fn auth_key(&self, password: &[u8], secret_key: &SecretKey) -> Result<AuthKey> {
        let (account_id, keys) = self.account()?;
        let (_, auth_key) =
            account::unlock_with_auth(account_id.as_bytes(), password, secret_key, &keys)
                .map_err(wrong_credentials)?;
        Ok(auth_key)
    }

    /// Requires the current password even while unlocked, so an unattended
    /// unlocked device can't be used to take over the account.
    pub fn prepare_password_change(
        &self,
        current: &[u8],
        new: &[u8],
        secret_key: &SecretKey,
        kdf: KdfParams,
    ) -> Result<PasswordChange> {
        let (account_id, keys) = self.account()?;
        let account_key = account::unlock(account_id.as_bytes(), current, secret_key, &keys)
            .map_err(wrong_credentials)?;
        let (keys, auth_key) =
            account::change_password(account_id.as_bytes(), new, secret_key, &account_key, kdf)?;
        Ok(PasswordChange { keys, auth_key })
    }

    /// Replaces the local Account Key envelope with one fetched from the
    /// server (after a password change made on another device). Accepted
    /// only if it opens to the very same Account Key, so a server can't
    /// swap in keys of its own.
    pub fn adopt_account_keys(
        &mut self,
        password: &[u8],
        secret_key: &SecretKey,
        keys: &EncryptedAccountKeys,
    ) -> Result<()> {
        let session = self.session()?;
        let account_key =
            account::unlock(session.account_id.as_bytes(), password, secret_key, keys)
                .map_err(wrong_credentials)?;
        if account_key != session.account_key {
            return Err(VaultError::Corrupt("server account key does not match"));
        }
        let json = serde_json::to_vec(keys).map_err(|_| VaultError::Corrupt("account keys"))?;
        self.store.set_meta(META_ACCOUNT_KEYS, &json)?;
        // The password changed: biometric unlock must be set up again.
        self.disable_quick_unlock()
    }

    pub fn commit_password_change(&mut self, change: &PasswordChange) -> Result<()> {
        let json =
            serde_json::to_vec(&change.keys).map_err(|_| VaultError::Corrupt("account keys"))?;
        self.store.set_meta(META_ACCOUNT_KEYS, &json)?;
        self.disable_quick_unlock()
    }

    /// Local-only password change (no sync link).
    pub fn change_password(
        &mut self,
        current: &[u8],
        new: &[u8],
        secret_key: &SecretKey,
        kdf: KdfParams,
    ) -> Result<()> {
        let change = self.prepare_password_change(current, new, secret_key, kdf)?;
        self.commit_password_change(&change)
    }

    pub fn set_sync_link(&mut self, link: &SyncLink) -> Result<()> {
        let session = self.session()?;
        let json =
            Zeroizing::new(serde_json::to_vec(link).map_err(|_| VaultError::Corrupt("sync link"))?);
        let sealed = aead::seal(&session.account_key, &json, &sync_link_aad(session))?;
        self.store.set_meta(META_SYNC_LINK, &sealed)
    }

    pub fn sync_link(&self) -> Result<Option<SyncLink>> {
        let session = self.session()?;
        let Some(sealed) = self.store.get_meta(META_SYNC_LINK)? else {
            return Ok(None);
        };
        let json = aead::open(&session.account_key, &sealed, &sync_link_aad(session))?;
        let link = serde_json::from_slice(&json).map_err(|_| VaultError::Corrupt("sync link"))?;
        Ok(Some(link))
    }

    /// Encrypts this device's name for the server's device list (the
    /// server stores it but can't read it). Names are trimmed and cut to
    /// [`MAX_DEVICE_NAME_CHARS`].
    pub fn seal_device_name(&self, name: &str) -> Result<Vec<u8>> {
        let session = self.session()?;
        let mut name: String = name.trim().chars().take(MAX_DEVICE_NAME_CHARS).collect();
        if name.is_empty() {
            name.push('?');
        }
        Ok(aead::seal(
            &session.account_key,
            name.as_bytes(),
            &device_name_aad(session),
        )?)
    }

    /// Decrypts a name sealed by [`Vault::seal_device_name`] on any device
    /// of this account; `None` if it doesn't open (tampered or foreign).
    pub fn open_device_name(&self, sealed: &[u8]) -> Result<Option<String>> {
        let session = self.session()?;
        Ok(
            aead::open(&session.account_key, sealed, &device_name_aad(session))
                .ok()
                .and_then(|bytes| String::from_utf8(bytes.to_vec()).ok()),
        )
    }

    /// Whether a sync link exists; readable while locked.
    pub fn is_linked(&self) -> Result<bool> {
        Ok(self.store.get_meta(META_SYNC_LINK)?.is_some())
    }

    /// Detaches from the server. Local data is kept and will be uploaded
    /// in full if the vault is linked again.
    pub fn clear_sync_link(&mut self) -> Result<()> {
        self.store.transaction(|s| {
            s.delete_meta(META_SYNC_LINK)?;
            s.delete_meta(META_SYNC_CURSOR)?;
            s.delete_meta(META_SYNC_EPOCH)?;
            s.delete_meta(META_RESYNC)?;
            s.reset_sync_state()
        })
    }

    /// All live items, sorted by title (case-insensitive).
    pub fn items(&self) -> Result<Vec<Item>> {
        let session = self.session()?;
        let mut items = self
            .store
            .live_items(&session.vault_id)?
            .iter()
            .map(|row| decrypt_row(session, row))
            .collect::<Result<Vec<_>>>()?;
        items.sort_by_cached_key(|i| i.data.title.to_lowercase());
        Ok(items)
    }

    pub fn item(&self, id: &str) -> Result<Item> {
        let session = self.session()?;
        let row = self.live_row(session, id)?;
        decrypt_row(session, &row)
    }

    pub fn add_item(&mut self, data: &ItemData) -> Result<Item> {
        let session = self.session()?;
        self.insert_new(session, data)
    }

    pub fn update_item(&mut self, id: &str, data: &ItemData) -> Result<Item> {
        let session = self.session()?;
        let row = self.live_row(session, id)?;
        let item_key = unwrap_item_key(session, &row)?;
        self.write_local(
            session,
            row.id,
            next_revision(row.revision)?,
            row.wrapped_key,
            &item_key,
            Some(data),
        )
    }

    /// Replaces the item with a tombstone: content is discarded, the
    /// revision is bumped so the deletion wins during sync.
    pub fn delete_item(&mut self, id: &str) -> Result<()> {
        let session = self.session()?;
        let row = self.live_row(session, id)?;
        let item_key = unwrap_item_key(session, &row)?;
        self.write_local(
            session,
            row.id,
            next_revision(row.revision)?,
            row.wrapped_key,
            &item_key,
            None,
        )?;
        Ok(())
    }

    /// Adds many items in one transaction (imports). Returns how many.
    pub fn add_items(&mut self, items: &[ItemData]) -> Result<u32> {
        let session = self.session.as_ref().ok_or(VaultError::Locked)?;
        let mut rows = Vec::with_capacity(items.len());
        for data in items {
            let id = Uuid::new_v4().to_string();
            let item_key = SymmetricKey::generate()?;
            let wrapped_key = hierarchy::wrap_item_key(
                &session.vault_key,
                session.vault_id.as_bytes(),
                id.as_bytes(),
                &item_key,
            )?;
            rows.push(encrypt_row(
                session,
                id,
                1,
                wrapped_key,
                &item_key,
                Some(data),
                now_ms(),
            )?);
        }
        self.store.transaction(|s| {
            for row in &rows {
                s.upsert_local(row)?;
            }
            Ok(())
        })?;
        Ok(u32::try_from(rows.len()).unwrap_or(u32::MAX))
    }

    /// Moves group `from`, with all its subgroups, to `to` in one
    /// transaction: `Work` -> `Office` also turns `Work/Clients` into
    /// `Office/Clients`. An empty `to` leaves every item of the subtree
    /// ungrouped. Group settings records ([`ItemKind::Group`]) move along
    /// with their group; they are deleted when the subtree is ungrouped or
    /// when the destination already has its own settings. Returns how many
    /// items (not settings records) were moved.
    pub fn rename_group(&mut self, from: &str, to: &str) -> Result<u32> {
        let session = self.session.as_ref().ok_or(VaultError::Locked)?;
        let (from, to) = (normalize_group(from), normalize_group(to));
        if from.is_empty() || from == to {
            return Ok(0);
        }
        let prefix = format!("{from}/");
        let mut moved = 0u32;
        let mut rows = Vec::new();
        let mut staying_settings = std::collections::HashSet::new();
        let mut moving_settings = Vec::new();
        for row in self.store.live_items(&session.vault_id)? {
            let Some(mut data) = decrypt_data(session, &row)? else {
                continue;
            };
            let group = normalize_group(&data.group);
            let rest = if group == from {
                ""
            } else if let Some(rest) = group.strip_prefix(&prefix) {
                rest
            } else {
                if data.kind == ItemKind::Group {
                    staying_settings.insert(group);
                }
                continue;
            };
            data.group = if to.is_empty() {
                String::new()
            } else if rest.is_empty() {
                to.clone()
            } else {
                format!("{to}/{rest}")
            };
            if data.kind == ItemKind::Group {
                moving_settings.push((row, data));
                continue;
            }
            moved += 1;
            let item_key = unwrap_item_key(session, &row)?;
            rows.push(encrypt_row(
                session,
                row.id,
                next_revision(row.revision)?,
                row.wrapped_key,
                &item_key,
                Some(&data),
                now_ms(),
            )?);
        }
        for (row, data) in moving_settings {
            let keep = !data.group.is_empty() && !staying_settings.contains(&data.group);
            let item_key = unwrap_item_key(session, &row)?;
            rows.push(encrypt_row(
                session,
                row.id,
                next_revision(row.revision)?,
                row.wrapped_key,
                &item_key,
                keep.then_some(&data),
                now_ms(),
            )?);
        }
        self.store.transaction(|s| {
            for row in &rows {
                s.upsert_local(row)?;
            }
            Ok(())
        })?;
        Ok(moved)
    }

    /// Sets the color (0xAARRGGBB) of group `path`, or clears it with
    /// `None`. Stored as an encrypted [`ItemKind::Group`] record, so it
    /// syncs like an item.
    pub fn set_group_color(&mut self, path: &str, color: Option<u32>) -> Result<()> {
        let session = self.session.as_ref().ok_or(VaultError::Locked)?;
        let path = normalize_group(path);
        if path.is_empty() {
            return Ok(());
        }
        let mut existing = Vec::new();
        for row in self.store.live_items(&session.vault_id)? {
            if let Some(data) = decrypt_data(session, &row)? {
                if data.kind == ItemKind::Group && normalize_group(&data.group) == path {
                    existing.push(row);
                }
            }
        }
        let data = color.map(|color| {
            let mut d = ItemData::default();
            d.kind = ItemKind::Group;
            d.group = path.clone();
            d.color = Some(color);
            d
        });
        let mut rows = Vec::new();
        let mut existing = existing.into_iter();
        if let Some(row) = existing.next() {
            let item_key = unwrap_item_key(session, &row)?;
            rows.push(encrypt_row(
                session,
                row.id,
                next_revision(row.revision)?,
                row.wrapped_key,
                &item_key,
                data.as_ref(),
                now_ms(),
            )?);
        } else if let Some(data) = &data {
            self.insert_new(session, data)?;
        }
        // Duplicates (two devices colored the same group offline) go away.
        for row in existing {
            let item_key = unwrap_item_key(session, &row)?;
            rows.push(encrypt_row(
                session,
                row.id,
                next_revision(row.revision)?,
                row.wrapped_key,
                &item_key,
                None,
                now_ms(),
            )?);
        }
        self.store.transaction(|s| {
            for row in &rows {
                s.upsert_local(row)?;
            }
            Ok(())
        })
    }

    pub(crate) fn insert_new(&self, session: &Session, data: &ItemData) -> Result<Item> {
        let id = Uuid::new_v4().to_string();
        let item_key = SymmetricKey::generate()?;
        let wrapped_key = hierarchy::wrap_item_key(
            &session.vault_key,
            session.vault_id.as_bytes(),
            id.as_bytes(),
            &item_key,
        )?;
        self.write_local(session, id, 1, wrapped_key, &item_key, Some(data))
    }

    fn write_local(
        &self,
        session: &Session,
        id: String,
        revision: u64,
        wrapped_key: Vec<u8>,
        item_key: &SymmetricKey,
        data: Option<&ItemData>,
    ) -> Result<Item> {
        let row = encrypt_row(session, id, revision, wrapped_key, item_key, data, now_ms())?;
        self.store.upsert_local(&row)?;
        Ok(Item {
            id: row.id,
            revision,
            updated_at: row.updated_at,
            data: data.cloned().unwrap_or_default(),
        })
    }

    fn live_row(&self, session: &Session, id: &str) -> Result<ItemRow> {
        match self.store.get_item(id)? {
            Some(row) if !row.deleted && row.vault_id == session.vault_id => Ok(row),
            _ => Err(VaultError::NotFound),
        }
    }

    pub(crate) fn session(&self) -> Result<&Session> {
        self.session.as_ref().ok_or(VaultError::Locked)
    }

    fn default_vault(&self) -> Result<(String, Vec<u8>)> {
        self.store
            .first_vault()?
            .ok_or(VaultError::Corrupt("missing default vault"))
    }

    pub(crate) fn account(&self) -> Result<(String, EncryptedAccountKeys)> {
        let id = self
            .store
            .get_meta(META_ACCOUNT_ID)?
            .ok_or(VaultError::NotInitialized)?;
        let keys = self
            .store
            .get_meta(META_ACCOUNT_KEYS)?
            .ok_or(VaultError::NotInitialized)?;
        let id = String::from_utf8(id).map_err(|_| VaultError::Corrupt("account id"))?;
        let keys =
            serde_json::from_slice(&keys).map_err(|_| VaultError::Corrupt("account keys"))?;
        Ok((id, keys))
    }
}

fn sync_link_aad(session: &Session) -> Aad {
    Aad::new(SYNC_LINK_LABEL).field(session.account_id.as_bytes())
}

fn device_name_aad(session: &Session) -> Aad {
    Aad::new(DEVICE_NAME_LABEL).field(session.account_id.as_bytes())
}

/// Encrypts `data` (or a tombstone when `None`) into a row marked dirty.
pub(crate) fn encrypt_row(
    session: &Session,
    id: String,
    revision: u64,
    wrapped_key: Vec<u8>,
    item_key: &SymmetricKey,
    data: Option<&ItemData>,
    updated_at: i64,
) -> Result<ItemRow> {
    let plaintext = Zeroizing::new(match data {
        Some(d) => serde_json::to_vec(d).map_err(|_| VaultError::Corrupt("item"))?,
        None => Vec::new(),
    });
    let ciphertext = hierarchy::encrypt_item(
        item_key,
        session.vault_id.as_bytes(),
        id.as_bytes(),
        revision,
        &plaintext,
    )?;
    Ok(ItemRow {
        id,
        vault_id: session.vault_id.clone(),
        revision,
        wrapped_key,
        ciphertext,
        deleted: data.is_none(),
        updated_at,
        dirty: true,
        server_revision: None,
    })
}

pub(crate) fn unwrap_item_key(session: &Session, row: &ItemRow) -> Result<SymmetricKey> {
    Ok(hierarchy::unwrap_item_key(
        &session.vault_key,
        session.vault_id.as_bytes(),
        row.id.as_bytes(),
        &row.wrapped_key,
    )?)
}

/// Decrypts a row's content; `None` for tombstones.
pub(crate) fn decrypt_data(session: &Session, row: &ItemRow) -> Result<Option<ItemData>> {
    if row.deleted {
        return Ok(None);
    }
    let item_key = unwrap_item_key(session, row)?;
    let plaintext = hierarchy::decrypt_item(
        &item_key,
        session.vault_id.as_bytes(),
        row.id.as_bytes(),
        row.revision,
        &row.ciphertext,
    )?;
    let data = serde_json::from_slice(&plaintext).map_err(|_| VaultError::Corrupt("item"))?;
    Ok(Some(data))
}

fn decrypt_row(session: &Session, row: &ItemRow) -> Result<Item> {
    let data = decrypt_data(session, row)?.ok_or(VaultError::NotFound)?;
    Ok(Item {
        id: row.id.clone(),
        revision: row.revision,
        updated_at: row.updated_at,
        data,
    })
}

pub(crate) fn wrong_credentials(e: CryptoError) -> VaultError {
    match e {
        CryptoError::Decrypt => VaultError::WrongCredentials,
        other => other.into(),
    }
}

pub(crate) fn next_revision(revision: u64) -> Result<u64> {
    revision
        .checked_add(1)
        .ok_or(VaultError::Corrupt("revision overflow"))
}

pub(crate) fn now_ms() -> i64 {
    SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .map(|d| i64::try_from(d.as_millis()).unwrap_or(i64::MAX))
        .unwrap_or(0)
}
