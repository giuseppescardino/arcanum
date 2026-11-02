//! A deliberately simple strength estimate for the UI meter: entropy from
//! length and character pool, with penalties for the most common weak
//! patterns. It never judges a password stronger than its pool allows.

use std::collections::HashSet;

#[derive(Debug, Clone, Copy, PartialEq, Eq, PartialOrd, Ord)]
pub enum StrengthLevel {
    VeryWeak,
    Weak,
    Fair,
    Strong,
    VeryStrong,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct Strength {
    /// Estimated entropy in bits.
    pub bits: u32,
    pub level: StrengthLevel,
}

const COMMON: &[&str] = &[
    "password", "passw0rd", "123456", "qwerty", "azerty", "letmein", "welcome", "admin",
    "iloveyou", "monkey", "dragon", "abc123", "111111", "123123", "000000",
];

pub fn estimate_strength(password: &str) -> Strength {
    let chars: Vec<char> = password.chars().collect();
    if chars.is_empty() {
        return Strength {
            bits: 0,
            level: StrengthLevel::VeryWeak,
        };
    }

    let mut pool = 0u32;
    if chars.iter().any(char::is_ascii_lowercase) {
        pool += 26;
    }
    if chars.iter().any(char::is_ascii_uppercase) {
        pool += 26;
    }
    if chars.iter().any(char::is_ascii_digit) {
        pool += 10;
    }
    if chars.iter().any(|c| c.is_ascii_punctuation() || *c == ' ') {
        pool += 33;
    }
    if chars.iter().any(|c| !c.is_ascii()) {
        pool += 100;
    }

    // Repeated characters add little: count distinct ones generously.
    let distinct = chars.iter().collect::<HashSet<_>>().len();
    let effective_len = distinct as f64 + (chars.len() - distinct) as f64 * 0.25;
    let mut bits = effective_len * f64::from(pool.max(2)).log2();

    let lower = password.to_lowercase();
    if COMMON.iter().any(|w| lower.contains(w)) {
        bits = bits.min(10.0);
    }
    if is_sequence(&chars) {
        bits = bits.min(12.0);
    }

    let bits = bits.round().clamp(0.0, 1000.0) as u32;
    let level = match bits {
        0..=27 => StrengthLevel::VeryWeak,
        28..=44 => StrengthLevel::Weak,
        45..=59 => StrengthLevel::Fair,
        60..=79 => StrengthLevel::Strong,
        _ => StrengthLevel::VeryStrong,
    };
    Strength { bits, level }
}

/// "abcdef", "654321" and the like.
fn is_sequence(chars: &[char]) -> bool {
    let step = |w: &[char]| i64::from(u32::from(w[1])) - i64::from(u32::from(w[0]));
    if chars.len() < 4 {
        return false;
    }
    let first = step(&chars[..2]);
    first.abs() == 1 && chars.windows(2).all(|w| step(w) == first)
}
#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn ordering_makes_sense() {
        let levels: Vec<StrengthLevel> = [
            "",
            "abcdefgh",
            "Password123",
            "tR7#qL",
            "correct-horse-battery",
            "gK8$vQ2!mZ5@wN9&",
        ]
        .iter()
        .map(|p| estimate_strength(p).level)
        .collect();
        assert_eq!(levels[0], StrengthLevel::VeryWeak);
        assert_eq!(levels[1], StrengthLevel::VeryWeak, "sequence");
        assert_eq!(levels[2], StrengthLevel::VeryWeak, "common word");
        assert!(levels[3] <= StrengthLevel::Weak);
        assert!(levels[4] >= StrengthLevel::Strong);
        assert_eq!(levels[5], StrengthLevel::VeryStrong);
    }

    #[test]
    fn repetition_is_penalized() {
        assert!(
            estimate_strength("aaaaaaaaaaaaaaaa").bits < estimate_strength("abqzkdmwptrnxcve").bits
        );
    }
}
