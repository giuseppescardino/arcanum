//! Dart-facing API. Passwords arrive as bytes and are wiped as soon as the
//! call returns; every method that runs Argon2 is async on the Dart side
//! (flutter_rust_bridge runs it on a worker thread).

use std::sync::{Mutex, MutexGuard};

use arcanum_sync::SyncError;
use arcanum_vault::{
    normalize_group, ItemData, ItemKind, KdfParams, SecretKey, SyncReport, Vault, VaultError,
};
use data_encoding::BASE64;
use flutter_rust_bridge::frb;
use zeroize::Zeroizing;

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum VaultItemKind {
    Login,
    SecureNote,
}

/// Editable fields of an item.
#[derive(Debug, Clone)]
pub struct ItemFields {
    pub kind: VaultItemKind,
    pub title: String,
    pub username: String,
    pub password: String,
    pub urls: Vec<String>,
    pub notes: String,
    pub totp: Option<String>,
    pub favorite: bool,
    /// Group path, levels separated by `/`; empty for none.
    pub group: String,
}

#[derive(Debug, Clone)]
pub struct VaultItem {
    pub id: String,
    /// Unix time in milliseconds.
    pub updated_at: i64,
    pub fields: ItemFields,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum VaultFailureCode {
    WrongCredentials,
    InvalidSecretKey,
    Locked,
    NotInitialized,
    AlreadyInitialized,
    NotFound,
    /// Server sync: wrong password or Secret Key.
    InvalidLogin,
    /// An account with this Secret Key is already on the server.
    AccountExists,
    /// The server only accepts registrations with an invite code.
    InviteRequired,
    /// The invite code is unknown, used or expired.
    InvalidInvite,
    /// The server does not accept new accounts.
    RegistrationClosed,
    /// The account reached the server's storage quota.
    QuotaExceeded,
    /// The server session expired or was revoked: reconnect.
    SessionExpired,
    TooManyRequests,
    InvalidServerUrl,
    Network,
    NotLinked,
    /// Bad generator options or TOTP secret.
    InvalidInput,
    /// Quick unlock refused: type the master password.
    PasswordRequired,
    /// The file to import is not in a format the app reads.
    UnsupportedFormat,
    /// The file is an encrypted backup: its password is needed.
    BackupPasswordRequired,
    Internal,
}

/// Outcome of a sync, for a short status line in the UI.
#[derive(Debug, Clone, Copy)]
pub struct SyncSummary {
    pub pulled: u32,
    pub pushed: u32,
    pub conflicts: u32,
}

#[derive(Debug, Clone)]
pub struct SyncInfo {
    pub server_url: String,
}

/// Errors surfaced to Dart as a typed exception. `message` is diagnostic
/// only; the UI picks its text from `code`.
#[derive(Debug)]
pub struct VaultFailure {
    pub code: VaultFailureCode,
    pub message: String,
}

impl VaultFailure {
    fn new(code: VaultFailureCode) -> Self {
        Self {
            code,
            message: String::new(),
        }
    }

    fn internal(message: impl Into<String>) -> Self {
        Self {
            code: VaultFailureCode::Internal,
            message: message.into(),
        }
    }
}

pub struct VaultHandle {
    inner: Mutex<Vault>,
}

impl VaultHandle {
    /// Opens (or creates) the vault database at `path`.
    pub fn open(path: String) -> Result<VaultHandle, VaultFailure> {
        Ok(VaultHandle {
            inner: Mutex::new(Vault::open(path)?),
        })
    }

    pub fn is_initialized(&self) -> Result<bool, VaultFailure> {
        Ok(self.vault()?.is_initialized()?)
    }

    #[frb(sync)]
    pub fn is_unlocked(&self) -> bool {
        self.vault().map(|v| v.is_unlocked()).unwrap_or(false)
    }

    /// Creates the account and returns the Secret Key in Emergency Kit form.
    pub fn create(&self, password: Vec<u8>) -> Result<String, VaultFailure> {
        let password = Zeroizing::new(password);
        let secret_key = self.vault()?.create(&password, KdfParams::DEFAULT)?;
        Ok(secret_key.to_display_string().to_string())
    }

    pub fn unlock(&self, password: Vec<u8>, secret_key: String) -> Result<(), VaultFailure> {
        let password = Zeroizing::new(password);
        let secret_key = parse_secret_key(secret_key)?;
        Ok(self.vault()?.unlock(&password, &secret_key)?)
    }

    #[frb(sync)]
    pub fn lock(&self) {
        if let Ok(mut v) = self.vault() {
            v.lock();
        }
    }

    pub fn change_password(
        &self,
        current: Vec<u8>,
        new_password: Vec<u8>,
        secret_key: String,
    ) -> Result<(), VaultFailure> {
        let current = Zeroizing::new(current);
        let new_password = Zeroizing::new(new_password);
        let secret_key = parse_secret_key(secret_key)?;
        // Updates the server first when linked, then the local copy.
        Ok(arcanum_sync::change_password(
            &mut *self.vault()?,
            &current,
            &new_password,
            &secret_key,
        )?)
    }

