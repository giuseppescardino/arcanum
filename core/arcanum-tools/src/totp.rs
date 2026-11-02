//! TOTP (RFC 6238) over HOTP (RFC 4226).
//!
//! Accepts either a bare base32 secret (as shown by most sites, spaces and
//! lowercase allowed) or an `otpauth://totp/...` URI from a QR code.

use data_encoding::BASE32_NOPAD;
use hmac::{Hmac, Mac};
use zeroize::{Zeroize, ZeroizeOnDrop};

#[derive(Debug, Clone, Copy, PartialEq, Eq, Zeroize)]
pub enum TotpAlgorithm {
    Sha1,
    Sha256,
    Sha512,
}

#[derive(Debug, Clone, PartialEq, Eq, thiserror::Error)]
pub enum TotpError {
    #[error("invalid TOTP secret")]
    InvalidSecret,
    #[error("unsupported otpauth URI: {0}")]
    InvalidUri(&'static str),
}

#[derive(Clone, PartialEq, Eq, Zeroize, ZeroizeOnDrop)]
pub struct TotpConfig {
    secret: Vec<u8>,
    pub digits: u32,
    pub period: u64,
    pub algorithm: TotpAlgorithm,
}

impl std::fmt::Debug for TotpConfig {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        f.debug_struct("TotpConfig")
            .field("secret", &"[REDACTED]")
            .field("digits", &self.digits)
            .field("period", &self.period)
            .field("algorithm", &self.algorithm)
            .finish()
    }
}

impl TotpConfig {
    pub fn parse(input: &str) -> Result<Self, TotpError> {
        let input = input.trim();
        if input.len() > 7 && input[..7].eq_ignore_ascii_case("otpauth") {
            Self::parse_uri(input)
        } else {
            Ok(Self {
                secret: decode_secret(input)?,
                digits: 6,
                period: 30,
                algorithm: TotpAlgorithm::Sha1,
            })
        }
    }

    fn parse_uri(input: &str) -> Result<Self, TotpError> {
        let url = url::Url::parse(input).map_err(|_| TotpError::InvalidUri("malformed"))?;
        if url.scheme() != "otpauth" {
            return Err(TotpError::InvalidUri("scheme"));
        }
        if url.host_str() != Some("totp") {
            return Err(TotpError::InvalidUri("only totp is supported"));
        }
        let mut config = Self {
            secret: Vec::new(),
            digits: 6,
            period: 30,
            algorithm: TotpAlgorithm::Sha1,
        };
        for (key, value) in url.query_pairs() {
            match key.to_ascii_lowercase().as_str() {
                "secret" => config.secret = decode_secret(&value)?,
                "digits" => {
                    config.digits = value
                        .parse()
                        .ok()
                        .filter(|d| (6..=8).contains(d))
                        .ok_or(TotpError::InvalidUri("digits"))?;
                }
                "period" => {
                    config.period = value
                        .parse()
                        .ok()
                        .filter(|p| (1..=300).contains(p))
                        .ok_or(TotpError::InvalidUri("period"))?;
                }
                "algorithm" => {
                    config.algorithm = match value.to_ascii_uppercase().as_str() {
                        "SHA1" => TotpAlgorithm::Sha1,
                        "SHA256" => TotpAlgorithm::Sha256,
                        "SHA512" => TotpAlgorithm::Sha512,
                        _ => return Err(TotpError::InvalidUri("algorithm")),
                    };
                }
                _ => {}
            }
        }
        if config.secret.is_empty() {
            return Err(TotpError::InvalidSecret);
        }
        Ok(config)
    }

    /// The code valid at `unix_seconds`.
    pub fn code_at(&self, unix_seconds: u64) -> String {
        let counter = (unix_seconds / self.period).to_be_bytes();
        macro_rules! hmac {
            ($digest:ty) => {{
                // HMAC accepts keys of any length: this cannot fail.
                let Ok(mut mac) = <Hmac<$digest> as Mac>::new_from_slice(&self.secret) else {
                    unreachable!()
                };
                mac.update(&counter);
                mac.finalize().into_bytes().to_vec()
            }};
        }
        let digest = match self.algorithm {
            TotpAlgorithm::Sha1 => hmac!(sha1::Sha1),
            TotpAlgorithm::Sha256 => hmac!(sha2::Sha256),
            TotpAlgorithm::Sha512 => hmac!(sha2::Sha512),
        };
        // RFC 4226 §5.3 dynamic truncation.
        let offset = usize::from(digest[digest.len() - 1] & 0x0f);
        let bin = u32::from_be_bytes([
            digest[offset] & 0x7f,
            digest[offset + 1],
            digest[offset + 2],
            digest[offset + 3],
        ]);
        let code = bin % 10u32.pow(self.digits);
        format!("{code:0width$}", width = self.digits as usize)
    }

