//! Cryptographic core of the password manager.
//!
//! Key hierarchy (see `docs/SECURITY.md`):
//!
//! ```text
//! master password ──Argon2id──┐
//!                             ├─HKDF-SHA256─► MUK (Master Unlock Key)
//! Secret Key (device only) ───┘                 │ wraps
//!                                               ▼
//!                                         Account Key ──wraps──► Vault Key ──wraps──► Item Key ──encrypts──► item
//! ```
//!
//! Every ciphertext is an XChaCha20-Poly1305 envelope bound to its context
//! through domain-separated, length-prefixed associated data ([`Aad`]).

mod aad;
pub mod account;
pub mod aead;
mod error;
pub mod hierarchy;
pub mod kdf;
mod keys;
mod secret_key;

pub use aad::Aad;
pub use error::{CryptoError, Result};
pub use kdf::KdfParams;
pub use keys::{SymmetricKey, KEY_LEN};
pub use secret_key::{SecretKey, SECRET_KEY_LEN};
