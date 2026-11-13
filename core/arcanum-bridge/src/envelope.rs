//! Message envelope: AES-256-GCM, random 96-bit nonce, AAD binding the
//! direction and the client id. Wire format: base64(nonce ‖ ct ‖ tag).

use aes_gcm::aead::{Aead, Payload};
use aes_gcm::{Aes256Gcm, KeyInit, Nonce};
use data_encoding::BASE64;
use rand_core::{OsRng, RngCore};

use crate::BridgeError;

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum Direction {
    Request,
    Response,
}

impl Direction {
    fn label(self) -> &'static [u8] {
        match self {
            Direction::Request => b"pm/bridge-req/v1",
            Direction::Response => b"pm/bridge-res/v1",
        }
    }
}

fn aad(client: &str, dir: Direction) -> Vec<u8> {
    [dir.label(), client.as_bytes()].concat()
}

pub fn seal(key: &[u8; 32], client: &str, dir: Direction, plaintext: &[u8]) -> String {
    let mut nonce = [0u8; 12];
    OsRng.fill_bytes(&mut nonce);
    seal_with_nonce(key, client, dir, plaintext, nonce)
}

/// [seal] with a caller-chosen nonce, for test vectors only.
pub fn seal_with_nonce(
    key: &[u8; 32],
    client: &str,
    dir: Direction,
    plaintext: &[u8],
    nonce: [u8; 12],
) -> String {
    let cipher = Aes256Gcm::new(key.into());
    let aad = aad(client, dir);
    // Encryption only fails for plaintexts beyond GCM's ~64 GiB limit.
    let ct = cipher
        .encrypt(
            Nonce::from_slice(&nonce),
            Payload {
                msg: plaintext,
                aad: &aad,
            },
        )
        .unwrap_or_default();
    BASE64.encode(&[&nonce[..], &ct].concat())
}

pub fn open(
    key: &[u8; 32],
    client: &str,
    dir: Direction,
    b64: &str,
) -> Result<Vec<u8>, BridgeError> {
    let raw = BASE64
        .decode(b64.as_bytes())
        .map_err(|_| BridgeError::Decrypt)?;
    if raw.len() < 12 + 16 {
        return Err(BridgeError::Decrypt);
    }
    let (nonce, ct) = raw.split_at(12);
    let aad = aad(client, dir);
    Aes256Gcm::new(key.into())
        .decrypt(Nonce::from_slice(nonce), Payload { msg: ct, aad: &aad })
        .map_err(|_| BridgeError::Decrypt)
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::BridgeError;

    const KEY: [u8; 32] = [5; 32];

    #[test]
    fn seal_open_roundtrip() {
        let ct = seal(&KEY, "c1", Direction::Request, b"hello");
        assert_eq!(open(&KEY, "c1", Direction::Request, &ct).unwrap(), b"hello");
    }

    #[test]
    fn nonces_are_random() {
        let a = seal(&KEY, "c1", Direction::Request, b"x");
        let b = seal(&KEY, "c1", Direction::Request, b"x");
        assert_ne!(a, b);
    }

    #[test]
    fn wrong_direction_rejected() {
        let ct = seal(&KEY, "c1", Direction::Request, b"x");
        assert_eq!(
            open(&KEY, "c1", Direction::Response, &ct),
            Err(BridgeError::Decrypt)
        );
    }

    #[test]
    fn wrong_client_rejected() {
        let ct = seal(&KEY, "c1", Direction::Request, b"x");
        assert_eq!(
            open(&KEY, "c2", Direction::Request, &ct),
            Err(BridgeError::Decrypt)
        );
    }

    #[test]
    fn wrong_key_rejected() {
        let ct = seal(&KEY, "c1", Direction::Request, b"x");
        assert_eq!(
            open(&[6; 32], "c1", Direction::Request, &ct),
            Err(BridgeError::Decrypt)
        );
    }

    #[test]
    fn tampered_byte_rejected() {
        let ct = seal(&KEY, "c1", Direction::Request, b"hello");
        let mut raw = data_encoding::BASE64.decode(ct.as_bytes()).unwrap();
        raw[14] ^= 1;
        let bad = data_encoding::BASE64.encode(&raw);
        assert_eq!(
            open(&KEY, "c1", Direction::Request, &bad),
            Err(BridgeError::Decrypt)
        );
    }

    #[test]
    fn garbage_rejected() {
        assert_eq!(
            open(&KEY, "c1", Direction::Request, "%%%"),
            Err(BridgeError::Decrypt)
        );
        assert_eq!(
            open(&KEY, "c1", Direction::Request, "AAAA"),
            Err(BridgeError::Decrypt)
        );
    }
}