    /// Seconds until the code at `unix_seconds` expires.
    pub fn remaining_at(&self, unix_seconds: u64) -> u64 {
        self.period - unix_seconds % self.period
    }
}

fn decode_secret(raw: &str) -> Result<Vec<u8>, TotpError> {
    let cleaned: String = raw
        .chars()
        .filter(|c| !c.is_whitespace() && *c != '-' && *c != '=')
        .map(|c| c.to_ascii_uppercase())
        .collect();
    // Many issuers emit base32 whose last character has non-zero padding
    // bits; decode leniently by ignoring them.
    let mut spec = BASE32_NOPAD.specification();
    spec.check_trailing_bits = false;
    let lenient = spec.encoding().map_err(|_| TotpError::InvalidSecret)?;
    let secret = lenient
        .decode(cleaned.as_bytes())
        .map_err(|_| TotpError::InvalidSecret)?;
    if secret.len() < 10 {
        // < 80 bits: either a typo or an issuer we shouldn't trust.
        return Err(TotpError::InvalidSecret);
    }
    Ok(secret)
}

#[cfg(test)]
mod tests {
    use super::*;

    fn config(secret: &[u8], algorithm: TotpAlgorithm) -> TotpConfig {
        TotpConfig {
            secret: secret.to_vec(),
            digits: 8,
            period: 30,
            algorithm,
        }
    }

    /// RFC 6238 Appendix B.
    #[test]
    fn rfc6238_vectors() {
        let sha1 = config(b"12345678901234567890", TotpAlgorithm::Sha1);
        let sha256 = config(b"12345678901234567890123456789012", TotpAlgorithm::Sha256);
        let sha512 = config(
            b"1234567890123456789012345678901234567890123456789012345678901234",
            TotpAlgorithm::Sha512,
        );
        let cases: [(u64, &str, &str, &str); 6] = [
            (59, "94287082", "46119246", "90693936"),
            (1_111_111_109, "07081804", "68084774", "25091201"),
            (1_111_111_111, "14050471", "67062674", "99943326"),
            (1_234_567_890, "89005924", "91819424", "93441116"),
            (2_000_000_000, "69279037", "90698825", "38618901"),
            (20_000_000_000, "65353130", "77737706", "47863826"),
        ];
        for (t, c1, c256, c512) in cases {
            assert_eq!(sha1.code_at(t), c1, "sha1 @ {t}");
            assert_eq!(sha256.code_at(t), c256, "sha256 @ {t}");
            assert_eq!(sha512.code_at(t), c512, "sha512 @ {t}");
        }
    }

    #[test]
    fn parses_plain_base32_leniently() {
        // base32("12345678901234567890")
        let canonical = TotpConfig::parse("GEZDGNBVGY3TQOJQGEZDGNBVGY3TQOJQ").unwrap();
        let sloppy = TotpConfig::parse(" gezd gnbv gy3t qojq gezd gnbv gy3t qojq ").unwrap();
        assert_eq!(canonical, sloppy);
        assert_eq!(canonical.digits, 6);
        assert_eq!(canonical.code_at(59), "287082");
        assert_eq!(canonical.remaining_at(59), 1);
    }

    #[test]
    fn parses_otpauth_uri() {
        let c = TotpConfig::parse(
            "otpauth://totp/Example:alice@example.com?secret=GEZDGNBVGY3TQOJQGEZDGNBVGY3TQOJQ&issuer=Example&digits=8&period=60&algorithm=SHA256",
        )
        .unwrap();
        assert_eq!(
            (c.digits, c.period, c.algorithm),
            (8, 60, TotpAlgorithm::Sha256)
        );
    }

    #[test]
    fn rejects_bad_input() {
        for bad in [
            "",
            "not base32!",
            "GEZDGNBV",
            "otpauth://hotp/x?secret=GEZDGNBVGY3TQOJQGEZDGNBVGY3TQOJQ",
            "otpauth://totp/x?secret=GEZDGNBVGY3TQOJQGEZDGNBVGY3TQOJQ&digits=12",
            "otpauth://totp/x?issuer=nosecret",
        ] {
            assert!(TotpConfig::parse(bad).is_err(), "{bad}");
        }
    }

    #[test]
    fn debug_hides_secret() {
        let c = TotpConfig::parse("GEZDGNBVGY3TQOJQGEZDGNBVGY3TQOJQ").unwrap();
        assert!(!format!("{c:?}").contains("49"));
        assert!(format!("{c:?}").contains("REDACTED"));
    }
}