    /// Enables biometric unlock; returns the secret (base64) that the app
    /// must keep in the platform's biometric-protected storage.
    pub fn enable_quick_unlock(&self) -> Result<String, VaultFailure> {
        let secret = self.vault()?.enable_quick_unlock()?;
        Ok(BASE64.encode(secret.as_ref()))
    }

    pub fn quick_unlock(&self, secret: String) -> Result<(), VaultFailure> {
        let secret = Zeroizing::new(secret);
        let raw = Zeroizing::new(
            BASE64
                .decode(secret.as_bytes())
                .map_err(|_| VaultFailure::new(VaultFailureCode::WrongCredentials))?,
        );
        Ok(self.vault()?.quick_unlock(&raw)?)
    }

    pub fn disable_quick_unlock(&self) -> Result<(), VaultFailure> {
        Ok(self.vault()?.disable_quick_unlock()?)
    }

    /// Works while locked.
    pub fn has_quick_unlock(&self) -> Result<bool, VaultFailure> {
        Ok(self.vault()?.has_quick_unlock()?)
    }
    /// Whether this vault syncs with a server; works while locked.
    pub fn is_linked(&self) -> Result<bool, VaultFailure> {
        Ok(self.vault()?.is_linked()?)
    }

    /// Server of the sync link (requires unlock).
    pub fn sync_info(&self) -> Result<Option<SyncInfo>, VaultFailure> {
        Ok(self.vault()?.sync_link()?.map(|l| SyncInfo {
            server_url: l.server_url.clone(),
        }))
    }

    /// Creates a server account for this vault and uploads it. `invite`
    /// may be empty when the server accepts open registrations.
    pub fn register_sync(
        &self,
        server_url: String,
        password: Vec<u8>,
        secret_key: String,
        device_name: String,
        invite: String,
    ) -> Result<SyncSummary, VaultFailure> {
        let password = Zeroizing::new(password);
        let secret_key = parse_secret_key(secret_key)?;
        let invite = invite.trim();
        let report = arcanum_sync::register(
            &mut *self.vault()?,
            &server_url,
            &password,
            &secret_key,
            &device_name,
            (!invite.is_empty()).then_some(invite),
        )?;
        Ok(report.into())
    }

    /// Sets up this empty database from an existing server account and
    /// leaves it unlocked.
    pub fn sign_in(
        &self,
        server_url: String,
        password: Vec<u8>,
        secret_key: String,
        device_name: String,
    ) -> Result<SyncSummary, VaultFailure> {
        let password = Zeroizing::new(password);
        let secret_key = parse_secret_key(secret_key)?;
        let report = arcanum_sync::sign_in(
            &mut *self.vault()?,
            &server_url,
            &password,
            &secret_key,
            &device_name,
        )?;
        Ok(report.into())
    }

    /// Signs in again after the session expired or the password was
    /// changed on another device.
    pub fn reconnect_sync(
        &self,
        password: Vec<u8>,
        secret_key: String,
        device_name: String,
    ) -> Result<SyncSummary, VaultFailure> {
        let password = Zeroizing::new(password);
        let secret_key = parse_secret_key(secret_key)?;
        let report =
            arcanum_sync::reconnect(&mut *self.vault()?, &password, &secret_key, &device_name)?;
        Ok(report.into())
    }

    pub fn sync_now(&self) -> Result<SyncSummary, VaultFailure> {
        Ok(arcanum_sync::sync_now(&mut *self.vault()?)?.into())
    }

    /// Stops syncing this device; local data is kept.
    pub fn unlink_sync(&self) -> Result<(), VaultFailure> {
        Ok(arcanum_sync::unlink(&mut *self.vault()?)?)
    }

    /// Signs this device out and erases the local account; the app goes
    /// back to first-launch setup.
    pub fn sign_out(&self) -> Result<(), VaultFailure> {
        Ok(arcanum_sync::sign_out(&mut *self.vault()?)?)
    }

    pub fn list_items(&self) -> Result<Vec<VaultItem>, VaultFailure> {
        Ok(self
            .vault()?
            .items()?
            .into_iter()
            .map(VaultItem::from)
            .collect())
    }

    pub fn add_item(&self, fields: ItemFields) -> Result<VaultItem, VaultFailure> {
        Ok(self.vault()?.add_item(&fields.into())?.into())
    }

    pub fn update_item(&self, id: String, fields: ItemFields) -> Result<VaultItem, VaultFailure> {
        Ok(self.vault()?.update_item(&id, &fields.into())?.into())
    }

    pub fn delete_item(&self, id: String) -> Result<(), VaultFailure> {
        Ok(self.vault()?.delete_item(&id)?)
    }

