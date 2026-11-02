//! Local vault: item model plus an SQLite store where every item is
//! encrypted with its own key (see `arcanum_crypto::hierarchy`), and the client
//! half of sync.
//!
//! The database only ever contains ciphertext and non-secret bookkeeping
//! (ids, revisions, timestamps, tombstones), so the same rows are pushed to
//! the sync server as-is.

mod error;
mod model;
mod quick;
mod store;
mod sync;
mod vault;

pub use arcanum_crypto::kdf::AuthKey;
pub use arcanum_crypto::{KdfParams, SecretKey};
pub use error::{Result, VaultError};
pub use model::{Item, ItemData, ItemKind};
pub use quick::QUICK_UNLOCK_MAX_AGE_MS;
pub use sync::{SyncReport, SyncTransport};
pub use vault::{AccountBundle, PasswordChange, SyncLink, Vault};
