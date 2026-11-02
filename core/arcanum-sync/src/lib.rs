//! Sync client: talks to `arcanum-server` over HTTPS and drives the account
//! flows (register, sign in on a new device, sync, password change) on a
//! local [`Vault`].

mod client;
mod error;

pub use client::Client;
pub use error::{Result, SyncError};

use arcanum_crypto::kdf::derive_keys;
use arcanum_vault::{AccountBundle, KdfParams, SecretKey, SyncLink, SyncReport, Vault};

/// Creates the server account for an existing local vault and uploads it.
pub fn register(
    vault: &mut Vault,
    server_url: &str,
    email: &str,
    password: &[u8],
    secret_key: &SecretKey,
    device_name: &str,
) -> Result<SyncReport> {
    // Fails fast on a wrong password, before anything is sent.
    let auth_key = vault.auth_key(password, secret_key)?;
    let bundle = vault.account_bundle()?;
    let mut client = Client::new(server_url)?;
    let session = client.register(email, &auth_key, &bundle, device_name)?;
    vault.set_sync_link(&SyncLink {
        server_url: client.base_url().to_owned(),
        email: email.trim().to_lowercase(),
        token: session.token,
    })?;
    Ok(vault.sync(&mut client)?)
}

/// Signs an empty local database into an existing account and downloads
/// the vault. Leaves the vault unlocked.
pub fn sign_in(
    vault: &mut Vault,
    server_url: &str,
    email: &str,
    password: &[u8],
    secret_key: &SecretKey,
    device_name: &str,
) -> Result<SyncReport> {
    let mut client = Client::new(server_url)?;
    let pre = client.prelogin(email)?;
    // `derive_keys` refuses KDF parameters below the minimum, so a
    // malicious server can't make us compute a cheap auth key.
    let keys = derive_keys(password, secret_key, &pre.salt, &pre.kdf)?;
    let session = client.login(email, &keys.auth_key, device_name)?;

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
        email: email.trim().to_lowercase(),
        token: session.token,
    })?;
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
    let pre = client.prelogin(&link.email)?;
    let keys = derive_keys(password, secret_key, &pre.salt, &pre.kdf)?;
    let session = client.login(&link.email, &keys.auth_key, device_name)?;
    vault.adopt_account_keys(password, secret_key, &session.account_keys)?;
    vault.set_sync_link(&SyncLink {
        server_url: link.server_url.clone(),
        email: link.email.clone(),
        token: session.token,
    })?;
    Ok(vault.sync(&mut client)?)
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
        let email = vault
            .sync_link()?
            .ok_or(SyncError::NotLinked)?
            .email
            .clone();
        let current_auth_key = vault.auth_key(current, secret_key)?;
        linked_client(vault)?.change_password(
            &email,
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

fn linked_client(vault: &Vault) -> Result<Client> {
    let link = vault.sync_link()?.ok_or(SyncError::NotLinked)?;
    Ok(Client::new(&link.server_url)?.with_token(link.token.clone()))
}
