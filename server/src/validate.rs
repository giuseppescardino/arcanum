use arcanum_crypto::account::EncryptedAccountKeys;
use arcanum_proto::limits::MAX_DEVICE_NAME_CHARS;
use uuid::Uuid;

use crate::error::{ApiError, ApiResult};

pub fn email(raw: &str) -> ApiResult<String> {
    let email = raw.trim().to_lowercase();
    let valid = (3..=254).contains(&email.len())
        && email
            .split_once('@')
            .is_some_and(|(l, d)| !l.is_empty() && !d.is_empty())
        && !email.chars().any(char::is_whitespace);
    if valid {
        Ok(email)
    } else {
        Err(ApiError::bad_request("invalid email"))
    }
}

pub fn uuid(raw: &str, what: &str) -> ApiResult<Uuid> {
    Uuid::parse_str(raw).map_err(|_| ApiError::bad_request(format!("invalid {what}")))
}

pub fn device_name(raw: &str) -> ApiResult<String> {
    let name = raw.trim();
    if name.is_empty() || name.chars().count() > MAX_DEVICE_NAME_CHARS {
        return Err(ApiError::bad_request("invalid device name"));
    }
    Ok(name.to_owned())
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
    fn email_is_normalized() {
        assert_eq!(email("  Alice@Example.COM ").unwrap(), "alice@example.com");
        for bad in ["", "a", "@b", "a@", "a b@c.d"] {
            assert!(email(bad).is_err(), "{bad}");
        }
    }

    #[test]
    fn device_name_limits() {
        assert!(device_name("  ").is_err());
        assert!(device_name(&"x".repeat(101)).is_err());
        assert_eq!(device_name(" Laptop ").unwrap(), "Laptop");
    }
}
