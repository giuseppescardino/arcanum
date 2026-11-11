//! Browser extension bridge: pairing and message envelope for the app's
//! loopback server. Keys cross the boundary as bytes; the Dart side keeps
//! them in the system keychain.

use arcanum_bridge::{derive, open, seal, verify_commitment, BridgeError, Direction, EphemeralKey};
use flutter_rust_bridge::frb;

use super::vault::{VaultFailure, VaultFailureCode};

/// The app's ephemeral key pair for one pairing, held by Dart only until
/// the browser reveals its key (at most the 120 s pairing window).
#[derive(Debug, Clone)]
pub struct BridgeAppKey {
    pub app_pub: Vec<u8>,
    pub secret: Vec<u8>,
}

/// Result of a pairing.
#[derive(Debug, Clone)]
pub struct BridgePairing {
    pub key: Vec<u8>,
    /// 6-digit code the user types in the app from the browser.
    pub code: String,
}

fn invalid(e: BridgeError) -> VaultFailure {
    VaultFailure {
        code: VaultFailureCode::InvalidInput,
        message: e.to_string(),
    }
}

fn key32(key: &[u8]) -> Result<[u8; 32], VaultFailure> {
    key.try_into().map_err(|_| invalid(BridgeError::InvalidKey))
}

/// Answers a browser's `pair_start` (which carries only its commitment)
/// with a fresh key pair.
#[frb(sync)]
pub fn bridge_pair_begin() -> BridgeAppKey {
    let mut secret = zeroize::Zeroizing::new([0u8; 32]);
    rand_core::RngCore::fill_bytes(&mut rand_core::OsRng, secret.as_mut());
    let app = EphemeralKey::from_scalar(*secret);
    BridgeAppKey {
        app_pub: app.public().to_vec(),
        secret: secret.to_vec(),
    }
}

/// Checks the browser's revealed key against its commitment, then derives
/// the message key and the verification code.
#[frb(sync)]
pub fn bridge_pair_finish(
    secret: Vec<u8>,
    ext_pub: Vec<u8>,
    nonce: Vec<u8>,
    commit: Vec<u8>,
) -> Result<BridgePairing, VaultFailure> {
    let secret = zeroize::Zeroizing::new(secret);
    verify_commitment(&commit, &ext_pub, &nonce).map_err(invalid)?;
    let app = EphemeralKey::from_scalar(key32(&secret)?);
    let paired = derive(&app, &ext_pub, &app.public(), &ext_pub).map_err(invalid)?;
    Ok(BridgePairing {
        key: paired.key.to_vec(),
        code: paired.code,
    })
}

/// Decrypts a request from the browser identified by `client`.
#[frb(sync)]
pub fn bridge_open_request(
    key: Vec<u8>,
    client: String,
    ciphertext: String,
) -> Result<String, VaultFailure> {
    let key = zeroize::Zeroizing::new(key32(&key)?);
    let plain = open(&key, &client, Direction::Request, &ciphertext).map_err(invalid)?;
    String::from_utf8(plain).map_err(|_| invalid(BridgeError::Decrypt))
}

/// Encrypts a response for the browser identified by `client`.
#[frb(sync)]
pub fn bridge_seal_response(
    key: Vec<u8>,
    client: String,
    plaintext: String,
) -> Result<String, VaultFailure> {
    let key = zeroize::Zeroizing::new(key32(&key)?);
    Ok(seal(
        &key,
        &client,
        Direction::Response,
        plaintext.as_bytes(),
    ))
}

#[cfg(test)]
mod tests {
    use super::*;
    use arcanum_bridge::{commitment, derive, seal, Direction, EphemeralKey};

    #[test]
    fn begin_finish_match_extension_side_and_roundtrip() {
        let ext = EphemeralKey::generate();
        let ext_pub = ext.public();
        let nonce = [4u8; 32];
        let commit = commitment(&ext_pub, &nonce).to_vec();
        let app = bridge_pair_begin();
        let paired =
            bridge_pair_finish(app.secret.clone(), ext_pub.to_vec(), nonce.to_vec(), commit)
                .unwrap();
        let on_ext = derive(&ext, &ext_pub, &app.app_pub, &app.app_pub).unwrap();
        assert_eq!(on_ext.code, paired.code);
        assert_eq!(on_ext.key.to_vec(), paired.key);

        let req = seal(&on_ext.key, "c", Direction::Request, b"{\"a\":1}");
        let plain = bridge_open_request(paired.key.clone(), "c".into(), req).unwrap();
        assert_eq!(plain, "{\"a\":1}");
        let res = bridge_seal_response(paired.key.clone(), "c".into(), "ok".into()).unwrap();
        let back = arcanum_bridge::open(&on_ext.key, "c", Direction::Response, &res).unwrap();
        assert_eq!(back, b"ok");
    }

    #[test]
    fn finish_rejects_a_key_other_than_the_committed_one() {
        let nonce = [4u8; 32];
        let commit = commitment(&EphemeralKey::generate().public(), &nonce).to_vec();
        let other = EphemeralKey::generate().public().to_vec();
        let app = bridge_pair_begin();
        let e = bridge_pair_finish(app.secret, other, nonce.to_vec(), commit)
            .err()
            .unwrap();
        assert_eq!(e.code, VaultFailureCode::InvalidInput);
    }

    #[test]
    fn bad_inputs_are_invalid_input() {
        let e = bridge_pair_finish(vec![1; 31], vec![0; 32], vec![0; 32], vec![0; 32])
            .err()
            .unwrap();
        assert_eq!(e.code, VaultFailureCode::InvalidInput);
        let e = bridge_open_request(vec![1; 31], "c".into(), "x".into())
            .err()
            .unwrap();
        assert_eq!(e.code, VaultFailureCode::InvalidInput);
        let e = bridge_open_request(vec![1; 32], "c".into(), "AAAA".into())
            .err()
            .unwrap();
        assert_eq!(e.code, VaultFailureCode::InvalidInput);
    }
}
