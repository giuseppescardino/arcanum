//! Import and export of items.
//!
//! Two export formats: a plaintext CSV that browsers and other password
//! managers read, and a password-protected backup (Argon2id +
//! XChaCha20-Poly1305) that keeps every field. Imports recognize both,
//! plus the exports of Bitwarden (JSON, CSV), 1Password (CSV) and KeePass
//! (CSV, KeePass 2 XML).
//!
//! Everything here works on plain [`ItemData`]: it never touches the
//! store, so the caller decides what to do with the parsed items.

use std::collections::HashMap;

use arcanum_crypto::{aead, kdf, Aad, CryptoError, KdfParams};
use data_encoding::BASE64;
use serde::{Deserialize, Serialize};
use serde_json::Value;
use zeroize::Zeroizing;

use crate::model::normalize_group;
use crate::{CardData, ItemData, ItemKind, WifiData, WifiSecurity};

const BACKUP_FORMAT: &str = "arcanum-backup";
const BACKUP_VERSION: u32 = 1;
const BACKUP_LABEL: &str = "pm/backup/v1";

/// Columns of the CSV export. The first five are the ones Chrome, Edge
/// and Opera use; the rest carry what those browsers have no column for.
const CSV_HEADER: [&str; 18] = [
    "name",
    "url",
    "username",
    "password",
    "note",
    "group",
    "totp",
    "favorite",
    "type",
    "extra_urls",
    "wifi_ssid",
    "wifi_security",
    "wifi_hidden",
    "card_holder",
    "card_number",
    "card_expiry",
    "card_cvv",
    "card_pin",
];

#[derive(Debug, thiserror::Error)]
pub enum TransferError {
    #[error("unrecognized file format")]
    UnsupportedFormat,
    #[error("the backup password is required")]
    PasswordRequired,
    #[error("wrong backup password")]
    WrongPassword,
    #[error(transparent)]
    Crypto(CryptoError),
}

pub type Result<T> = core::result::Result<T, TransferError>;

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum ImportFormat {
    ArcanumBackup,
    /// Generic CSV, including the browsers' and our own export.
    Csv,
    Bitwarden,
    OnePassword,
    KeePass,
}

#[derive(Debug)]
pub struct Imported {
    pub format: ImportFormat,
    pub items: Vec<ItemData>,
    /// Entries left out because they are neither logins nor notes (cards,
    /// identities) or are empty.
    pub skipped: u32,
}

// ---------------------------------------------------------------- export

/// Plaintext CSV: anyone who gets the file reads every password.
pub fn export_csv(items: &[ItemData]) -> String {
    let mut out = String::new();
    push_csv_row(&mut out, CSV_HEADER.iter().copied());
    for d in items.iter().filter(|d| d.kind != ItemKind::Group) {
        let extra = d.urls.iter().skip(1).cloned().collect::<Vec<_>>().join(" ");
        let wifi = d.wifi.clone().unwrap_or_default();
        let card = d.card.clone().unwrap_or_default();
        let row = [
            d.title.as_str(),
            d.urls.first().map_or("", String::as_str),
            d.username.as_str(),
            d.password.as_str(),
            d.notes.as_str(),
            d.group.as_str(),
            d.totp.as_deref().unwrap_or(""),
            if d.favorite { "1" } else { "" },
            match d.kind {
                ItemKind::Login => "login",
                ItemKind::SecureNote | ItemKind::Group => "note",
                ItemKind::Wifi => "wifi",
                ItemKind::Card => "card",
            },
            extra.as_str(),
            wifi.ssid.as_str(),
            match (d.wifi.is_some(), wifi.security) {
                (false, _) => "",
                (true, WifiSecurity::Wpa) => "WPA",
                (true, WifiSecurity::Wep) => "WEP",
                (true, WifiSecurity::None) => "nopass",
            },
            if wifi.hidden { "1" } else { "" },
            card.holder.as_str(),
            card.number.as_str(),
            card.expiry.as_str(),
            card.cvv.as_str(),
            card.pin.as_str(),
        ];
        push_csv_row(&mut out, row.into_iter());
    }
    out
}

