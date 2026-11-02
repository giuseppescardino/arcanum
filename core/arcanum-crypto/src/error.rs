/// Errors are deliberately coarse: callers must not be able to distinguish
/// *why* a decryption failed (wrong key, tampered data, wrong context).
#[derive(Debug, Clone, PartialEq, Eq, thiserror::Error)]
pub enum CryptoError {
    #[error("KDF parameters are below the security minimum")]
    WeakKdfParams,
    #[error("key derivation failed")]
    Kdf,
    #[error("encryption failed")]
    Encrypt,
    #[error("decryption failed")]
    Decrypt,
    #[error("unsupported envelope version {0}")]
    UnsupportedVersion(u8),
    #[error("malformed envelope")]
    MalformedEnvelope,
    #[error("invalid secret key")]
    InvalidSecretKey,
    #[error("random number generator failure")]
    Rng,
}

pub type Result<T> = core::result::Result<T, CryptoError>;
