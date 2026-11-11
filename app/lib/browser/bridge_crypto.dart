import 'dart:typed_data';

import '../src/rust/api/bridge.dart' as rust;

export '../src/rust/api/bridge.dart' show BridgePairing;

/// Pairing and envelope crypto for the browser bridge. Implemented in
/// Rust (`arcanum-bridge`); swappable so server tests run without the
/// native library. Failures throw `VaultFailure`.
abstract class BridgeCrypto {
  rust.BridgePairing pairRespond(Uint8List extPub);
  String openRequest(Uint8List key, String client, String ciphertext);
  String sealResponse(Uint8List key, String client, String plaintext);
}

class RustBridgeCrypto implements BridgeCrypto {
  const RustBridgeCrypto();

  @override
  rust.BridgePairing pairRespond(Uint8List extPub) =>
      rust.bridgePairRespond(extPub: extPub);

  @override
  String openRequest(Uint8List key, String client, String ciphertext) =>
      rust.bridgeOpenRequest(key: key, client: client, ciphertext: ciphertext);

  @override
  String sealResponse(Uint8List key, String client, String plaintext) =>
      rust.bridgeSealResponse(key: key, client: client, plaintext: plaintext);
}