fn push_csv_row<'a>(out: &mut String, cells: impl Iterator<Item = &'a str>) {
    for (i, cell) in cells.enumerate() {
        if i > 0 {
            out.push(',');
        }
        let quote =
            cell.contains([',', '"', '\n', '\r']) || cell.starts_with(' ') || cell.ends_with(' ');
        if quote {
            out.push('"');
            out.push_str(&cell.replace('"', "\"\""));
            out.push('"');
        } else {
            out.push_str(cell);
        }
    }
    out.push_str("\r\n");
}

#[derive(Serialize, Deserialize)]
struct BackupFile {
    format: String,
    version: u32,
    kdf: KdfParams,
    /// Base64.
    salt: String,
    /// Base64 AEAD envelope of the JSON [`BackupPayload`].
    data: String,
}

#[derive(Serialize, Deserialize)]
struct BackupPayload {
    items: Vec<ItemData>,
}

/// Backup encrypted with a key derived from `password` alone, so it can be
/// restored without the account it came from.
pub fn export_backup(items: &[ItemData], password: &[u8]) -> Result<Vec<u8>> {
    let params = KdfParams::DEFAULT;
    let salt = kdf::generate_salt().map_err(TransferError::Crypto)?;
    let key = kdf::derive_backup_key(password, &salt, &params).map_err(TransferError::Crypto)?;
    let plaintext = Zeroizing::new(
        serde_json::to_vec(&BackupPayload {
            items: items.to_vec(),
        })
        .map_err(|_| TransferError::UnsupportedFormat)?,
    );
    let data = aead::seal(&key, &plaintext, &backup_aad(&salt)).map_err(TransferError::Crypto)?;
    let file = BackupFile {
        format: BACKUP_FORMAT.to_owned(),
        version: BACKUP_VERSION,
        kdf: params,
        salt: BASE64.encode(&salt),
        data: BASE64.encode(&data),
    };
    serde_json::to_vec_pretty(&file).map_err(|_| TransferError::UnsupportedFormat)
}

fn backup_aad(salt: &[u8]) -> Aad {
    Aad::new(BACKUP_LABEL)
        .u64(u64::from(BACKUP_VERSION))
        .field(salt)
}

// ---------------------------------------------------------------- import

/// Parses `data`, recognizing its format. `password` is needed only for
/// an Arcanum backup: without it the call fails with
/// [`TransferError::PasswordRequired`], so the caller can ask and retry.
pub fn import(data: &[u8], password: Option<&[u8]>) -> Result<Imported> {
    let text = std::str::from_utf8(data).map_err(|_| TransferError::UnsupportedFormat)?;
    let text = text.trim_start_matches('\u{feff}');
    let head = text.trim_start();
    let mut imported = if head.starts_with('{') {
        import_json(text, password)?
    } else if head.starts_with('<') {
        import_keepass_xml(text)?
    } else {
        import_csv(text)?
    };

    let before = imported.items.len();
    imported.items.retain(|d| !is_blank(d));
    let dropped = before - imported.items.len();
    imported.skipped = imported
        .skipped
        .saturating_add(u32::try_from(dropped).unwrap_or(u32::MAX));
    for d in &mut imported.items {
        d.group = normalize_group(&d.group);
        if d.title.trim().is_empty() {
            d.title = d.urls.first().map(|u| host_of(u)).unwrap_or_default();
        }
    }
    Ok(imported)
}

fn is_blank(d: &ItemData) -> bool {
    d.title.trim().is_empty()
        && d.username.is_empty()
        && d.password.is_empty()
        && d.urls.is_empty()
        && d.notes.trim().is_empty()
}

fn host_of(url: &str) -> String {
    let rest = url.split_once("://").map_or(url, |(_, rest)| rest);
    let host = rest.split(['/', '?', '#']).next().unwrap_or(rest);
    host.strip_prefix("www.").unwrap_or(host).to_owned()
}

fn non_empty(value: &str) -> Option<String> {
    let value = value.trim();
    (!value.is_empty()).then(|| value.to_owned())
}

fn is_truthy(value: &str) -> bool {
    matches!(
        value.trim().to_ascii_lowercase().as_str(),
        "1" | "true" | "yes" | "y"
    )
}

// ---- JSON: Arcanum backup, Bitwarden

