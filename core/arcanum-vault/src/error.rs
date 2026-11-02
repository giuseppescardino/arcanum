use arcanum_crypto::CryptoError;

#[derive(Debug, thiserror::Error)]
pub enum VaultError {
    #[error(transparent)]
    Crypto(#[from] CryptoError),
    #[error("database error: {0}")]
    Db(#[from] rusqlite::Error),
    #[error("corrupt vault data: {0}")]
    Corrupt(&'static str),
    #[error("vault is locked")]
    Locked,
    #[error("vault has not been created yet")]
    NotInitialized,
    #[error("vault already exists")]
    AlreadyInitialized,
    #[error("item not found")]
    NotFound,
    #[error("wrong master password or secret key")]
    WrongCredentials,
    #[error("sync failed: {0}")]
    Transport(String),
    #[error("the server rejected this device's session")]
    Unauthorized,
    #[error("the master password is required")]
    PasswordRequired,
    /// The server's data went back in time (restored from a backup).
    /// Handled inside sync, which starts over from scratch.
    #[error("the server was restored from a backup")]
    ServerRestored,
}

pub type Result<T> = core::result::Result<T, VaultError>;
