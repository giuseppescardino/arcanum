use zeroize::Zeroizing;

use crate::random::{below, shuffle};
use crate::wordlist::words;

const LOWER: &str = "abcdefghijklmnopqrstuvwxyz";
const UPPER: &str = "ABCDEFGHIJKLMNOPQRSTUVWXYZ";
const DIGITS: &str = "0123456789";
const SYMBOLS: &str = "!#$%&()*+,-./:;<=>?@[]^_{|}~";
/// Characters easy to confuse when read or typed by hand.
const AMBIGUOUS: &str = "Il1O0o|`'\"";

pub const MIN_LENGTH: usize = 8;
pub const MAX_LENGTH: usize = 128;
pub const MIN_WORDS: usize = 3;
pub const MAX_WORDS: usize = 20;

#[derive(Debug, Clone, PartialEq, Eq, thiserror::Error)]
pub enum GeneratorError {
    #[error("length must be between {MIN_LENGTH} and {MAX_LENGTH}")]
    InvalidLength,
    #[error("select at least one character set")]
    NoCharacterSet,
    #[error("word count must be between {MIN_WORDS} and {MAX_WORDS}")]
    InvalidWordCount,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct PasswordOptions {
    pub length: usize,
    pub lowercase: bool,
    pub uppercase: bool,
    pub digits: bool,
    pub symbols: bool,
    pub avoid_ambiguous: bool,
}

impl Default for PasswordOptions {
    fn default() -> Self {
        Self {
            length: 20,
            lowercase: true,
            uppercase: true,
            digits: true,
            symbols: true,
            avoid_ambiguous: true,
        }
    }
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct PassphraseOptions {
    pub words: usize,
    pub separator: String,
    pub capitalize: bool,
    /// Appends one random digit to one random word.
    pub include_number: bool,
}

impl Default for PassphraseOptions {
    fn default() -> Self {
        Self {
            words: 5,
            separator: "-".into(),
            capitalize: true,
            include_number: true,
        }
    }
}

/// Random password using every selected character set at least once.
pub fn generate_password(opts: &PasswordOptions) -> Result<Zeroizing<String>, GeneratorError> {
    if !(MIN_LENGTH..=MAX_LENGTH).contains(&opts.length) {
        return Err(GeneratorError::InvalidLength);
    }
    let sets: Vec<Vec<char>> = [
        (opts.lowercase, LOWER),
        (opts.uppercase, UPPER),
        (opts.digits, DIGITS),
        (opts.symbols, SYMBOLS),
    ]
    .into_iter()
    .filter(|(on, _)| *on)
    .map(|(_, set)| {
        set.chars()
            .filter(|c| !(opts.avoid_ambiguous && AMBIGUOUS.contains(*c)))
            .collect()
    })
    .collect();
    if sets.is_empty() {
        return Err(GeneratorError::NoCharacterSet);
    }
    let all: Vec<char> = sets.iter().flatten().copied().collect();

    let mut chars: Zeroizing<Vec<char>> = Zeroizing::new(Vec::with_capacity(opts.length));
    for set in &sets {
        chars.push(set[below(set.len())]);
    }
    while chars.len() < opts.length {
        chars.push(all[below(all.len())]);
    }
    shuffle(&mut chars);
    Ok(Zeroizing::new(chars.iter().collect()))
}

/// Diceware-style passphrase from the EFF Large Wordlist.
pub fn generate_passphrase(opts: &PassphraseOptions) -> Result<Zeroizing<String>, GeneratorError> {
    if !(MIN_WORDS..=MAX_WORDS).contains(&opts.words) {
        return Err(GeneratorError::InvalidWordCount);
    }
    let list = words();
    let mut parts: Vec<Zeroizing<String>> = (0..opts.words)
        .map(|_| {
            let w = list[below(list.len())];
            Zeroizing::new(if opts.capitalize {
                let mut c = w.chars();
                c.next()
                    .map(|f| f.to_uppercase().collect::<String>() + c.as_str())
                    .unwrap_or_default()
            } else {
                w.to_owned()
            })
        })
        .collect();
    if opts.include_number {
        let i = below(parts.len());
        parts[i].push(char::from(b'0' + below(10) as u8));
    }
    let refs: Vec<&str> = parts.iter().map(|p| p.as_str()).collect();
    Ok(Zeroizing::new(refs.join(&opts.separator)))
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn password_has_requested_length_and_every_set() {
        for length in [MIN_LENGTH, 20, MAX_LENGTH] {
            let p = generate_password(&PasswordOptions {
                length,
                ..Default::default()
            })
            .unwrap();
            assert_eq!(p.chars().count(), length);
            assert!(p.chars().any(|c| c.is_ascii_lowercase()));
            assert!(p.chars().any(|c| c.is_ascii_uppercase()));
            assert!(p.chars().any(|c| c.is_ascii_digit()));
            assert!(p.chars().any(|c| SYMBOLS.contains(c)));
            assert!(!p.chars().any(|c| AMBIGUOUS.contains(c)));
        }
    }

    #[test]
    fn only_selected_sets_are_used() {
        let p = generate_password(&PasswordOptions {
            length: 64,
            lowercase: false,
            uppercase: false,
            digits: true,
            symbols: false,
            avoid_ambiguous: false,
        })
        .unwrap();
        assert!(p.chars().all(|c| c.is_ascii_digit()));
    }

    #[test]
    fn invalid_options_are_rejected() {
        let bad_len = PasswordOptions {
            length: 4,
            ..Default::default()
        };
        assert_eq!(
            generate_password(&bad_len),
            Err(GeneratorError::InvalidLength)
        );
        let no_sets = PasswordOptions {
            lowercase: false,
            uppercase: false,
            digits: false,
            symbols: false,
            ..Default::default()
        };
        assert_eq!(
            generate_password(&no_sets),
            Err(GeneratorError::NoCharacterSet)
        );
        let few_words = PassphraseOptions {
            words: 2,
            ..Default::default()
        };
        assert_eq!(
            generate_passphrase(&few_words),
            Err(GeneratorError::InvalidWordCount)
        );
    }

    #[test]
    fn passwords_differ() {
        let a = generate_password(&PasswordOptions::default()).unwrap();
        let b = generate_password(&PasswordOptions::default()).unwrap();
        assert_ne!(a, b);
    }

    #[test]
    fn passphrase_shape() {
        let p = generate_passphrase(&PassphraseOptions::default()).unwrap();
        let parts: Vec<&str> = p.split('-').collect();
        assert_eq!(parts.len(), 5);
        assert!(parts
            .iter()
            .all(|w| w.chars().next().unwrap().is_uppercase()));
        assert_eq!(p.chars().filter(char::is_ascii_digit).count(), 1);

        let plain = generate_passphrase(&PassphraseOptions {
            words: 4,
            separator: " ".into(),
            capitalize: false,
            include_number: false,
        })
        .unwrap();
        for w in plain.split(' ') {
            assert!(words().contains(&w), "{w}");
        }
    }
}