fn import_json(text: &str, password: Option<&[u8]>) -> Result<Imported> {
    let value: Value = serde_json::from_str(text).map_err(|_| TransferError::UnsupportedFormat)?;
    if value.get("format").and_then(Value::as_str) == Some(BACKUP_FORMAT) {
        return import_backup(value, password);
    }
    if value.get("items").is_some_and(Value::is_array) {
        return import_bitwarden_json(&value);
    }
    Err(TransferError::UnsupportedFormat)
}

fn import_backup(value: Value, password: Option<&[u8]>) -> Result<Imported> {
    let file: BackupFile =
        serde_json::from_value(value).map_err(|_| TransferError::UnsupportedFormat)?;
    if file.version != BACKUP_VERSION {
        return Err(TransferError::UnsupportedFormat);
    }
    let password = password.ok_or(TransferError::PasswordRequired)?;
    let salt: [u8; kdf::SALT_LEN] = BASE64
        .decode(file.salt.as_bytes())
        .ok()
        .and_then(|s| s.try_into().ok())
        .ok_or(TransferError::UnsupportedFormat)?;
    let data = BASE64
        .decode(file.data.as_bytes())
        .map_err(|_| TransferError::UnsupportedFormat)?;
    // Refuses parameters outside the safe range (too weak, or so large
    // that opening the file would exhaust memory).
    let key = kdf::derive_backup_key(password, &salt, &file.kdf).map_err(|e| match e {
        CryptoError::WeakKdfParams => TransferError::UnsupportedFormat,
        other => TransferError::Crypto(other),
    })?;
    let plaintext = aead::open(&key, &data, &backup_aad(&salt)).map_err(|e| match e {
        CryptoError::Decrypt => TransferError::WrongPassword,
        _ => TransferError::UnsupportedFormat,
    })?;
    let payload: BackupPayload =
        serde_json::from_slice(&plaintext).map_err(|_| TransferError::UnsupportedFormat)?;
    Ok(Imported {
        format: ImportFormat::ArcanumBackup,
        items: payload.items,
        skipped: 0,
    })
}

fn import_bitwarden_json(root: &Value) -> Result<Imported> {
    // Bitwarden's own encrypted exports can't be read without its keys.
    if root.get("encrypted").and_then(Value::as_bool) == Some(true) {
        return Err(TransferError::UnsupportedFormat);
    }
    let text = |v: &Value, key: &str| -> String {
        v.get(key)
            .and_then(Value::as_str)
            .unwrap_or_default()
            .to_owned()
    };
    let folders: HashMap<String, String> = root
        .get("folders")
        .and_then(Value::as_array)
        .into_iter()
        .flatten()
        .map(|f| (text(f, "id"), text(f, "name")))
        .collect();

    let mut items = Vec::new();
    let mut skipped = 0u32;
    for entry in root
        .get("items")
        .and_then(Value::as_array)
        .into_iter()
        .flatten()
    {
        let kind = match entry.get("type").and_then(Value::as_u64) {
            Some(1) => ItemKind::Login,
            Some(2) => ItemKind::SecureNote,
            Some(3) => ItemKind::Card,
            // Identities have no counterpart here.
            _ => {
                skipped = skipped.saturating_add(1);
                continue;
            }
        };
        let mut d = ItemData::default();
        d.kind = kind;
        d.title = text(entry, "name");
        d.notes = text(entry, "notes");
        d.favorite = entry.get("favorite").and_then(Value::as_bool) == Some(true);
        d.group = entry
            .get("folderId")
            .and_then(Value::as_str)
            .and_then(|id| folders.get(id))
            .cloned()
            .unwrap_or_default();
        if let Some(card) = entry.get("card").filter(|_| kind == ItemKind::Card) {
            let month = text(card, "expMonth");
            let year = text(card, "expYear");
            let year = year.get(year.len().saturating_sub(2)..).unwrap_or_default();
            d.card = Some(CardData {
                holder: text(card, "cardholderName"),
                number: digits(&text(card, "number")),
                expiry: if month.is_empty() || year.is_empty() {
                    String::new()
                } else {
                    format!("{month:0>2}/{year}")
                },
                cvv: text(card, "code"),
                pin: String::new(),
            });
        }
        if let Some(login) = entry.get("login") {
            d.username = text(login, "username");
            d.password = text(login, "password");
            d.totp = non_empty(&text(login, "totp"));
            d.urls = login
                .get("uris")
                .and_then(Value::as_array)
                .into_iter()
                .flatten()
                .filter_map(|u| non_empty(&text(u, "uri")))
                .collect();
        }
        items.push(d);
    }
    Ok(Imported {
        format: ImportFormat::Bitwarden,
        items,
        skipped,
    })
}

