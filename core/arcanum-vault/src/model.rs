use serde::{Deserialize, Serialize};
use zeroize::{Zeroize, ZeroizeOnDrop};

#[derive(Debug, Clone, Copy, PartialEq, Eq, Default, Serialize, Deserialize, Zeroize)]
#[serde(rename_all = "snake_case")]
pub enum ItemKind {
    #[default]
    Login,
    SecureNote,
    /// Wi-Fi network: [`ItemData::wifi`], password in [`ItemData::password`].
    Wifi,
    /// Payment card: [`ItemData::card`].
    Card,
    /// Not an entry: settings of the group named in [`ItemData::group`]
    /// (its color). Stored and synced like an item, so group settings
    /// are as encrypted as everything else.
    Group,
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
    /// Group the item is filed under, as a `/`-separated path
    /// (`Work/Clients`); empty for none.
    #[serde(default)]
    pub group: String,
    /// Color of a [`ItemKind::Group`] record as 0xAARRGGBB.
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub color: Option<u32>,
    /// Network details of a [`ItemKind::Wifi`] item.
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub wifi: Option<WifiData>,
    /// Details of a [`ItemKind::Card`] item.
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub card: Option<CardData>,
}

/// Wi-Fi authentication, as named in the `WIFI:` QR code format.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Default, Serialize, Deserialize, Zeroize)]
#[serde(rename_all = "snake_case")]
pub enum WifiSecurity {
    #[default]
    Wpa,
    Wep,
    None,
}

#[derive(Debug, Clone, Default, PartialEq, Eq, Serialize, Deserialize, Zeroize)]
pub struct WifiData {
    #[serde(default)]
    pub ssid: String,
    #[serde(default)]
    pub security: WifiSecurity,
    /// The network does not broadcast its name.
    #[serde(default)]
    pub hidden: bool,
}

#[derive(Debug, Clone, Default, PartialEq, Eq, Serialize, Deserialize, Zeroize)]
pub struct CardData {
    #[serde(default)]
    pub holder: String,
    /// Digits only.
    #[serde(default)]
    pub number: String,
    /// `MM/YY`.
    #[serde(default)]
    pub expiry: String,
    #[serde(default)]
    pub cvv: String,
    #[serde(default)]
    pub pin: String,
}

/// Separates the levels of a group path.
pub const GROUP_SEPARATOR: char = '/';

/// Canonical form of a group path: levels trimmed, empty ones dropped.
pub fn normalize_group(path: &str) -> String {
    path.split(GROUP_SEPARATOR)
        .map(str::trim)
        .filter(|level| !level.is_empty())
        .collect::<Vec<_>>()
        .join("/")
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct Item {
    pub id: String,
    pub revision: u64,
    /// Unix time in milliseconds.
    pub updated_at: i64,
    pub data: ItemData,
}
