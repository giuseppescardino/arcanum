//! Pairing: an ephemeral X25519 exchange from which both sides derive the
//! long-term key and a 6-digit code the user compares in the app.

use hkdf::Hkdf;
use rand_core::OsRng;
use sha2::{Digest, Sha256};
use x25519_dalek::{PublicKey, StaticSecret};
use zeroize::Zeroizing;

use crate::BridgeError;

const PAIR_LABEL: &[u8] = b"pm/bridge-pair/v1";
const KEY_INFO: &[u8] = b"pm/bridge-key/v1";
const CODE_INFO: &[u8] = b"pm/bridge-code/v1";
const COMMIT_LABEL: &[u8] = b"pm/bridge-commit/v1";

/// Bytes of randomness the browser adds to its commitment.
pub const COMMIT_NONCE_LEN: usize = 32;

/// One side's key pair for a single pairing attempt.
pub struct EphemeralKey(StaticSecret);

impl EphemeralKey {
    pub fn generate() -> Self {
        Self(StaticSecret::random_from_rng(OsRng))
    }

    /// Fixed scalar, for test vectors only.
    pub fn from_scalar(scalar: [u8; 32]) -> Self {
        Self(StaticSecret::from(scalar))
    }

    pub fn public(&self) -> [u8; 32] {
        PublicKey::from(&self.0).to_bytes()
    }
}

/// The browser's commitment to its public key, sent before it sees the
/// app's key: `SHA-256(label ‖ ext_pub ‖ nonce)`. Without it a man in the
/// middle could pick its own key after seeing the app's and search for
/// one that gives both sides the same 6-digit code.
pub fn commitment(ext_pub: &[u8], nonce: &[u8]) -> [u8; 32] {
    Sha256::new()
        .chain_update(COMMIT_LABEL)
        .chain_update(ext_pub)
        .chain_update(nonce)
        .finalize()
        .into()
}

/// Checks a revealed key and nonce against the earlier commitment.
pub fn verify_commitment(commit: &[u8], ext_pub: &[u8], nonce: &[u8]) -> Result<(), BridgeError> {
    if nonce.len() != COMMIT_NONCE_LEN || commit != commitment(ext_pub, nonce) {
        return Err(BridgeError::BadCommitment);
    }
    Ok(())
}

/// Result of a pairing: the shared key and the verification code.
pub struct Paired {
    pub key: Zeroizing<[u8; 32]>,
    pub code: String,
}

/// Derives the key and code. `ext_pub` and `app_pub` fix the transcript
/// order on both sides; `peer` is the other side's public key.
pub fn derive(
    own: &EphemeralKey,
    ext_pub: &[u8],
    app_pub: &[u8],
    peer: &[u8],
) -> Result<Paired, BridgeError> {
    let peer: [u8; 32] = peer.try_into().map_err(|_| BridgeError::InvalidKey)?;
    if ext_pub.len() != 32 || app_pub.len() != 32 {
        return Err(BridgeError::InvalidKey);
    }
    let shared = own.0.diffie_hellman(&PublicKey::from(peer));
    if !shared.was_contributory() {
        return Err(BridgeError::InvalidKey);
    }
    let th = Sha256::new()
        .chain_update(PAIR_LABEL)
        .chain_update(ext_pub)
        .chain_update(app_pub)
        .finalize();
    let hk = Hkdf::<Sha256>::new(Some(&th), shared.as_bytes());
    let mut key = Zeroizing::new([0u8; 32]);
    let mut code = [0u8; 4];
    hk.expand(KEY_INFO, key.as_mut())
        .and_then(|()| hk.expand(CODE_INFO, &mut code))
        .map_err(|_| BridgeError::InvalidKey)?;
    let code = format!("{:06}", u32::from_be_bytes(code) % 1_000_000);
    Ok(Paired { key, code })
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::BridgeError;

    fn pair(ext: &EphemeralKey, app: &EphemeralKey) -> (Paired, Paired) {
        let (e, a) = (ext.public(), app.public());
        let on_ext = derive(ext, &e, &a, &a).unwrap();
        let on_app = derive(app, &e, &a, &e).unwrap();
        (on_ext, on_app)
    }

    #[test]
    fn both_sides_derive_same_key_and_code() {
        let (ext, app) = (EphemeralKey::generate(), EphemeralKey::generate());
        let (x, y) = pair(&ext, &app);
        assert_eq!(*x.key, *y.key);
        assert_eq!(x.code, y.code);
        assert_eq!(x.code.len(), 6);
        assert!(x.code.chars().all(|c| c.is_ascii_digit()));
    }

    #[test]
    fn mitm_changes_code() {
        let (ext, app, mallory) = (
            EphemeralKey::generate(),
            EphemeralKey::generate(),
            EphemeralKey::generate(),
        );
        let (on_ext, _) = pair(&ext, &mallory);
        let (_, on_app) = pair(&mallory, &app);
        assert_ne!(*on_ext.key, *on_app.key);
        assert_ne!(on_ext.code, on_app.code);
    }

    #[test]
    fn low_order_peer_rejected() {
        let app = EphemeralKey::generate();
        let zero = [0u8; 32];
        let r = derive(&app, &zero, &app.public(), &zero);
        assert_eq!(r.err(), Some(BridgeError::InvalidKey));
    }

    #[test]
    fn wrong_length_peer_rejected() {
        let app = EphemeralKey::generate();
        let short = [9u8; 31];
        let r = derive(&app, &short, &app.public(), &short);
        assert_eq!(r.err(), Some(BridgeError::InvalidKey));
    }

    #[test]
    fn commitment_binds_key_and_nonce() {
        let c = commitment(&[1; 32], &[2; 32]);
        assert_eq!(c, commitment(&[1; 32], &[2; 32]));
        assert_ne!(c, commitment(&[9; 32], &[2; 32]));
        assert_ne!(c, commitment(&[1; 32], &[9; 32]));
    }

    #[test]
    fn verify_commitment_rejects_another_key() {
        let c = commitment(&[1; 32], &[2; 32]);
        assert_eq!(verify_commitment(&c, &[1; 32], &[2; 32]), Ok(()));
        assert_eq!(
            verify_commitment(&c, &[7; 32], &[2; 32]),
            Err(BridgeError::BadCommitment)
        );
        assert_eq!(
            verify_commitment(&c[..31], &[1; 32], &[2; 32]),
            Err(BridgeError::BadCommitment)
        );
    }

    #[test]
    fn short_nonce_rejected() {
        let c = commitment(&[1; 32], &[2; 15]);
        assert_eq!(
            verify_commitment(&c, &[1; 32], &[2; 15]),
            Err(BridgeError::BadCommitment)
        );
    }

    #[test]
    fn fixed_scalars_are_deterministic() {
        let ext = EphemeralKey::from_scalar([1; 32]);
        let app = EphemeralKey::from_scalar([2; 32]);
        let (x, _) = pair(&ext, &app);
        let (y, _) = pair(&ext, &app);
        assert_eq!(x.code, y.code);
    }
}