fn digits(s: &str) -> String {
    s.chars().filter(char::is_ascii_digit).collect()
}

// ---- CSV

/// RFC 4180 parser: quoted cells may hold delimiters, quotes (doubled)
/// and line breaks.
fn parse_csv(text: &str, delimiter: char) -> Vec<Vec<String>> {
    let mut rows = Vec::new();
    let mut row = Vec::new();
    let mut cell = String::new();
    let mut quoted = false;
    let mut chars = text.chars().peekable();
    while let Some(c) = chars.next() {
        if quoted {
            if c == '"' {
                if chars.peek() == Some(&'"') {
                    chars.next();
                    cell.push('"');
                } else {
                    quoted = false;
                }
            } else {
                cell.push(c);
            }
        } else if c == '"' && cell.is_empty() {
            quoted = true;
        } else if c == delimiter {
            row.push(std::mem::take(&mut cell));
        } else if c == '\n' || c == '\r' {
            if c == '\r' && chars.peek() == Some(&'\n') {
                chars.next();
            }
            row.push(std::mem::take(&mut cell));
            rows.push(std::mem::take(&mut row));
        } else {
            cell.push(c);
        }
    }
    if !cell.is_empty() || !row.is_empty() {
        row.push(cell);
        rows.push(row);
    }
    rows.retain(|r| r.iter().any(|c| !c.trim().is_empty()));
    rows
}

fn import_csv(text: &str) -> Result<Imported> {
    let first_line = text.lines().next().unwrap_or_default();
    let delimiter = [',', ';', '\t']
        .into_iter()
        .max_by_key(|d| first_line.matches(*d).count())
        .unwrap_or(',');
    let mut rows = parse_csv(text, delimiter).into_iter();
    let header: Vec<String> = rows
        .next()
        .ok_or(TransferError::UnsupportedFormat)?
        .iter()
        .map(|h| h.trim().to_lowercase())
        .collect();
    let column = |names: &[&str]| header.iter().position(|h| names.contains(&h.as_str()));

    let title = column(&["name", "title", "account"]);
    let url = column(&["url", "website", "web site", "login_uri", "uri", "urls"]);
    let username = column(&["username", "login name", "login_username", "user", "login"]);
    let password = column(&["password", "login_password"]);
    let notes = column(&["note", "notes", "comments", "comment"]);
    let group = column(&["group", "folder", "grouping", "tags"]);
    let totp = column(&["totp", "otpauth", "login_totp", "otp"]);
    let favorite = column(&["favorite", "favourite"]);
    let kind = column(&["type"]);
    let extra_urls = column(&["extra_urls"]);
    let wifi_ssid = column(&["wifi_ssid"]);
    let wifi_security = column(&["wifi_security"]);
    let wifi_hidden = column(&["wifi_hidden"]);
    let card_holder = column(&["card_holder"]);
    let card_number = column(&["card_number"]);
    let card_expiry = column(&["card_expiry"]);
    let card_cvv = column(&["card_cvv"]);
    let card_pin = column(&["card_pin"]);

    // Without these it is some other table, not a credential export.
    if password.is_none() || (title.is_none() && url.is_none()) {
        return Err(TransferError::UnsupportedFormat);
    }

    let has = |name: &str| header.iter().any(|h| h == name);
    let format = if has("login_uri") || has("login_password") {
        ImportFormat::Bitwarden
    } else if has("otpauth") || has("archived") {
        ImportFormat::OnePassword
    } else if has("login name") || has("web site") || (has("group") && has("title")) {
        ImportFormat::KeePass
    } else {
        ImportFormat::Csv
    };

    let mut items = Vec::new();
    let mut skipped = 0u32;
    for row in rows {
        let cell = |index: Option<usize>| -> &str {
            index
                .and_then(|i| row.get(i))
                .map_or("", |value| value.as_str())
        };
        let type_name = cell(kind).trim().to_ascii_lowercase();
        let mut d = ItemData::default();
        d.kind = match type_name.as_str() {
            "" | "login" | "1" => ItemKind::Login,
            "note" | "securenote" | "secure_note" | "secure note" | "2" => ItemKind::SecureNote,
            "wifi" => ItemKind::Wifi,
            "card" => ItemKind::Card,
            _ => {
                skipped = skipped.saturating_add(1);
                continue;
            }
        };
        d.title = cell(title).trim().to_owned();
        d.username = cell(username).to_owned();
        d.password = cell(password).to_owned();
        d.notes = cell(notes).to_owned();
        d.totp = non_empty(cell(totp));
        d.favorite = is_truthy(cell(favorite));
        if d.kind == ItemKind::Wifi {
            d.wifi = Some(WifiData {
                ssid: cell(wifi_ssid).to_owned(),
                security: match cell(wifi_security).trim().to_ascii_lowercase().as_str() {
                    "wep" => WifiSecurity::Wep,
                    "nopass" | "none" | "" if cell(password).is_empty() => WifiSecurity::None,
                    _ => WifiSecurity::Wpa,
                },
                hidden: is_truthy(cell(wifi_hidden)),
            });
        }
        if d.kind == ItemKind::Card {
            d.card = Some(CardData {
                holder: cell(card_holder).to_owned(),
                number: digits(cell(card_number)),
                expiry: cell(card_expiry).trim().to_owned(),
                cvv: cell(card_cvv).to_owned(),
                pin: cell(card_pin).to_owned(),
            });
        }
        d.group = match format {
            // Tags are a list: file the item under the first one.
            ImportFormat::OnePassword => cell(group)
                .split([';', ','])
                .next()
                .unwrap_or_default()
                .to_owned(),
            _ => cell(group).to_owned(),
        };
        // Bitwarden puts several URIs in one cell, comma-separated.
        let separators: &[char] = if format == ImportFormat::Bitwarden {
            &[',', ' ', '\n']
        } else {
            &[' ', '\n']
        };
        d.urls = cell(url)
            .split(separators)
            .chain(cell(extra_urls).split(separators))
            .filter_map(non_empty)
            .collect();
        items.push(d);
    }

    if format == ImportFormat::KeePass {
        strip_common_root(&mut items);
    }
    Ok(Imported {
        format,
        items,
        skipped,
    })
}

