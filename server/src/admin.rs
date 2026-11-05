//! Operator commands, run inside the server container:
//!
//! ```text
//! arcanum-server invite create [--label TEXT] [--days N]
//! arcanum-server invite list
//! arcanum-server invite revoke <id>
//! arcanum-server account list
//! arcanum-server account delete <id>
//! ```
//!
//! They talk to the database directly and print plain text.

use std::fmt::Write as _;

use sqlx::PgPool;
use uuid::Uuid;

use crate::{invites, now_ms};

const DEFAULT_INVITE_DAYS: i64 = 7;

#[derive(sqlx::FromRow)]
struct InviteRow {
    id: Uuid,
    label: Option<String>,
    created_at: i64,
    expires_at: i64,
    used_by: Option<Uuid>,
    used_at: Option<i64>,
}

#[derive(sqlx::FromRow)]
struct AccountRow {
    id: Uuid,
    label: Option<String>,
    created_at: i64,
    last_used: Option<i64>,
    devices: i64,
    items: i64,
}

pub const USAGE: &str = "usage:
  arcanum-server                          run the server
  arcanum-server invite create [--label TEXT] [--days N]
  arcanum-server invite list
  arcanum-server invite revoke <id>
  arcanum-server account list
  arcanum-server account delete <id>";

/// True if `args` (without the program name) is an admin command.
pub fn is_admin_command(args: &[String]) -> bool {
    matches!(args.first().map(String::as_str), Some("invite" | "account"))
}

/// Runs an admin command and returns what to print.
pub async fn run(pool: &PgPool, args: &[String]) -> Result<String, String> {
    let words: Vec<&str> = args.iter().map(String::as_str).collect();
    match words.as_slice() {
        ["invite", "create", rest @ ..] => invite_create(pool, rest).await,
        ["invite", "list"] => invite_list(pool).await,
        ["invite", "revoke", id] => invite_revoke(pool, id).await,
        ["account", "list"] => account_list(pool).await,
        ["account", "delete", id] => account_delete(pool, id).await,
        _ => Err(USAGE.into()),
    }
}

fn db(e: sqlx::Error) -> String {
    format!("database error: {e}")
}

fn parse_id(raw: &str) -> Result<Uuid, String> {
    Uuid::parse_str(raw).map_err(|_| format!("not a valid id: {raw}"))
}

async fn invite_create(pool: &PgPool, opts: &[&str]) -> Result<String, String> {
    let mut label = None;
    let mut days = DEFAULT_INVITE_DAYS;
    let mut it = opts.iter();
    while let Some(opt) = it.next() {
        match *opt {
            "--label" => {
                let v = it.next().ok_or("--label needs a value")?.trim();
                if v.is_empty() || v.chars().count() > 200 {
                    return Err("--label must be 1-200 characters".into());
                }
                label = Some(v.to_owned());
            }
            "--days" => {
                days = it
                    .next()
                    .and_then(|v| v.parse().ok())
                    .filter(|d| (1..=365).contains(d))
                    .ok_or("--days must be between 1 and 365")?;
            }
            other => return Err(format!("unknown option {other}\n{USAGE}")),
        }
    }
    let (id, code) = invites::create(pool, label.as_deref(), days)
        .await
        .map_err(db)?;
    Ok(format!(
        "invite {id} (valid {days} days{})\n\n  {code}\n\nThe code is shown only now. Enter it in the app when creating the account.",
        label.map(|l| format!(", label {l:?}")).unwrap_or_default()
    ))
}

async fn invite_list(pool: &PgPool) -> Result<String, String> {
    let rows: Vec<InviteRow> = sqlx::query_as(
        "SELECT id, label, created_at, expires_at, used_by, used_at FROM invites ORDER BY created_at DESC",
    )
    .fetch_all(pool)
    .await
    .map_err(db)?;
    if rows.is_empty() {
        return Ok("no invites".into());
    }
    let now = now_ms();
    let mut out = String::new();
    for row in rows {
        let state = match (row.used_at, row.used_by) {
            (Some(at), Some(acc)) => format!("used {} by account {acc}", date(at)),
            (Some(at), None) => format!("used {} (account deleted)", date(at)),
            _ if row.expires_at <= now => "expired".to_owned(),
            _ => format!("open until {}", date(row.expires_at)),
        };
        let _ = writeln!(
            out,
            "{}  created {}  {:<30}  {state}",
            row.id,
            date(row.created_at),
            row.label.unwrap_or_else(|| "-".into())
        );
    }
    Ok(out)
}

