//! Key derivation from the master password and Secret Key:
//! `IKM = Argon2id(password, salt) ‖ SecretKey`, then HKDF-SHA256(salt, IKM)
//! expands to the Master Unlock Key (`pm/muk/v1`) and the server
//! authentication key (`pm/auth/v1`).

use argon2::{Algorithm, Argon2, Params, Version};
use hkdf::Hkdf;
use rand_core::{OsRng, RngCore};
use serde::{Deserialize, Serialize};
use sha2::Sha256;
use zeroize::Zeroizing;

use crate::{CryptoError, Result, SecretKey, SymmetricKey, KEY_LEN, SECRET_KEY_LEN};

pub const SALT_LEN: usize = 16;
const MUK_INFO: &[u8] = b"pm/muk/v1";
const AUTH_INFO: &[u8] = b"pm/auth/v1";
const LOGIN_ID_INFO: &[u8] = b"pm/login-id/v1";
/// Length of the decoded login identifier.
pub const LOGIN_ID_LEN: usize = 32;
/// Length of the login identifier as sent on the wire (base64url, no padding).
pub const LOGIN_ID_CHARS: usize = 43;

/// Argon2id cost parameters. They are stored server-side next to the
/// wrapped account key, so clients must refuse values below the minimum to
/// stop a malicious server from downgrading them.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
pub struct KdfParams {
    pub memory_kib: u32,
    pub iterations: u32,
    pub parallelism: u32,
}

impl KdfParams {
    /// OWASP minimum for Argon2id (19 MiB, t=2).
    pub const MIN_MEMORY_KIB: u32 = 19 * 1024;
    pub const MIN_ITERATIONS: u32 = 2;
    pub const MAX_MEMORY_KIB: u32 = 2 * 1024 * 1024;
    pub const MAX_ITERATIONS: u32 = 64;
    pub const MAX_PARALLELISM: u32 = 16;

    pub const DEFAULT: Self = Self {
        memory_kib: 64 * 1024,
        iterations: 3,
        parallelism: 1,
    };

    pub fn validate(&self) -> Result<()> {
        let ok = (Self::MIN_MEMORY_KIB..=Self::MAX_MEMORY_KIB).contains(&self.memory_kib)
            && (Self::MIN_ITERATIONS..=Self::MAX_ITERATIONS).contains(&self.iterations)
            && (1..=Self::MAX_PARALLELISM).contains(&self.parallelism);
        if ok {
            Ok(())
        } else {
            Err(CryptoError::WeakKdfParams)
        }
    }
}

impl Default for KdfParams {
    fn default() -> Self {
        Self::DEFAULT
    }
}

pub fn generate_salt() -> Result<[u8; SALT_LEN]> {
    let mut salt = [0u8; SALT_LEN];
    OsRng
        .try_fill_bytes(&mut salt)
        .map_err(|_| CryptoError::Rng)?;
    Ok(salt)
}

/// 32-byte key used only to authenticate to the sync server (as the OPAQUE
/// password). Domain-separated from the MUK, so the server learns nothing
/// that helps decrypt the vault even if OPAQUE were broken.
#[derive(Clone, PartialEq, Eq, zeroize::Zeroize, zeroize::ZeroizeOnDrop)]
pub struct AuthKey([u8; KEY_LEN]);

impl AuthKey {
    pub fn as_bytes(&self) -> &[u8; KEY_LEN] {
        &self.0
    }
}

impl core::fmt::Debug for AuthKey {
    fn fmt(&self, f: &mut core::fmt::Formatter<'_>) -> core::fmt::Result {
        f.write_str("AuthKey([REDACTED])")
    }
}

pub struct DerivedKeys {
    pub muk: SymmetricKey,
    pub auth_key: AuthKey,
}

pub fn derive_muk(
    password: &[u8],
    secret_key: &SecretKey,
    salt: &[u8; SALT_LEN],
    params: &KdfParams,
) -> Result<SymmetricKey> {
    Ok(derive_keys(password, secret_key, salt, params)?.muk)
}

/// One Argon2id run, then HKDF expands the result into independent keys:
/// `MUK` (info `pm/muk/v1`) and `AuthKey` (info `pm/auth/v1`).
pub fn derive_keys(
    password: &[u8],
    secret_key: &SecretKey,
    salt: &[u8; SALT_LEN],
    params: &KdfParams,
) -> Result<DerivedKeys> {
    params.validate()?;

    let argon_params = Params::new(
        params.memory_kib,
        params.iterations,
        params.parallelism,
        Some(KEY_LEN),
    )
    .map_err(|_| CryptoError::Kdf)?;
    let argon = Argon2::new(Algorithm::Argon2id, Version::V0x13, argon_params);

    let mut ikm = Zeroizing::new([0u8; KEY_LEN + SECRET_KEY_LEN]);
    argon
        .hash_password_into(password, salt, &mut ikm[..KEY_LEN])
        .map_err(|_| CryptoError::Kdf)?;
    ikm[KEY_LEN..].copy_from_slice(secret_key.as_bytes());

    let hkdf = Hkdf::<Sha256>::new(Some(salt), ikm.as_slice());
    let mut muk = [0u8; KEY_LEN];
    hkdf.expand(MUK_INFO, &mut muk)
        .map_err(|_| CryptoError::Kdf)?;
    let mut auth_key = AuthKey([0u8; KEY_LEN]);
    hkdf.expand(AUTH_INFO, &mut auth_key.0)
        .map_err(|_| CryptoError::Kdf)?;
    Ok(DerivedKeys {
        muk: SymmetricKey::from_bytes(&mut muk),
        auth_key,
    })
}