/// KeePass prefixes every group with the database's root group; drop it
/// when all items share it.
fn strip_common_root(items: &mut [ItemData]) {
    let root_of = |group: &str| group.split('/').next().unwrap_or_default().to_owned();
    let Some(root) = items.first().map(|d| root_of(&d.group)) else {
        return;
    };
    if root.is_empty() || items.iter().any(|d| root_of(&d.group) != root) {
        return;
    }
    for d in items {
        let rest = d.group[root.len()..].trim_start_matches('/').to_owned();
        d.group = rest;
    }
}

// ---- KeePass 2 XML

enum Xml {
    Open(String),
    Close(String),
    Text(String),
}

/// Just enough XML for KeePass's machine-written export: elements, text,
/// CDATA and entities. Attributes, comments and declarations are skipped.
fn xml_events(src: &str) -> Vec<Xml> {
    let mut events = Vec::new();
    let mut rest = src;
    while let Some(start) = rest.find('<') {
        if start > 0 {
            events.push(Xml::Text(xml_unescape(&rest[..start])));
        }
        rest = &rest[start..];
        if let Some(body) = rest.strip_prefix("<![CDATA[") {
            let end = body.find("]]>").unwrap_or(body.len());
            events.push(Xml::Text(body[..end].to_owned()));
            rest = body.get(end + 3..).unwrap_or_default();
            continue;
        }
        let skip_until = if rest.starts_with("<!--") {
            Some("-->")
        } else if rest.starts_with("<?") {
            Some("?>")
        } else if rest.starts_with("<!") {
            Some(">")
        } else {
            None
        };
        if let Some(marker) = skip_until {
            rest = rest
                .find(marker)
                .and_then(|end| rest.get(end + marker.len()..))
                .unwrap_or_default();
            continue;
        }
        let Some(end) = rest.find('>') else { break };
        let tag = &rest[1..end];
        rest = &rest[end + 1..];
        if let Some(name) = tag.strip_prefix('/') {
            events.push(Xml::Close(name.trim().to_owned()));
        } else {
            let self_closing = tag.ends_with('/');
            let name = tag
                .trim_end_matches('/')
                .split_whitespace()
                .next()
                .unwrap_or_default()
                .to_owned();
            events.push(Xml::Open(name.clone()));
            if self_closing {
                events.push(Xml::Close(name));
            }
        }
    }
    events
}