async fn invite_revoke(pool: &PgPool, raw: &str) -> Result<String, String> {
    let id = parse_id(raw)?;
    let n = sqlx::query("DELETE FROM invites WHERE id = $1 AND used_at IS NULL")
        .bind(id)
        .execute(pool)
        .await
        .map_err(db)?
        .rows_affected();
    if n == 0 {
        return Err(format!("no unused invite with id {id}"));
    }
    Ok(format!("invite {id} revoked"))
}

async fn account_list(pool: &PgPool) -> Result<String, String> {
    let rows: Vec<AccountRow> = sqlx::query_as(
        "SELECT a.id, a.label, a.created_at,
                (SELECT max(last_used_at) FROM sessions s WHERE s.account_id = a.id) AS last_used,
                (SELECT count(*) FROM sessions s WHERE s.account_id = a.id) AS devices,
                (SELECT count(*) FROM items i JOIN vaults v ON v.id = i.vault_id
                 WHERE v.account_id = a.id AND NOT i.deleted) AS items
         FROM accounts a ORDER BY a.created_at",
    )
    .fetch_all(pool)
    .await
    .map_err(db)?;
    if rows.is_empty() {
        return Ok("no accounts".into());
    }
    let mut out = String::new();
    for row in rows {
        let _ = writeln!(
            out,
            "{}  {:<30}  created {}  last used {}  {} devices  {} items",
            row.id,
            row.label.unwrap_or_else(|| "-".into()),
            date(row.created_at),
            row.last_used.map_or_else(|| "never".into(), date),
            row.devices,
            row.items,
        );
    }
    Ok(out)
}

async fn account_delete(pool: &PgPool, raw: &str) -> Result<String, String> {
    let id = parse_id(raw)?;
    // Vaults, items and sessions go with it (ON DELETE CASCADE).
    let n = sqlx::query("DELETE FROM accounts WHERE id = $1")
        .bind(id)
        .execute(pool)
        .await
        .map_err(db)?
        .rows_affected();
    if n == 0 {
        return Err(format!("no account with id {id}"));
    }
    tracing::info!(account_id = %id, "account deleted by the operator");
    Ok(format!(
        "account {id} deleted with all its data and sessions; its devices keep their local copy"
    ))
}

/// UTC date from Unix ms, `YYYY-MM-DD` (no date crate needed).
fn date(ms: i64) -> String {
    let days = ms.div_euclid(86_400_000);
    // Civil-from-days (Howard Hinnant's algorithm).
    let z = days + 719_468;
    let era = z.div_euclid(146_097);
    let doe = z - era * 146_097;
    let yoe = (doe - doe / 1460 + doe / 36_524 - doe / 146_096) / 365;
    let doy = doe - (365 * yoe + yoe / 4 - yoe / 100);
    let mp = (5 * doy + 2) / 153;
    let d = doy - (153 * mp + 2) / 5 + 1;
    let m = if mp < 10 { mp + 3 } else { mp - 9 };
    let y = yoe + era * 400 + i64::from(m <= 2);
    format!("{y:04}-{m:02}-{d:02}")
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn dates() {
        assert_eq!(date(0), "1970-01-01");
        assert_eq!(date(1_709_164_800_000), "2024-02-29");
        assert_eq!(date(1_793_750_400_000), "2026-11-04");
    }

    #[test]
    fn admin_commands_are_recognized() {
        let a = |v: &[&str]| v.iter().map(|s| s.to_string()).collect::<Vec<_>>();
        assert!(is_admin_command(&a(&["invite", "list"])));
        assert!(is_admin_command(&a(&["account", "list"])));
        assert!(!is_admin_command(&a(&[])));
        assert!(!is_admin_command(&a(&["serve"])));
    }
}
