//! Browser extension bridge: pairing and message envelope for the app's
//! loopback server. Keys cross the boundary as bytes; the Dart side keeps
//! them in the system keychain.

use arcanum_bridge::{derive, open, seal, BridgeError, Direction, EphemeralKey};
use flutter_rust_bridge::frb;

use super::vault::{VaultFailure, VaultFailureCode};

/// The app's half of a pairing.
#[derive(Debug, Clone)]
pub struct BridgePairing {
    pub app_pub: Vec<u8>,
    pub key: Vec<u8>,
    /// 6-digit code the user compares with the one the browser shows.
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

/// Answers a browser's `pair_start` with a fresh key pair.
#[frb(sync)]
pub fn bridge_pair_respond(ext_pub: Vec<u8>) -> Result<BridgePairing, VaultFailure> {
    let app = EphemeralKey::generate();
    let app_pub = app.public();
    let paired = derive(&app, &ext_pub, &app_pub, &ext_pub).map_err(invalid)?;
    Ok(BridgePairing {
        app_pub: app_pub.to_vec(),
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
    use arcanum_bridge::{derive, seal, Direction, EphemeralKey};

    #[test]
    fn pair_respond_matches_extension_side_and_roundtrips() {
        let ext = EphemeralKey::generate();
        let ext_pub = ext.public();
        let app = bridge_pair_respond(ext_pub.to_vec()).unwrap();
        let on_ext = derive(&ext, &ext_pub, &app.app_pub, &app.app_pub).unwrap();
        assert_eq!(on_ext.code, app.code);
        assert_eq!(on_ext.key.to_vec(), app.key);

        let req = seal(&on_ext.key, "c", Direction::Request, b"{\"a\":1}");
        let plain = bridge_open_request(app.key.clone(), "c".into(), req).unwrap();
        assert_eq!(plain, "{\"a\":1}");

        let res = bridge_seal_response(app.key.clone(), "c".into(), "ok".into()).unwrap();
        let back = arcanum_bridge::open(&on_ext.key, "c", Direction::Response, &res).unwrap();
        assert_eq!(back, b"ok");
    }

    #[test]
    fn bad_inputs_are_invalid_input() {
        let e = bridge_pair_respond(vec![0; 32]).err().unwrap();
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
