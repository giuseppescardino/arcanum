//! Offline half of the Have I Been Pwned "Pwned Passwords" check
//! (k-anonymity range API): only the first five hex digits of the
//! password's SHA-1 are sent, the server answers with every known hash
//! suffix in that range and the match is done here.
//! <https://haveibeenpwned.com/API/v3#SearchingPwnedPasswordsByRange>

use sha1::{Digest, Sha1};
use zeroize::Zeroizing;

/// Hex digits of the SHA-1 sent to the server.
pub const PREFIX_LEN: usize = 5;

/// The two halves of a password's upper-case hex SHA-1.
pub struct RangeQuery {
    /// Sent to the server.
    pub prefix: String,
    /// Kept on the device and matched against the response.
    pub suffix: Zeroizing<String>,
}

pub fn range_query(password: &str) -> RangeQuery {
    let digest = Zeroizing::new(Sha1::digest(password.as_bytes()));
    let hex = Zeroizing::new(data_encoding::HEXUPPER.encode(&digest));
    RangeQuery {
        prefix: hex[..PREFIX_LEN].to_owned(),
        suffix: Zeroizing::new(hex[PREFIX_LEN..].to_owned()),
    }
}

/// Times `suffix` appears in breaches according to a range response
/// (`SUFFIX:COUNT` lines). Padding lines (`Add-Padding`) have count 0, so
/// they never match; malformed lines are ignored.
pub fn count_in_range(body: &str, suffix: &str) -> u64 {
    body.lines()
        .filter_map(|line| line.trim().split_once(':'))
        .find(|(s, _)| s.eq_ignore_ascii_case(suffix))
        .and_then(|(_, count)| count.trim().parse().ok())
        .unwrap_or(0)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn splits_the_sha1() {
        // SHA-1("password") = 5BAA61E4C9B93F3F0682250B6CF8331B7EE68FD8
        let q = range_query("password");
        assert_eq!(q.prefix, "5BAA6");
        assert_eq!(q.suffix.as_str(), "1E4C9B93F3F0682250B6CF8331B7EE68FD8");
    }

    #[test]
    fn finds_the_count() {
        let body = "0018A45C4D1DEF81644B54AB7F969B88D65:1\r\n\
                    1e4c9b93f3f0682250b6cf8331b7ee68fd8:10434004\r\n\
                    00D4F6E8FA6EECAD2A3AA415EEC418D38EC:2\r\n";
        assert_eq!(
            count_in_range(body, "1E4C9B93F3F0682250B6CF8331B7EE68FD8"),
            10_434_004
        );
        assert_eq!(
            count_in_range(body, "FFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF"),
            0
        );
    }

    #[test]
    fn padding_and_garbage_count_as_absent() {
        let body = "1E4C9B93F3F0682250B6CF8331B7EE68FD8:0\r\nnot a line\r\n:\r\n";
        assert_eq!(
            count_in_range(body, "1E4C9B93F3F0682250B6CF8331B7EE68FD8"),
            0
        );
        assert_eq!(count_in_range("", "ABC"), 0);
    }
}
