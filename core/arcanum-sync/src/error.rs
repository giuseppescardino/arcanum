use arcanum_crypto::CryptoError;
use arcanum_vault::VaultError;

#[derive(Debug, thiserror::Error)]
pub enum SyncError {
    #[error(transparent)]
    Vault(#[from] VaultError),
    #[error("invalid server URL: {0}")]
    InvalidUrl(&'static str),
    #[error("cannot reach the server: {0}")]
    Network(String),
    #[error("wrong email, master password or Secret Key")]
    InvalidLogin,
    #[error("an account with this email already exists")]
    EmailTaken,
    #[error("session expired, sign in again")]
    Unauthorized,
    #[error("too many attempts, try again later")]
    TooManyRequests,
    #[error("server error: {0}")]
    Server(String),
    #[error("unexpected server response: {0}")]
    Protocol(&'static str),
    #[error("this vault is not connected to a server")]
    NotLinked,
    #[error("the server was restored from a backup")]
    ServerRestored,
}

impl From<CryptoError> for SyncError {
    fn from(e: CryptoError) -> Self {
        Self::Vault(e.into())
    }
}

/// Errors surfacing inside `Vault::sync` must be `VaultError`s.
impl From<SyncError> for VaultError {
    fn from(e: SyncError) -> Self {
        match e {
            SyncError::Vault(v) => v,
            SyncError::Unauthorized => VaultError::Unauthorized,
            SyncError::ServerRestored => VaultError::ServerRestored,
            other => VaultError::Transport(other.to_string()),
        }
    }
}

pub type Result<T> = core::result::Result<T, SyncError>;
