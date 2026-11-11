//! Pairing and message encryption between the desktop app and the
//! browser extension. Pure functions, no I/O: the app's loopback server
//! and the extension's WebCrypto code implement the same formulas (see
//! `docs/superpowers/specs/2026-11-11-browser-extension-design.md`).

mod envelope;
mod pairing;
mod replay;

pub use envelope::{open, seal, seal_with_nonce, Direction};
pub use pairing::{derive, EphemeralKey, Paired};
pub use replay::ReplayGuard;

#[derive(Debug, Clone, Copy, PartialEq, Eq, thiserror::Error)]
pub enum BridgeError {
    #[error("invalid public key")]
    InvalidKey,
    #[error("message could not be decrypted")]
    Decrypt,
    #[error("message already seen")]
    Replay,
    #[error("message timestamp outside the accepted window")]
    Stale,
}
