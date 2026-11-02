//! The Secret Key: 128 random bits that never leave the user's devices
//! (and the printed Emergency Kit). Mixed into the MUK derivation, it makes
//! offline brute force of a stolen server database infeasible even with a
//! weak master password.

use core::fmt;

use data_encoding::BASE32_NOPAD;
use rand_core::{OsRng, RngCore};
use zeroize::{Zeroize, ZeroizeOnDrop, Zeroizing};

use crate::{CryptoError, Result};

pub const SECRET_KEY_LEN: usize = 16;
const PREFIX: &str = "PM1";
/// 16 bytes → 26 base32 characters, printed as `PM1-XXXXXX-XXXXX-XXXXX-XXXXX-XXXXX`.
const GROUPS: [usize; 5] = [6, 5, 5, 5, 5];

#[derive(Clone, PartialEq, Eq, Zeroize, ZeroizeOnDrop)]
pub struct SecretKey([u8; SECRET_KEY_LEN]);

impl SecretKey {
    pub fn generate() -> Result<Self> {
        let mut key = Self([0u8; SECRET_KEY_LEN]);
        OsRng
            .try_fill_bytes(&mut key.0)
            .map_err(|_| CryptoError::Rng)?;
        Ok(key)
    }

    #[cfg(test)]
    pub(crate) fn from_array(bytes: [u8; SECRET_KEY_LEN]) -> Self {
        Self(bytes)
    }

    pub(crate) fn as_bytes(&self) -> &[u8; SECRET_KEY_LEN] {
        &self.0
    }

    /// Human-readable form for the Emergency Kit.
    pub fn to_display_string(&self) -> Zeroizing<String> {
        let encoded = Zeroizing::new(BASE32_NOPAD.encode(&self.0));
        let mut out = Zeroizing::new(String::with_capacity(PREFIX.len() + 32));
        out.push_str(PREFIX);
        let mut start = 0;
        for len in GROUPS {
            out.push('-');
            out.push_str(&encoded[start..start + len]);
            start += len;
        }
        out
    }

    /// Parses user input leniently: case-insensitive, ignores dashes and
    /// whitespace, and maps the look-alikes `0`→`O`, `1`→`I`, `8`→`B`.
    pub fn parse(input: &str) -> Result<Self> {
        let normalized: Zeroizing<String> = Zeroizing::new(
            input
                .chars()
                .filter(|c| !c.is_whitespace() && *c != '-')
                .map(|c| match c.to_ascii_uppercase() {
                    '0' => 'O',
                    '1' => 'I',
                    '8' => 'B',
                    other => other,
                })
                .collect(),
        );
        let body = normalized
            .strip_prefix("PMI") // "PM1" after look-alike mapping
            .ok_or(CryptoError::InvalidSecretKey)?;
        let decoded = Zeroizing::new(
            BASE32_NOPAD
                .decode(body.as_bytes())
                .map_err(|_| CryptoError::InvalidSecretKey)?,
        );
        let bytes: [u8; SECRET_KEY_LEN] = decoded
            .as_slice()
            .try_into()
            .map_err(|_| CryptoError::InvalidSecretKey)?;
        Ok(Self(bytes))
    }
}

impl fmt::Debug for SecretKey {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        f.write_str("SecretKey([REDACTED])")
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn display_format() {
        let s = SecretKey([0u8; SECRET_KEY_LEN]).to_display_string();
        assert_eq!(&*s, "PM1-AAAAAA-AAAAA-AAAAA-AAAAA-AAAAA");
    }

    #[test]
    fn round_trip() {
        let key = SecretKey::generate().unwrap();
        let shown = key.to_display_string();
        assert_eq!(SecretKey::parse(&shown).unwrap(), key);
    }

    #[test]
    fn parse_is_lenient() {
        let key = SecretKey::generate().unwrap();
        let sloppy = key
            .to_display_string()
            .to_lowercase()
            .replace('-', " ")
            .replace('o', "0")
            .replace('i', "1");
        assert_eq!(SecretKey::parse(&sloppy).unwrap(), key);
    }

    #[test]
    fn rejects_bad_input() {
        for bad in [
            "",
            "PM1",
            "XX1-AAAAAA-AAAAA-AAAAA-AAAAA-AAAAA",
            "PM1-AAAAAA-AAAAA",
            "PM1-AAAAAA-AAAAA-AAAAA-AAAAA-AAAA9",
        ] {
            assert_eq!(
                SecretKey::parse(bad),
                Err(CryptoError::InvalidSecretKey),
                "{bad}"
            );
        }
    }

    #[test]
    fn rejects_non_canonical_trailing_bits() {
        // Last char of 26 carries only 2 data bits; 'B' sets a padding bit.
        assert_eq!(
            SecretKey::parse("PM1-AAAAAA-AAAAA-AAAAA-AAAAA-AAAAB"),
            Err(CryptoError::InvalidSecretKey)
        );
    }
}
