//! Fixed-input vectors shared with the extension's WebCrypto code
//! (`extension/test/crypto.test.js`). `UPDATE_VECTORS=1 cargo test`
//! rewrites the file; otherwise the test fails if it is out of date.

use arcanum_bridge::{derive, seal_with_nonce, Direction, EphemeralKey};

const PATH: &str = concat!(
    env!("CARGO_MANIFEST_DIR"),
    "/../../extension/test/vectors.json"
);

#[test]
fn vectors_match_file() {
    let ext = EphemeralKey::from_scalar([1; 32]);
    let app = EphemeralKey::from_scalar([2; 32]);
    let (e, a) = (ext.public(), app.public());
    let paired = derive(&ext, &e, &a, &a).unwrap();
    let client = "client-1";
    let nonce = [7u8; 12];
    let plaintext = r#"{"id":"x","ts":0,"body":{"op":"status"}}"#;
    let vectors = serde_json::json!({
        "ext_scalar": hex::encode([1u8; 32]),
        "app_scalar": hex::encode([2u8; 32]),
        "ext_pub": hex::encode(e),
        "app_pub": hex::encode(a),
        "key": hex::encode(*paired.key),
        "code": paired.code,
        "client": client,
        "nonce": hex::encode(nonce),
        "plaintext": plaintext,
        "request_ct": seal_with_nonce(&paired.key, client, Direction::Request, plaintext.as_bytes(), nonce),
        "response_ct": seal_with_nonce(&paired.key, client, Direction::Response, plaintext.as_bytes(), nonce),
    });
    let text = serde_json::to_string_pretty(&vectors).unwrap() + "\n";
    if std::env::var_os("UPDATE_VECTORS").is_some() {
        std::fs::create_dir_all(std::path::Path::new(PATH).parent().unwrap()).unwrap();
        std::fs::write(PATH, &text).unwrap();
    }
    let on_disk = std::fs::read_to_string(PATH).unwrap_or_default();
    assert_eq!(
        on_disk, text,
        "run with UPDATE_VECTORS=1 to regenerate {PATH}"
    );
}
