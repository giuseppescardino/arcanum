use serde::{Deserialize, Serialize};
use zeroize::{Zeroize, ZeroizeOnDrop};

#[derive(Debug, Clone, Copy, PartialEq, Eq, Default, Serialize, Deserialize, Zeroize)]
#[serde(rename_all = "snake_case")]
pub enum ItemKind {
    #[default]
    Login,
    SecureNote,
}

/// Everything the user typed. Serialized to JSON and encrypted as one blob,
/// so the title is as protected as the password.
#[derive(Debug, Clone, Default, PartialEq, Eq, Serialize, Deserialize, Zeroize, ZeroizeOnDrop)]
pub struct ItemData {
    // Field-level defaults (not container-level, which would conflict with
    // ZeroizeOnDrop) keep old clients' JSON readable as fields are added.
    #[serde(default)]
    pub kind: ItemKind,
    #[serde(default)]
    pub title: String,
    #[serde(default)]
    pub username: String,
    #[serde(default)]
    pub password: String,
    #[serde(default)]
    pub urls: Vec<String>,
    #[serde(default)]
    pub notes: String,
    #[serde(default)]
    pub totp: Option<String>,
    #[serde(default)]
    pub favorite: bool,
    /// Name of the group the item is filed under; empty for none.
    #[serde(default)]
    pub group: String,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct Item {
    pub id: String,
    pub revision: u64,
    /// Unix time in milliseconds.
    pub updated_at: i64,
    pub data: ItemData,
}