    /// Adds many items at once (imports); returns how many.
    pub fn add_items(&self, items: Vec<ItemFields>) -> Result<u32, VaultFailure> {
        let items: Vec<ItemData> = items.into_iter().map(ItemData::from).collect();
        Ok(self.vault()?.add_items(&items)?)
    }

    /// Moves group `from` and its subgroups to `to` (empty `to` ungroups
    /// their items); returns how many items were moved.
    pub fn rename_group(&self, from: String, to: String) -> Result<u32, VaultFailure> {
        Ok(self.vault()?.rename_group(&from, &to)?)
    }

    fn vault(&self) -> Result<MutexGuard<'_, Vault>, VaultFailure> {
        self.inner
            .lock()
            .map_err(|_| VaultFailure::internal("vault mutex poisoned"))
    }
}

/// Lets the UI validate a typed Secret Key before attempting an unlock.
#[frb(sync)]
pub fn is_valid_secret_key(secret_key: String) -> bool {
    SecretKey::parse(&Zeroizing::new(secret_key)).is_ok()
}

#[frb(init)]
pub fn init_app() {
    flutter_rust_bridge::setup_default_user_utils();
}

fn parse_secret_key(input: String) -> Result<SecretKey, VaultFailure> {
    SecretKey::parse(&Zeroizing::new(input))
        .map_err(|_| VaultFailure::new(VaultFailureCode::InvalidSecretKey))
}

impl From<SyncReport> for SyncSummary {
    fn from(r: SyncReport) -> Self {
        Self {
            pulled: r.pulled,
            pushed: r.pushed,
            conflicts: r.conflicts,
        }
    }
}

impl From<SyncError> for VaultFailure {
    fn from(e: SyncError) -> Self {
        use VaultFailureCode as C;
        match e {
            SyncError::Vault(v) => v.into(),
            SyncError::InvalidUrl(_) => Self::new(C::InvalidServerUrl),
            SyncError::Network(m) => Self {
                code: C::Network,
                message: m,
            },
            SyncError::InvalidLogin => Self::new(C::InvalidLogin),
            SyncError::AccountExists => Self::new(C::AccountExists),
            SyncError::InviteRequired => Self::new(C::InviteRequired),
            SyncError::InvalidInvite => Self::new(C::InvalidInvite),
            SyncError::RegistrationClosed => Self::new(C::RegistrationClosed),
            SyncError::QuotaExceeded => Self::new(C::QuotaExceeded),
            SyncError::Unauthorized => Self::new(C::SessionExpired),
            SyncError::TooManyRequests => Self::new(C::TooManyRequests),
            SyncError::NotLinked => Self::new(C::NotLinked),
            other => Self::internal(other.to_string()),
        }
    }
}

impl From<VaultError> for VaultFailure {
    fn from(e: VaultError) -> Self {
        use VaultFailureCode as C;
        match e {
            VaultError::Unauthorized => Self::new(C::SessionExpired),
            VaultError::PasswordRequired => Self::new(C::PasswordRequired),
            VaultError::Transport(m) => Self {
                code: C::Network,
                message: m,
            },
            VaultError::WrongCredentials => Self::new(C::WrongCredentials),
            VaultError::Locked => Self::new(C::Locked),
            VaultError::NotInitialized => Self::new(C::NotInitialized),
            VaultError::AlreadyInitialized => Self::new(C::AlreadyInitialized),
            VaultError::NotFound => Self::new(C::NotFound),
            other => Self::internal(other.to_string()),
        }
    }
}

impl From<ItemFields> for ItemData {
    fn from(f: ItemFields) -> Self {
        let mut d = ItemData::default();
        d.kind = match f.kind {
            VaultItemKind::Login => ItemKind::Login,
            VaultItemKind::SecureNote => ItemKind::SecureNote,
        };
        d.title = f.title;
        d.username = f.username;
        d.password = f.password;
        d.urls = f.urls;
        d.notes = f.notes;
        d.totp = f.totp;
        d.favorite = f.favorite;
        d.group = normalize_group(&f.group);
        d
    }
}

impl From<arcanum_vault::Item> for VaultItem {
    fn from(item: arcanum_vault::Item) -> Self {
        VaultItem {
            id: item.id.clone(),
            updated_at: item.updated_at,
            fields: ItemFields::from(&item.data),
        }
    }
}

impl From<&ItemData> for ItemFields {
    fn from(d: &ItemData) -> Self {
        ItemFields {
            kind: match d.kind {
                ItemKind::Login => VaultItemKind::Login,
                ItemKind::SecureNote => VaultItemKind::SecureNote,
            },
            title: d.title.clone(),
            username: d.username.clone(),
            password: d.password.clone(),
            urls: d.urls.clone(),
            notes: d.notes.clone(),
            totp: d.totp.clone(),
            favorite: d.favorite,
            group: d.group.clone(),
        }
    }
}
