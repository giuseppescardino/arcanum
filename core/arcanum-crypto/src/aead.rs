//! XChaCha20-Poly1305 envelopes.
//!
//! Wire format: `version (1) ‖ nonce (24) ‖ ciphertext ‖ tag (16)`.
//! The version byte is authenticated as part of the associated data.

use chacha20poly1305::aead::{Aead, KeyInit, Payload};
use chacha20poly1305::{Key, XChaCha20Poly1305, XNonce};
use rand_core::{OsRng, RngCore};
use zeroize::Zeroizing;

use crate::{Aad, CryptoError, Result, SymmetricKey};

pub const ENVELOPE_V1: u8 = 1;
pub const NONCE_LEN: usize = 24;
pub const TAG_LEN: usize = 16;
pub const OVERHEAD: usize = 1 + NONCE_LEN + TAG_LEN;

pub fn seal(key: &SymmetricKey, plaintext: &[u8], aad: &Aad) -> Result<Vec<u8>> {
    let mut nonce = [0u8; NONCE_LEN];
    OsRng
        .try_fill_bytes(&mut nonce)
        .map_err(|_| CryptoError::Rng)?;

    let full_aad = versioned_aad(ENVELOPE_V1, aad);
    let ciphertext = cipher(key)
        .encrypt(
            XNonce::from_slice(&nonce),
            Payload {
                msg: plaintext,
                aad: &full_aad,
            },
        )
        .map_err(|_| CryptoError::Encrypt)?;

    let mut envelope = Vec::with_capacity(1 + NONCE_LEN + ciphertext.len());
    envelope.push(ENVELOPE_V1);
    envelope.extend_from_slice(&nonce);
    envelope.extend_from_slice(&ciphertext);
    Ok(envelope)
}

pub fn open(key: &SymmetricKey, envelope: &[u8], aad: &Aad) -> Result<Zeroizing<Vec<u8>>> {
    if envelope.len() < OVERHEAD {
        return Err(CryptoError::MalformedEnvelope);
    }
    let (version, rest) = (envelope[0], &envelope[1..]);
    if version != ENVELOPE_V1 {
        return Err(CryptoError::UnsupportedVersion(version));
    }
    let (nonce, ciphertext) = rest.split_at(NONCE_LEN);

    let full_aad = versioned_aad(version, aad);
    cipher(key)
        .decrypt(
            XNonce::from_slice(nonce),
            Payload {
                msg: ciphertext,
                aad: &full_aad,
            },
        )
        .map(Zeroizing::new)
        .map_err(|_| CryptoError::Decrypt)
}

fn cipher(key: &SymmetricKey) -> XChaCha20Poly1305 {
    XChaCha20Poly1305::new(Key::from_slice(key.as_bytes()))
}

fn versioned_aad(version: u8, aad: &Aad) -> Vec<u8> {
    let mut out = Vec::with_capacity(1 + aad.as_bytes().len());
    out.push(version);
    out.extend_from_slice(aad.as_bytes());
    out
}

#[cfg(test)]
mod tests {
    use super::*;
    use proptest::prelude::*;

    fn aad() -> Aad {
        Aad::new("test").field(b"ctx")
    }

    #[test]
    fn round_trip() {
        let key = SymmetricKey::generate().unwrap();
        let env = seal(&key, b"hunter2", &aad()).unwrap();
        assert_eq!(env.len(), OVERHEAD + 7);
        assert_eq!(&*open(&key, &env, &aad()).unwrap(), b"hunter2");
    }

    #[test]
    fn nonces_are_unique() {
        let key = SymmetricKey::generate().unwrap();
        let a = seal(&key, b"x", &aad()).unwrap();
        let b = seal(&key, b"x", &aad()).unwrap();
        assert_ne!(a, b);
    }

    #[test]
    fn wrong_key_fails() {
        let env = seal(&SymmetricKey::generate().unwrap(), b"x", &aad()).unwrap();
        let other = SymmetricKey::generate().unwrap();
        assert_eq!(open(&other, &env, &aad()), Err(CryptoError::Decrypt));
    }

    #[test]
    fn wrong_context_fails() {
        let key = SymmetricKey::generate().unwrap();
        let env = seal(&key, b"x", &aad()).unwrap();
        let other = Aad::new("test").field(b"other");
        assert_eq!(open(&key, &env, &other), Err(CryptoError::Decrypt));
    }

    #[test]
    fn version_byte_is_checked() {
        let key = SymmetricKey::generate().unwrap();
        let mut env = seal(&key, b"x", &aad()).unwrap();
        env[0] = 2;
        assert_eq!(
            open(&key, &env, &aad()),
            Err(CryptoError::UnsupportedVersion(2))
        );
    }

    #[test]
    fn truncated_envelope_is_rejected() {
        let key = SymmetricKey::generate().unwrap();
        assert_eq!(
            open(&key, &[ENVELOPE_V1; OVERHEAD - 1], &aad()),
            Err(CryptoError::MalformedEnvelope)
        );
    }

    proptest! {
        #[test]
        fn any_bit_flip_is_detected(msg in proptest::collection::vec(any::<u8>(), 0..256), pos in any::<prop::sample::Index>(), bit in 0u8..8) {
            let key = SymmetricKey::generate().unwrap();
            let mut env = seal(&key, &msg, &aad()).unwrap();
            let i = pos.index(env.len());
            env[i] ^= 1 << bit;
            prop_assert!(open(&key, &env, &aad()).is_err());
        }

        #[test]
        fn open_never_panics_on_garbage(data in proptest::collection::vec(any::<u8>(), 0..128)) {
            let key = SymmetricKey::generate().unwrap();
            let _ = open(&key, &data, &aad());
        }
    }
}
