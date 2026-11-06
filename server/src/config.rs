//! Server settings read from the environment.

use std::env;

/// Who may create an account (`ARCANUM_REGISTRATION`).
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum Registration {
    /// Anyone (public instances; abuse is bounded by quotas and rate limits).
    Open,
    /// Only with a single-use code from `arcanum-server invite create`.
    Invite,
    /// Nobody.
    Closed,
}

impl Registration {
    pub fn parse(s: &str) -> Option<Self> {
        match s.trim().to_ascii_lowercase().as_str() {
            "open" => Some(Self::Open),
            "invite" => Some(Self::Invite),
            "closed" => Some(Self::Closed),
            _ => None,
        }
    }

    pub fn as_str(self) -> &'static str {
        match self {
            Self::Open => "open",
            Self::Invite => "invite",
            Self::Closed => "closed",
        }
    }
}

#[derive(Debug, Clone)]
pub struct Config {
    pub registration: Registration,
    /// Upper bound on items (including deleted ones) per account.
    pub max_items_per_account: i64,
    /// Take the client IP from `X-Forwarded-For` (only behind a proxy that
    /// sets it, such as the bundled Caddy).
    pub trust_proxy: bool,
}

impl Default for Config {
    /// Safe defaults: invite-only, so an exposed server can't be used by
    /// strangers until the operator decides otherwise.
    fn default() -> Self {
        Self {
            registration: Registration::Invite,
            max_items_per_account: 20_000,
            trust_proxy: false,
        }
    }
}

impl Config {
    pub fn from_env() -> Result<Self, String> {
        let mut c = Self::default();
        if let Ok(v) = env::var("ARCANUM_REGISTRATION") {
            c.registration = Registration::parse(&v).ok_or_else(|| {
                format!("ARCANUM_REGISTRATION must be open, invite or closed (got {v:?})")
            })?;
        }
        if let Ok(v) = env::var("ARCANUM_MAX_ITEMS_PER_ACCOUNT") {
            c.max_items_per_account = v
                .trim()
                .parse()
                .ok()
                .filter(|n: &i64| *n > 0)
                .ok_or_else(|| format!("invalid ARCANUM_MAX_ITEMS_PER_ACCOUNT: {v:?}"))?;
        }
        if let Ok(v) = env::var("TRUST_PROXY") {
            c.trust_proxy = matches!(v.trim().to_ascii_lowercase().as_str(), "1" | "true" | "yes");
        }
        Ok(c)
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn registration_parsing() {
        assert_eq!(Registration::parse(" Open "), Some(Registration::Open));
        assert_eq!(Registration::parse("invite"), Some(Registration::Invite));
        assert_eq!(Registration::parse("CLOSED"), Some(Registration::Closed));
        assert_eq!(Registration::parse("yes"), None);
        assert_eq!(Config::default().registration, Registration::Invite);
    }
}
