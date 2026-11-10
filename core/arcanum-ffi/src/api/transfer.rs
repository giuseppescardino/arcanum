//! Import and export of items. Parsing and the backup's cryptography run
//! in Rust; Dart only reads and writes the files.

use arcanum_vault::transfer::{self, TransferError};
use arcanum_vault::ItemData;
use zeroize::Zeroizing;

use super::vault::{ItemFields, VaultFailure, VaultFailureCode};

/// Format an imported file was recognized as.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum ImportFormat {
    ArcanumBackup,
    Csv,
    Bitwarden,
    OnePassword,
    KeePass,
}

/// Items read from a file, not yet added to the vault.
#[derive(Debug, Clone)]
pub struct ImportData {
    pub format: ImportFormat,
    pub items: Vec<ItemFields>,
    /// Entries left out: empty, or of a kind the vault has no place for.
    pub skipped: u32,
}

/// Plaintext CSV in the browsers' column layout.
pub fn export_csv(items: Vec<ItemFields>) -> String {
    let items: Vec<ItemData> = items.into_iter().map(ItemData::from).collect();
    transfer::export_csv(&items)
}

/// Backup encrypted with `password` (Argon2id + XChaCha20-Poly1305).
pub fn export_backup(items: Vec<ItemFields>, password: Vec<u8>) -> Result<Vec<u8>, VaultFailure> {
    let password = Zeroizing::new(password);
    let items: Vec<ItemData> = items.into_iter().map(ItemData::from).collect();
    Ok(transfer::export_backup(&items, &password)?)
}

/// Reads a file exported by Arcanum, a browser, Bitwarden, 1Password or
/// KeePass. `password` is needed only for an Arcanum backup: without it
/// the call fails with `BackupPasswordRequired`.
pub fn parse_import(data: Vec<u8>, password: Option<Vec<u8>>) -> Result<ImportData, VaultFailure> {
    let data = Zeroizing::new(data);
    let password = password.map(Zeroizing::new);
    let imported = transfer::import(&data, password.as_ref().map(|p| p.as_slice()))?;
    Ok(ImportData {
        format: match imported.format {
            transfer::ImportFormat::ArcanumBackup => ImportFormat::ArcanumBackup,
            transfer::ImportFormat::Csv => ImportFormat::Csv,
            transfer::ImportFormat::Bitwarden => ImportFormat::Bitwarden,
            transfer::ImportFormat::OnePassword => ImportFormat::OnePassword,
            transfer::ImportFormat::KeePass => ImportFormat::KeePass,
        },
        items: imported.items.iter().map(ItemFields::from).collect(),
        skipped: imported.skipped,
    })
}

impl From<TransferError> for VaultFailure {
    fn from(e: TransferError) -> Self {
        use VaultFailureCode as C;
        let code = match e {
            TransferError::UnsupportedFormat => C::UnsupportedFormat,
            TransferError::PasswordRequired => C::BackupPasswordRequired,
            TransferError::WrongPassword => C::WrongCredentials,
            TransferError::Crypto(_) => C::Internal,
        };
        Self {
            code,
            message: e.to_string(),
        }
    }
}
