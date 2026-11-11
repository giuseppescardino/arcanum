import 'dart:typed_data';

import '../src/rust/api/bridge.dart' as rust;

export '../src/rust/api/bridge.dart' show BridgeAppKey, BridgePairing;

/// Pairing and envelope crypto for the browser bridge. Implemented in
/// Rust (`arcanum-bridge`); swappable so server tests run without the
/// native library. Failures throw `VaultFailure`.
abstract class BridgeCrypto {
  /// Fresh app key pair, answering the browser's commitment.
  rust.BridgeAppKey pairBegin();

  /// Checks [extPub]/[nonce] against [commit] and derives key and code.
  rust.BridgePairing pairFinish(
    rust.BridgeAppKey appKey,
    Uint8List extPub,
    Uint8List nonce,
    Uint8List commit,
  );

  String openRequest(Uint8List key, String client, String ciphertext);
  String sealResponse(Uint8List key, String client, String plaintext);
}

class RustBridgeCrypto implements BridgeCrypto {
  const RustBridgeCrypto();

  @override
  rust.BridgeAppKey pairBegin() => rust.bridgePairBegin();

  @override
  rust.BridgePairing pairFinish(
    rust.BridgeAppKey appKey,
    Uint8List extPub,
    Uint8List nonce,
    Uint8List commit,
  ) => rust.bridgePairFinish(
    secret: appKey.secret,
    extPub: extPub,
    nonce: nonce,
    commit: commit,
  );

  @override
  String openRequest(Uint8List key, String client, String ciphertext) =>
      rust.bridgeOpenRequest(key: key, client: client, ciphertext: ciphertext);

  @override
  String sealResponse(Uint8List key, String client, String plaintext) =>
      rust.bridgeSealResponse(key: key, client: client, plaintext: plaintext);
}
