//! Sync client: talks to `arcanum-server` over HTTPS and drives the account
//! flows (register, sign in on a new device, sync, password change) on a
//! local [`Vault`].
//!
//! The account is identified on the server by its login id, derived from
//! the Secret Key (`arcanum_crypto::kdf::login_id`): signing in needs only
//! the server address, the master password and the Secret Key.

pub mod breach;
mod client;
mod error;

pub use client::Client;
pub use error::{Result, SyncError};

use arcanum_crypto::kdf::{derive_keys, login_id};
use arcanum_vault::{AccountBundle, KdfParams, SecretKey, SyncLink, SyncReport, Vault};

/// A signed-in device of the account, as listed by the server.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct Device {
    pub id: String,
    /// `None` if the device hasn't set a name yet or it doesn't decrypt.
    pub name: Option<String>,
    pub created_at: i64,
    pub last_used_at: i64,
    pub current: bool,
}

/// Creates the server account for an existing local vault and uploads it.
/// `invite` is needed when the server only accepts invited registrations.
pub fn register(
    vault: &mut Vault,
    server_url: &str,
    password: &[u8],
    secret_key: &SecretKey,
    device_name: &str,
    invite: Option<&str>,
) -> Result<SyncReport> {
    // Fails fast on a wrong password, before anything is sent.
    let auth_key = vault.auth_key(password, secret_key)?;
    let bundle = vault.account_bundle()?;
    let mut client = Client::new(server_url)?;
    let session = client.register(&login_id(secret_key)?, &auth_key, &bundle, invite)?;
    vault.set_sync_link(&SyncLink {
        server_url: client.base_url().to_owned(),
        token: session.token,
    })?;
    name_this_device(vault, &client, device_name);
    Ok(vault.sync(&mut client)?)
}

/// Signs an empty local database into an existing account and downloads
/// the vault. Leaves the vault unlocked.
pub fn sign_in(
    vault: &mut Vault,
    server_url: &str,
    password: &[u8],
    secret_key: &SecretKey,
    device_name: &str,
) -> Result<SyncReport> {
    let mut client = Client::new(server_url)?;
    let id = login_id(secret_key)?;
    let pre = client.prelogin(&id)?;
    // `derive_keys` refuses KDF parameters below the minimum, so a
    // malicious server can't make us compute a cheap auth key.
    let keys = derive_keys(password, secret_key, &pre.salt, &pre.kdf)?;
    let session = client.login(&id, &keys.auth_key)?;

    let vault_record = session
        .vaults
        .first()
        .ok_or(SyncError::Protocol("account has no vault"))?;
    vault.import_account(&AccountBundle {
        account_id: session.account_id.clone(),
        keys: session.account_keys.clone(),
        vault_id: vault_record.id.clone(),
        wrapped_vault_key: vault_record.wrapped_key.clone(),
    })?;
    vault.unlock(password, secret_key)?;
    vault.set_sync_link(&SyncLink {
        server_url: client.base_url().to_owned(),
        token: session.token,
    })?;
    name_this_device(vault, &client, device_name);
    Ok(vault.sync(&mut client)?)
}

/// Signs this already-linked device in again (expired or revoked session,
/// or a password changed on another device), then syncs. `password` is the
/// account's *current* password, which may differ from the local one.
pub fn reconnect(
    vault: &mut Vault,
    password: &[u8],
    secret_key: &SecretKey,
    device_name: &str,
) -> Result<SyncReport> {
    let link = vault.sync_link()?.ok_or(SyncError::NotLinked)?;
    let mut client = Client::new(&link.server_url)?;
    let id = login_id(secret_key)?;
    let pre = client.prelogin(&id)?;
    let keys = derive_keys(password, secret_key, &pre.salt, &pre.kdf)?;
    let session = client.login(&id, &keys.auth_key)?;
    vault.adopt_account_keys(password, secret_key, &session.account_keys)?;
    vault.set_sync_link(&SyncLink {
        server_url: link.server_url.clone(),
        token: session.token,
    })?;
    name_this_device(vault, &client, device_name);
    Ok(vault.sync(&mut client)?)
}

/// The signed-in devices of this account, with their names decrypted.
/// The vault must be unlocked.
pub fn devices(vault: &Vault) -> Result<Vec<Device>> {
    linked_client(vault)?
        .devices()?
        .into_iter()
        .map(|d| {
            let name = match &d.name {
                Some(sealed) => vault.open_device_name(sealed)?,
                None => None,
            };
            Ok(Device {
                id: d.id,
                name,
                created_at: d.created_at,
                last_used_at: d.last_used_at,
                current: d.current,
            })
        })
        .collect()
}

/// Signs a device of this account out (revokes its session).
pub fn revoke_device(vault: &Vault, id: &str) -> Result<()> {
    linked_client(vault)?.revoke_device(id)
}

/// Best effort: a missing name only makes the device list less readable,
/// so it must not fail a sign-in that already succeeded.
fn name_this_device(vault: &Vault, client: &Client, device_name: &str) {
    if let Ok(sealed) = vault.seal_device_name(device_name) {
        let _ = client.set_device_name(sealed);
    }
}

/// Pull + push with the stored link. The vault must be unlocked.
pub fn sync_now(vault: &mut Vault) -> Result<SyncReport> {
    let mut client = linked_client(vault)?;
    Ok(vault.sync(&mut client)?)
}

/// Changes the master password everywhere. The server is updated first,
/// so a network failure leaves both sides on the old password.
pub fn change_password(
    vault: &mut Vault,
    current: &[u8],
    new: &[u8],
    secret_key: &SecretKey,
) -> Result<()> {
    let change = vault.prepare_password_change(current, new, secret_key, KdfParams::DEFAULT)?;
    if vault.is_linked()? {
        let current_auth_key = vault.auth_key(current, secret_key)?;
        linked_client(vault)?.change_password(
            &login_id(secret_key)?,
            &current_auth_key,
            &change.auth_key,
            &change.keys,
        )?;
    }
    vault.commit_password_change(&change)?;
    Ok(())
}

/// Signs this device out of the server; local data is kept.
pub fn unlink(vault: &mut Vault) -> Result<()> {
    if let Ok(client) = linked_client(vault) {
        // Best effort: being offline must not prevent unlinking.
        let _ = client.logout();
    }
    vault.clear_sync_link()?;
    Ok(())
}

/// Signs this device out: revokes the server session (best effort) and
/// erases the local account so another one can be set up.
pub fn sign_out(vault: &mut Vault) -> Result<()> {
    if let Ok(client) = linked_client(vault) {
        let _ = client.logout();
    }
    vault.reset()?;
    Ok(())
}

fn linked_client(vault: &Vault) -> Result<Client> {
    let link = vault.sync_link()?.ok_or(SyncError::NotLinked)?;
    Ok(Client::new(&link.server_url)?.with_token(link.token.clone()))
}