/// The account's identifier on the sync server:
/// `HKDF-SHA256(IKM = SecretKey, info = "pm/login-id/v1")`, base64url.
///
/// It replaces the email: every device already needs the Secret Key to sign
/// in, so there is nothing extra to remember, and its 128 bits of entropy
/// make it unguessable (no account enumeration, squatting or targeted
/// lockouts). HKDF is one-way, so the server can't recover the Secret Key,
/// and the label keeps it independent of the MUK and the Auth Key.
pub fn login_id(secret_key: &SecretKey) -> Result<String> {
    let hkdf = Hkdf::<Sha256>::new(None, secret_key.as_bytes());
    let mut out = Zeroizing::new([0u8; LOGIN_ID_LEN]);
    hkdf.expand(LOGIN_ID_INFO, out.as_mut_slice())
        .map_err(|_| CryptoError::Kdf)?;
    Ok(data_encoding::BASE64URL_NOPAD.encode(out.as_slice()))
}

#[cfg(test)]
mod tests {
    use super::*;

    fn sk(byte: u8) -> SecretKey {
        SecretKey::from_array([byte; SECRET_KEY_LEN])
    }

    /// RFC 9106 §5.3 Argon2id test vector: checks the dependency itself.
    #[test]
    fn argon2id_rfc9106_vector() {
        let params = argon2::ParamsBuilder::new()
            .m_cost(32)
            .t_cost(3)
            .p_cost(4)
            .output_len(32)
            .data(argon2::AssociatedData::new(&[4u8; 12]).unwrap())
            .build()
            .unwrap();
        let secret = [3u8; 8];
        let argon =
            Argon2::new_with_secret(&secret, Algorithm::Argon2id, Version::V0x13, params).unwrap();
        let mut out = [0u8; 32];
        argon
            .hash_password_into(&[1u8; 32], &[2u8; 16], &mut out)
            .unwrap();
        assert_eq!(
            hex::encode(out),
            "0d640df58d78766c08c037a34a8b53c9d01ef0452d75b65eb52520e96b01e659"
        );
    }

    #[test]
    fn deterministic_and_sensitive_to_every_input() {
        let p = KdfParams::DEFAULT;
        let salt = [9u8; SALT_LEN];
        let base = derive_muk(b"correct horse", &sk(1), &salt, &p).unwrap();

        assert_eq!(
            base,
            derive_muk(b"correct horse", &sk(1), &salt, &p).unwrap()
        );
        assert_ne!(
            base,
            derive_muk(b"correct horsf", &sk(1), &salt, &p).unwrap()
        );
        assert_ne!(
            base,
            derive_muk(b"correct horse", &sk(2), &salt, &p).unwrap()
        );
        assert_ne!(
            base,
            derive_muk(b"correct horse", &sk(1), &[8u8; SALT_LEN], &p).unwrap()
        );
        let stronger = KdfParams { iterations: 4, ..p };
        assert_ne!(
            base,
            derive_muk(b"correct horse", &sk(1), &salt, &stronger).unwrap()
        );
    }

    #[test]
    fn auth_key_is_independent_of_muk() {
        let keys = derive_keys(b"pw", &sk(1), &[0; SALT_LEN], &KdfParams::DEFAULT).unwrap();
        assert_ne!(keys.auth_key.as_bytes(), keys.muk.as_bytes());
        assert_eq!(
            keys.muk,
            derive_muk(b"pw", &sk(1), &[0; SALT_LEN], &KdfParams::DEFAULT).unwrap()
        );
        let other = derive_keys(b"pw", &sk(2), &[0; SALT_LEN], &KdfParams::DEFAULT).unwrap();
        assert_ne!(keys.auth_key, other.auth_key);
    }

    #[test]
    fn login_id_is_stable_unique_and_separate() {
        let id = login_id(&sk(1)).unwrap();
        assert_eq!(id.len(), LOGIN_ID_CHARS);
        assert_eq!(id, login_id(&sk(1)).unwrap());
        assert_ne!(id, login_id(&sk(2)).unwrap());
        let keys = derive_keys(b"pw", &sk(1), &[0; SALT_LEN], &KdfParams::DEFAULT).unwrap();
        let raw = data_encoding::BASE64URL_NOPAD
            .decode(id.as_bytes())
            .unwrap();
        assert_ne!(raw.as_slice(), keys.auth_key.as_bytes());
        assert_ne!(raw.as_slice(), keys.muk.as_bytes());
        assert!(id
            .chars()
            .all(|c| c.is_ascii_alphanumeric() || c == '-' || c == '_'));
    }

    #[test]
    fn rejects_downgraded_params() {
        let weak = [
            KdfParams {
                memory_kib: 1024,
                ..KdfParams::DEFAULT
            },
            KdfParams {
                iterations: 1,
                ..KdfParams::DEFAULT
            },
            KdfParams {
                parallelism: 0,
                ..KdfParams::DEFAULT
            },
            KdfParams {
                memory_kib: u32::MAX,
                ..KdfParams::DEFAULT
            },
        ];
        for params in weak {
            assert_eq!(
                derive_muk(b"pw", &sk(1), &[0; SALT_LEN], &params),
                Err(CryptoError::WeakKdfParams),
                "{params:?}"
            );
        }
    }
}
