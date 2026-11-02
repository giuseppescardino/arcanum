//! Generator, strength meter and TOTP for the UI. All synchronous: they
//! are fast and called while the user types or every second.

use arcanum_tools::{PassphraseOptions, PasswordOptions, StrengthLevel, TotpConfig};
use flutter_rust_bridge::frb;

use super::vault::{VaultFailure, VaultFailureCode};

#[derive(Debug, Clone)]
pub struct PasswordGeneratorOptions {
    pub length: u32,
    pub lowercase: bool,
    pub uppercase: bool,
    pub digits: bool,
    pub symbols: bool,
    pub avoid_ambiguous: bool,
}

#[derive(Debug, Clone)]
pub struct PassphraseGeneratorOptions {
    pub words: u32,
    pub separator: String,
    pub capitalize: bool,
    pub include_number: bool,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum PasswordStrengthLevel {
    VeryWeak,
    Weak,
    Fair,
    Strong,
    VeryStrong,
}

#[derive(Debug, Clone, Copy)]
pub struct PasswordStrength {
    pub bits: u32,
    pub level: PasswordStrengthLevel,
}

#[derive(Debug, Clone)]
pub struct TotpCode {
    pub code: String,
    pub period: u32,
    /// Seconds before this code expires.
    pub remaining: u32,
}

#[frb(sync)]
pub fn generate_password(options: PasswordGeneratorOptions) -> Result<String, VaultFailure> {
    let opts = PasswordOptions {
        length: options.length as usize,
        lowercase: options.lowercase,
        uppercase: options.uppercase,
        digits: options.digits,
        symbols: options.symbols,
        avoid_ambiguous: options.avoid_ambiguous,
    };
    arcanum_tools::generate_password(&opts)
        .map(|p| p.to_string())
        .map_err(invalid_input)
}

#[frb(sync)]
pub fn generate_passphrase(options: PassphraseGeneratorOptions) -> Result<String, VaultFailure> {
    let opts = PassphraseOptions {
        words: options.words as usize,
        separator: options.separator,
        capitalize: options.capitalize,
        include_number: options.include_number,
    };
    arcanum_tools::generate_passphrase(&opts)
        .map(|p| p.to_string())
        .map_err(invalid_input)
}

#[frb(sync)]
pub fn password_strength(password: String) -> PasswordStrength {
    let s = arcanum_tools::estimate_strength(&zeroize::Zeroizing::new(password));
    PasswordStrength {
        bits: s.bits,
        level: match s.level {
            StrengthLevel::VeryWeak => PasswordStrengthLevel::VeryWeak,
            StrengthLevel::Weak => PasswordStrengthLevel::Weak,
            StrengthLevel::Fair => PasswordStrengthLevel::Fair,
            StrengthLevel::Strong => PasswordStrengthLevel::Strong,
            StrengthLevel::VeryStrong => PasswordStrengthLevel::VeryStrong,
        },
    }
}

/// Current code for a stored TOTP secret or `otpauth://` URI.
#[frb(sync)]
pub fn totp_code(secret: String, unix_seconds: i64) -> Result<TotpCode, VaultFailure> {
    let config = TotpConfig::parse(&zeroize::Zeroizing::new(secret)).map_err(invalid_input)?;
    let now = u64::try_from(unix_seconds).unwrap_or(0);
    Ok(TotpCode {
        code: config.code_at(now),
        period: u32::try_from(config.period).unwrap_or(30),
        remaining: u32::try_from(config.remaining_at(now)).unwrap_or(0),
    })
}

#[frb(sync)]
pub fn is_valid_totp(secret: String) -> bool {
    TotpConfig::parse(&zeroize::Zeroizing::new(secret)).is_ok()
}

fn invalid_input(e: impl std::fmt::Display) -> VaultFailure {
    VaultFailure {
        code: VaultFailureCode::InvalidInput,
        message: e.to_string(),
    }
}
