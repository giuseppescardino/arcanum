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
    /// Day the item expires, as `YYYY-MM-DD`; a calendar date with no time zone.
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub expires_on: Option<String>,
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

/// Canonical form of an expiry day: trimmed `YYYY-MM-DD` naming a real
/// calendar date, or `None`.
pub fn normalize_expiry(value: &str) -> Option<String> {
    let v = value.trim();
    let b = v.as_bytes();
    if b.len() != 10 || b[4] != b'-' || b[7] != b'-' {
        return None;
    }
    let digits = |r: std::ops::Range<usize>| -> Option<u32> {
        let part = &v[r];
        if part.bytes().all(|c| c.is_ascii_digit()) {
            part.parse().ok()
        } else {
            None
        }
    };
    let (year, month, day) = (digits(0..4)?, digits(5..7)?, digits(8..10)?);
    let leap = year % 4 == 0 && (year % 100 != 0 || year % 400 == 0);
    let days = match month {
        1 | 3 | 5 | 7 | 8 | 10 | 12 => 31,
        4 | 6 | 9 | 11 => 30,
        2 if leap => 29,
        2 => 28,
        _ => return None,
    };
    (1..=days).contains(&day).then(|| v.to_string())
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct Item {
    pub id: String,
    pub revision: u64,
    /// Unix time in milliseconds.
    pub updated_at: i64,
    pub data: ItemData,
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn normalize_expiry_accepts_only_real_dates() {
        assert_eq!(
            normalize_expiry("2026-11-13").as_deref(),
            Some("2026-11-13")
        );
        assert_eq!(
            normalize_expiry(" 2028-02-29 ").as_deref(),
            Some("2028-02-29")
        );
        for bad in [
            "",
            "2026-02-30",
            "2027-02-29",
            "2026-13-01",
            "2026-00-10",
            "13/11/2026",
            "2026-1-3",
            "2026-11-13T00:00:00Z",
        ] {
            assert_eq!(normalize_expiry(bad), None, "{bad}");
        }
    }

    #[test]
    fn old_items_read_without_expiry_and_roundtrip_unchanged() {
        let old = r#"{"kind":"login","title":"Bank","password":"x"}"#;
        let d: ItemData = serde_json::from_str(old).unwrap();
        assert_eq!(d.expires_on, None);
        assert!(!serde_json::to_string(&d).unwrap().contains("expires_on"));
    }

    #[test]
    fn expiry_is_serialized_when_set() {
        let mut d = ItemData::default();
        d.expires_on = Some("2027-01-31".into());
        let back: ItemData = serde_json::from_str(&serde_json::to_string(&d).unwrap()).unwrap();
        assert_eq!(back.expires_on.as_deref(), Some("2027-01-31"));
    }
}
