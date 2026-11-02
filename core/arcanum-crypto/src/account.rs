//! Account creation, unlock and master password change.

use serde::{Deserialize, Serialize};

use crate::hierarchy::{unwrap_key, wrap_key};
use crate::kdf::{derive_keys, generate_salt, AuthKey, SALT_LEN};
use crate::{Aad, KdfParams, Result, SecretKey, SymmetricKey};

const ACCOUNT_KEY_LABEL: &str = "pm/account-key/v1";

/// What the server stores to let a device rebuild the Account Key.
/// Useless without both the master password and the Secret Key.
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct EncryptedAccountKeys {
    pub kdf: KdfParams,
    pub salt: [u8; SALT_LEN],
    pub wrapped_account_key: Vec<u8>,
}

#[derive(Debug)]
pub struct NewAccount {
    /// Must be shown once in the Emergency Kit and stored on the device.
    pub secret_key: SecretKey,
    pub account_key: SymmetricKey,
    pub keys: EncryptedAccountKeys,
    pub auth_key: AuthKey,
}

pub fn create(account_id: &[u8], password: &[u8], kdf: KdfParams) -> Result<NewAccount> {
    let secret_key = SecretKey::generate()?;
    let account_key = SymmetricKey::generate()?;
    let (keys, auth_key) = seal_account_key(account_id, password, &secret_key, &account_key, kdf)?;
    Ok(NewAccount {
        secret_key,
        account_key,
        keys,
        auth_key,
    })
}

pub fn unlock(
    account_id: &[u8],
    password: &[u8],
    secret_key: &SecretKey,
    keys: &EncryptedAccountKeys,
) -> Result<SymmetricKey> {
    Ok(unlock_with_auth(account_id, password, secret_key, keys)?.0)
}

/// Unlocks and also returns the server authentication key; a successful
/// unwrap proves the password is right before anything is sent.
pub fn unlock_with_auth(
    account_id: &[u8],
    password: &[u8],
    secret_key: &SecretKey,
    keys: &EncryptedAccountKeys,
) -> Result<(SymmetricKey, AuthKey)> {
    let derived = derive_keys(password, secret_key, &keys.salt, &keys.kdf)?;
    let account_key = unwrap_key(&derived.muk, &keys.wrapped_account_key, &aad(account_id))?;
    Ok((account_key, derived.auth_key))
}

/// Re-wraps the existing Account Key under a new password with a fresh
/// salt. Vault and item keys are untouched, so no data is re-encrypted.
/// The returned auth key must replace the server registration.
pub fn change_password(
    account_id: &[u8],
    new_password: &[u8],
    secret_key: &SecretKey,
    account_key: &SymmetricKey,
    kdf: KdfParams,
) -> Result<(EncryptedAccountKeys, AuthKey)> {
    seal_account_key(account_id, new_password, secret_key, account_key, kdf)
}

fn seal_account_key(
    account_id: &[u8],
    password: &[u8],
    secret_key: &SecretKey,
    account_key: &SymmetricKey,
    kdf: KdfParams,
) -> Result<(EncryptedAccountKeys, AuthKey)> {
    let salt = generate_salt()?;
    let derived = derive_keys(password, secret_key, &salt, &kdf)?;
    let keys = EncryptedAccountKeys {
        kdf,
        salt,
        wrapped_account_key: wrap_key(&derived.muk, account_key, &aad(account_id))?,
    };
    Ok((keys, derived.auth_key))
}
fn aad(account_id: &[u8]) -> Aad {
    Aad::new(ACCOUNT_KEY_LABEL).field(account_id)
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::CryptoError;

    const ID: &[u8] = b"user@example.com";

    #[test]
    fn create_then_unlock() {
        let acc = create(ID, b"pw", KdfParams::DEFAULT).unwrap();
        let key = unlock(ID, b"pw", &acc.secret_key, &acc.keys).unwrap();
        assert_eq!(key, acc.account_key);
    }

    #[test]
    fn unlock_requires_password_secret_key_and_account_id() {
        let acc = create(ID, b"pw", KdfParams::DEFAULT).unwrap();
        let other_sk = SecretKey::generate().unwrap();
        assert_eq!(
            unlock(ID, b"pX", &acc.secret_key, &acc.keys),
            Err(CryptoError::Decrypt)
        );
        assert_eq!(
            unlock(ID, b"pw", &other_sk, &acc.keys),
            Err(CryptoError::Decrypt)
        );
        assert_eq!(
            unlock(b"eve@example.com", b"pw", &acc.secret_key, &acc.keys),
            Err(CryptoError::Decrypt)
        );
    }

    #[test]
    fn server_cannot_downgrade_kdf() {
        let acc = create(ID, b"pw", KdfParams::DEFAULT).unwrap();
        let mut tampered = acc.keys.clone();
        tampered.kdf.iterations = 1;
        assert_eq!(
            unlock(ID, b"pw", &acc.secret_key, &tampered),
            Err(CryptoError::WeakKdfParams)
        );
    }

    #[test]
    fn change_password_keeps_account_key() {
        let acc = create(ID, b"old", KdfParams::DEFAULT).unwrap();
        let (new_keys, new_auth) = change_password(
            ID,
            b"new",
            &acc.secret_key,
            &acc.account_key,
            KdfParams::DEFAULT,
        )
        .unwrap();
        assert_ne!(new_keys.salt, acc.keys.salt);
        assert_ne!(new_auth, acc.auth_key);
        let (_, auth) = unlock_with_auth(ID, b"new", &acc.secret_key, &new_keys).unwrap();
        assert_eq!(auth, new_auth);
        assert_eq!(
            unlock(ID, b"new", &acc.secret_key, &new_keys).unwrap(),
            acc.account_key
        );
        assert_eq!(
            unlock(ID, b"old", &acc.secret_key, &new_keys),
            Err(CryptoError::Decrypt)
        );
    }
}
