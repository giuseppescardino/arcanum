use core::fmt;

use rand_core::{OsRng, RngCore};
use zeroize::{Zeroize, ZeroizeOnDrop};

use crate::{CryptoError, Result};

pub const KEY_LEN: usize = 32;

/// A 256-bit symmetric key, wiped from memory on drop.
#[derive(Clone, PartialEq, Eq, Zeroize, ZeroizeOnDrop)]
pub struct SymmetricKey([u8; KEY_LEN]);

impl SymmetricKey {
    pub fn generate() -> Result<Self> {
        let mut key = Self([0u8; KEY_LEN]);
        OsRng
            .try_fill_bytes(&mut key.0)
            .map_err(|_| CryptoError::Rng)?;
        Ok(key)
    }

    /// Takes ownership of raw key material and wipes the caller's copy.
    pub fn from_bytes(bytes: &mut [u8; KEY_LEN]) -> Self {
        let key = Self(*bytes);
        bytes.zeroize();
        key
    }

    pub(crate) fn from_slice(bytes: &[u8]) -> Result<Self> {
        let array: [u8; KEY_LEN] = bytes.try_into().map_err(|_| CryptoError::Decrypt)?;
        Ok(Self(array))
    }

    pub(crate) fn as_bytes(&self) -> &[u8; KEY_LEN] {
        &self.0
    }
}

impl fmt::Debug for SymmetricKey {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        f.write_str("SymmetricKey([REDACTED])")
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn generated_keys_differ() {
        let a = SymmetricKey::generate().unwrap();
        let b = SymmetricKey::generate().unwrap();
        assert_ne!(a, b);
    }

    #[test]
    fn debug_does_not_leak() {
        let mut raw = [7u8; KEY_LEN];
        let key = SymmetricKey::from_bytes(&mut raw);
        assert_eq!(raw, [0u8; KEY_LEN]);
        assert_eq!(format!("{key:?}"), "SymmetricKey([REDACTED])");
    }
}
