//! Single-use registration codes. Shown once to the operator, stored only
//! as SHA-256 hashes (like session tokens).

use data_encoding::BASE32_NOPAD;
use rand_core::{OsRng, RngCore};
use sha2::{Digest, Sha256};
use sqlx::{PgConnection, PgPool};
use uuid::Uuid;

use crate::now_ms;

const PREFIX: &str = "INV";
const GROUPS: [usize; 5] = [6, 5, 5, 5, 5];

/// A new random code, printed as `INV-XXXXXX-XXXXX-XXXXX-XXXXX-XXXXX`.
pub fn generate_code() -> String {
    let mut raw = [0u8; 16];
    OsRng.fill_bytes(&mut raw);
    let encoded = BASE32_NOPAD.encode(&raw);
    let mut out = String::from(PREFIX);
    let mut start = 0;
    for len in GROUPS {
        out.push('-');
        out.push_str(&encoded[start..start + len]);
        start += len;
    }
    out
}

/// Hash of the normalized code: case, dashes, spaces and the look-alikes
/// `0/O`, `1/I`, `8/B` don't matter, so codes can be typed from paper.
pub fn hash_code(code: &str) -> Vec<u8> {
    let normalized: String = code
        .chars()
        .filter(|c| !c.is_whitespace() && *c != '-')
        .map(|c| match c.to_ascii_uppercase() {
            '0' => 'O',
            '1' => 'I',
            '8' => 'B',
            other => other,
        })
        .collect();
    let body = normalized.strip_prefix(PREFIX).unwrap_or(&normalized);
    Sha256::digest(body.as_bytes()).to_vec()
}

/// Creates an invite valid for `days` days and returns `(id, code)`.
pub async fn create(
    pool: &PgPool,
    label: Option<&str>,
    days: i64,
) -> Result<(Uuid, String), sqlx::Error> {
    let code = generate_code();
    let id = Uuid::new_v4();
    let now = now_ms();
    sqlx::query(
        "INSERT INTO invites (id, code_hash, label, created_at, expires_at) VALUES ($1, $2, $3, $4, $5)",
    )
    .bind(id)
    .bind(hash_code(&code))
    .bind(label)
    .bind(now)
    .bind(now + days.saturating_mul(24 * 60 * 60 * 1000))
    .execute(pool)
    .await?;
    Ok((id, code))
}

/// Marks the invite as used by `account_id` (single use, not expired) and
/// returns its label; `None` if the code is not usable. Runs inside the
/// registration transaction, so a failed registration frees the code again.
pub async fn consume(
    conn: &mut PgConnection,
    code: &str,
    account_id: Uuid,
) -> Result<Option<Option<String>>, sqlx::Error> {
    let now = now_ms();
    sqlx::query_scalar(
        "UPDATE invites SET used_by = $2, used_at = $3
         WHERE code_hash = $1 AND used_at IS NULL AND expires_at > $3
         RETURNING label",
    )
    .bind(hash_code(code))
    .bind(account_id)
    .bind(now)
    .fetch_optional(conn)
    .await
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn codes_are_unique_and_formatted() {
        let a = generate_code();
        assert_eq!(a.len(), 3 + 5 + 26);
        assert!(a.starts_with("INV-"));
        assert_ne!(a, generate_code());
    }

    #[test]
    fn hashing_is_lenient() {
        let code = generate_code();
        let typed = code.to_lowercase().replace('-', " ");
        assert_eq!(hash_code(&code), hash_code(&typed));
        assert_eq!(hash_code(&code), hash_code(code.trim_start_matches("INV-")));
        assert_ne!(hash_code(&code), hash_code(&generate_code()));
    }
}