fn xml_unescape(text: &str) -> String {
    if !text.contains('&') {
        return text.to_owned();
    }
    let mut out = String::with_capacity(text.len());
    let mut rest = text;
    while let Some(start) = rest.find('&') {
        out.push_str(&rest[..start]);
        rest = &rest[start..];
        let Some(end) = rest.find(';').filter(|end| *end <= 10) else {
            out.push('&');
            rest = &rest[1..];
            continue;
        };
        let entity = &rest[1..end];
        let decoded = match entity {
            "amp" => Some('&'),
            "lt" => Some('<'),
            "gt" => Some('>'),
            "quot" => Some('"'),
            "apos" => Some('\''),
            _ => entity
                .strip_prefix("#x")
                .and_then(|hex| u32::from_str_radix(hex, 16).ok())
                .or_else(|| entity.strip_prefix('#').and_then(|dec| dec.parse().ok()))
                .and_then(char::from_u32),
        };
        match decoded {
            Some(c) => {
                out.push(c);
                rest = &rest[end + 1..];
            }
            None => {
                out.push('&');
                rest = &rest[1..];
            }
        }
    }
    out.push_str(rest);
    out
}

fn import_keepass_xml(text: &str) -> Result<Imported> {
    if !text.contains("<KeePassFile") {
        return Err(TransferError::UnsupportedFormat);
    }
    let mut stack: Vec<String> = Vec::new();
    // Names of the open groups, root first.
    let mut groups: Vec<String> = Vec::new();
    let mut entry: Option<HashMap<String, String>> = None;
    let mut key = String::new();
    let mut value = String::new();
    // Depth of the <History> being skipped: old versions of an entry.
    let mut history: Option<usize> = None;
    let mut items = Vec::new();

    for event in xml_events(text) {
        match event {
            Xml::Open(name) => {
                stack.push(name);
                if history.is_some() {
                    continue;
                }
                match stack.last().map(String::as_str) {
                    Some("History") => history = Some(stack.len()),
                    Some("Group") => groups.push(String::new()),
                    Some("Entry") => entry = Some(HashMap::new()),
                    Some("String") => {
                        key.clear();
                        value.clear();
                    }
                    _ => {}
                }
            }
            Xml::Text(text) => {
                if history.is_some() || stack.len() < 2 {
                    continue;
                }
                let parent = stack[stack.len() - 2].as_str();
                match (parent, stack[stack.len() - 1].as_str()) {
                    ("String", "Key") => key.push_str(&text),
                    ("String", "Value") => value.push_str(&text),
                    ("Group", "Name") => {
                        if let Some(group) = groups.last_mut() {
                            group.push_str(&text);
                        }
                    }
                    _ => {}
                }
            }
            Xml::Close(name) => {
                if history == Some(stack.len()) {
                    history = None;
                } else if history.is_none() {
                    match name.as_str() {
                        "String" => {
                            if let Some(fields) = entry.as_mut() {
                                fields.insert(std::mem::take(&mut key), std::mem::take(&mut value));
                            }
                        }
                        "Entry" => {
                            if let Some(fields) = entry.take() {
                                // The first group is the database root.
                                let path = groups.iter().skip(1).cloned().collect::<Vec<_>>();
                                items.push(keepass_item(&fields, &path.join("/")));
                            }
                        }
                        "Group" => {
                            groups.pop();
                        }
                        _ => {}
                    }
                }
                stack.pop();
            }
        }
    }
    Ok(Imported {
        format: ImportFormat::KeePass,
        items,
        skipped: 0,
    })
}

fn keepass_item(fields: &HashMap<String, String>, group: &str) -> ItemData {
    let get = |key: &str| fields.get(key).cloned().unwrap_or_default();
    let mut d = ItemData::default();
    d.title = get("Title").trim().to_owned();
    d.username = get("UserName");
    d.password = get("Password");
    d.urls = non_empty(&get("URL")).into_iter().collect();
    d.notes = get("Notes");
    d.totp = non_empty(&get("otp")).or_else(|| non_empty(&get("TimeOtp-Secret-Base32")));
    d.group = group.to_owned();
    d
}
