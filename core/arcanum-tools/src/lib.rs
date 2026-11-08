//! Tools that don't touch the vault: secure password and passphrase
//! generation, a strength estimate, TOTP (RFC 6238) codes and the offline
//! half of the breached-password check.

pub mod breach;

mod generator;
mod random;
mod strength;
mod totp;
mod wordlist;

pub use generator::{
    generate_passphrase, generate_password, GeneratorError, PassphraseOptions, PasswordOptions,
};
pub use strength::{estimate_strength, Strength, StrengthLevel};
pub use totp::{TotpAlgorithm, TotpConfig, TotpError};
