//! JSON wire format of the sync API (`/v1/...`). Binary fields are base64.
//!
//! Everything secret travels encrypted: the server only ever sees OPAQUE
//! messages, wrapped keys and item ciphertexts.

use arcanum_crypto::account::EncryptedAccountKeys;
use arcanum_crypto::KdfParams;
use serde::{Deserialize, Serialize};

pub use opaque_ke;

/// OPAQUE cipher suite shared by client and server. The OPAQUE "password"
/// is the client's `AuthKey`, already stretched with Argon2id and mixed
/// with the Secret Key, so no extra key-stretching function is needed.
pub struct OpaqueSuite;

impl opaque_ke::CipherSuite for OpaqueSuite {
    type OprfCs = opaque_ke::Ristretto255;
    type KeyExchange = opaque_ke::TripleDh<opaque_ke::Ristretto255, sha2::Sha512>;
    type Ksf = opaque_ke::ksf::Identity;
}

/// OPAQUE login context, so transcripts can't be replayed against
/// another protocol using the same suite.
pub const OPAQUE_CONTEXT: &[u8] = b"pm-sync/opaque/v1";

/// Upper bounds enforced by the server (and respected by clients).
pub mod limits {
    pub const MAX_PUSH_ITEMS: usize = 500;
    pub const MAX_PULL_ITEMS: i64 = 500;
    pub const MAX_CIPHERTEXT_BYTES: usize = 1024 * 1024;
    pub const MAX_DEVICE_NAME_CHARS: usize = 100;
}

pub mod b64 {
    use base64::engine::general_purpose::STANDARD;
    use base64::Engine;
    use serde::{de, Deserialize, Deserializer, Serializer};

    pub fn serialize<S: Serializer>(bytes: &[u8], s: S) -> Result<S::Ok, S::Error> {
        s.serialize_str(&STANDARD.encode(bytes))
    }

    pub fn deserialize<'de, D: Deserializer<'de>>(d: D) -> Result<Vec<u8>, D::Error> {
        let s = String::deserialize(d)?;
        STANDARD.decode(s).map_err(de::Error::custom)
    }
}

// ---- Registration -------------------------------------------------------

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct RegisterStartRequest {
    pub email: String,
    #[serde(with = "b64")]
    pub message: Vec<u8>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct OpaqueMessage {
    #[serde(with = "b64")]
    pub message: Vec<u8>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct RegisterFinishRequest {
    pub email: String,
    #[serde(with = "b64")]
    pub message: Vec<u8>,
    /// Chosen by the client (it is bound into the Account Key's AAD).
    pub account_id: String,
    pub account_keys: EncryptedAccountKeys,
    pub vault: VaultRecord,
    pub device_name: String,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct VaultRecord {
    pub id: String,
    #[serde(with = "b64")]
    pub wrapped_key: Vec<u8>,
}

// ---- Login --------------------------------------------------------------

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct PreloginRequest {
    pub email: String,
}

/// Returned for every email, existing or not, so it can't be used to
/// enumerate accounts.
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct PreloginResponse {
    pub kdf: KdfParams,
    pub salt: [u8; arcanum_crypto::kdf::SALT_LEN],
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct LoginStartRequest {
    pub email: String,
    #[serde(with = "b64")]
    pub message: Vec<u8>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct LoginStartResponse {
    pub login_id: String,
    #[serde(with = "b64")]
    pub message: Vec<u8>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct LoginFinishRequest {
    pub login_id: String,
    #[serde(with = "b64")]
    pub message: Vec<u8>,
    pub device_name: String,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct SessionResponse {
    /// Bearer token for `Authorization: Bearer ...`.
    pub token: String,
    pub account_id: String,
    pub account_keys: EncryptedAccountKeys,
    pub vaults: Vec<VaultRecord>,
}

// ---- Password change (authenticated) ------------------------------------

/// A session token alone is not enough to change the password: the client
/// must also prove the *current* one with a fresh OPAQUE login (started
/// with `/v1/login/start`, finished here instead of `/v1/login/finish`).
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct PasswordFinishRequest {
    pub login_id: String,
    /// OPAQUE `CredentialFinalization` for the current password.
    #[serde(with = "b64")]
    pub login_message: Vec<u8>,
    /// OPAQUE `RegistrationUpload` for the new password.
    #[serde(with = "b64")]
    pub message: Vec<u8>,
    pub account_keys: EncryptedAccountKeys,
}

// ---- Sync (authenticated) -----------------------------------------------

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct ItemRecord {
    pub id: String,
    pub vault_id: String,
    /// Client revision, bound into the ciphertext's AAD.
    pub revision: u64,
    #[serde(with = "b64")]
    pub wrapped_key: Vec<u8>,
    #[serde(with = "b64")]
    pub ciphertext: Vec<u8>,
    pub deleted: bool,
    /// Unix ms, as reported by the writing client.
    pub updated_at: i64,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct PullResponse {
    pub items: Vec<ItemRecord>,
    /// Pass back as `since` on the next pull.
    pub cursor: i64,
    /// More changes are waiting; pull again with the new cursor.
    pub has_more: bool,
    /// Identifies the server's data set. It changes when the database is
    /// restored from a backup, telling clients to resync from scratch.
    /// Empty from servers that predate it.
    #[serde(default)]
    pub epoch: String,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct PushRequest {
    pub items: Vec<PushItem>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct PushItem {
    /// Revision the client last saw from the server, `None` for new items.
    /// The server rejects the write if its copy has moved on.
    pub base_revision: Option<u64>,
    pub item: ItemRecord,
}

#[derive(Debug, Clone, Default, Serialize, Deserialize)]
pub struct PushResponse {
    pub accepted: Vec<String>,
    /// Current server copies of the rejected items.
    pub conflicts: Vec<ItemRecord>,
}

// ---- Devices ------------------------------------------------------------

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct DeviceInfo {
    pub id: String,
    pub name: String,
    pub created_at: i64,
    pub last_used_at: i64,
    pub current: bool,
}

// ---- Errors -------------------------------------------------------------

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum ErrorCode {
    BadRequest,
    Unauthorized,
    InvalidLogin,
    EmailTaken,
    NotFound,
    TooManyRequests,
    /// The pull cursor is ahead of the server: its database went back in
    /// time (restored from a backup). Resync from scratch.
    CursorAhead,
    Internal,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ErrorResponse {
    pub error: ErrorCode,
    pub message: String,
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn binary_fields_are_base64() {
        let rec = OpaqueMessage {
            message: vec![0, 1, 2, 255],
        };
        let json = serde_json::to_string(&rec).unwrap();
        assert_eq!(json, r#"{"message":"AAEC/w=="}"#);
        let back: OpaqueMessage = serde_json::from_str(&json).unwrap();
        assert_eq!(back.message, rec.message);
    }

    #[test]
    fn invalid_base64_is_rejected() {
        assert!(serde_json::from_str::<OpaqueMessage>(r#"{"message":"!!"}"#).is_err());
    }
}
