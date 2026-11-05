use arcanum_crypto::account::EncryptedAccountKeys;
use arcanum_crypto::kdf::LOGIN_ID_CHARS;
use arcanum_proto::limits::MAX_DEVICE_NAME_BYTES;
use uuid::Uuid;

use crate::error::{ApiError, ApiResult};

/// The account identifier: 32 bytes in base64url without padding.
pub fn login_id(raw: &str) -> ApiResult<String> {
    let valid = raw.len() == LOGIN_ID_CHARS
        && raw
            .bytes()
            .all(|b| b.is_ascii_alphanumeric() || b == b'-' || b == b'_');
    if valid {
        Ok(raw.to_owned())
    } else {
        Err(ApiError::bad_request("invalid login id"))
    }
}

pub fn uuid(raw: &str, what: &str) -> ApiResult<Uuid> {
    Uuid::parse_str(raw).map_err(|_| ApiError::bad_request(format!("invalid {what}")))
}

/// Encrypted device name (opaque to the server).
pub fn device_name(raw: &[u8]) -> ApiResult<()> {
    if raw.is_empty() || raw.len() > MAX_DEVICE_NAME_BYTES {
        return Err(ApiError::bad_request("invalid device name"));
    }
    Ok(())
}

/// Refuse weak KDF parameters at the source, so a buggy or old client
/// can't store a vault that other devices would (rightly) refuse to open.
pub fn account_keys(keys: &EncryptedAccountKeys) -> ApiResult<()> {
    keys.kdf
        .validate()
        .map_err(|_| ApiError::bad_request("KDF parameters below minimum"))?;
    if keys.wrapped_account_key.is_empty() || keys.wrapped_account_key.len() > 1024 {
        return Err(ApiError::bad_request("invalid wrapped account key"));
    }
    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn login_id_format() {
        let ok = "a".repeat(LOGIN_ID_CHARS - 2) + "-_";
        assert_eq!(login_id(&ok).unwrap(), ok);
        for bad in [
            String::new(),
            "a".repeat(LOGIN_ID_CHARS - 1),
            "a".repeat(LOGIN_ID_CHARS + 1),
            "a".repeat(LOGIN_ID_CHARS - 1) + "=",
            "alice@example.com".into(),
        ] {
            assert!(login_id(&bad).is_err(), "{bad}");
        }
    }

    #[test]
    fn device_name_limits() {
        assert!(device_name(&[]).is_err());
        assert!(device_name(&[0; MAX_DEVICE_NAME_BYTES + 1]).is_err());
        assert!(device_name(&[0; 60]).is_ok());
    }
}
