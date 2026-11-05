//! Opaque bearer tokens: 32 random bytes, stored only as SHA-256 hashes,
//! so a database leak doesn't leak usable sessions. Sliding 90-day expiry.

use axum::extract::FromRequestParts;
use axum::http::header::AUTHORIZATION;
use axum::http::request::Parts;
use base64::engine::general_purpose::URL_SAFE_NO_PAD;
use base64::Engine;
use rand_core::{OsRng, RngCore};
use sha2::{Digest, Sha256};
use sqlx::PgConnection;
use uuid::Uuid;

use crate::error::{ApiError, ApiResult};
use crate::{now_ms, AppState};

const SESSION_TTL_MS: i64 = 90 * 24 * 60 * 60 * 1000;

pub struct AuthSession {
    pub session_id: Uuid,
    pub account_id: Uuid,
}

impl FromRequestParts<AppState> for AuthSession {
    type Rejection = ApiError;

    async fn from_request_parts(parts: &mut Parts, state: &AppState) -> ApiResult<Self> {
        let token = parts
            .headers
            .get(AUTHORIZATION)
            .and_then(|v| v.to_str().ok())
            .and_then(|v| v.strip_prefix("Bearer "))
            .ok_or_else(ApiError::unauthorized)?;
        let now = now_ms();
        let row: Option<(Uuid, Uuid)> = sqlx::query_as(
            "UPDATE sessions SET last_used_at = $2, expires_at = $3
             WHERE token_hash = $1 AND expires_at > $2
             RETURNING id, account_id",
        )
        .bind(hash_token(token))
        .bind(now)
        .bind(now + SESSION_TTL_MS)
        .fetch_optional(&state.pool)
        .await?;
        let (session_id, account_id) = row.ok_or_else(ApiError::unauthorized)?;
        Ok(Self {
            session_id,
            account_id,
        })
    }
}

/// Creates a session and returns the bearer token (shown only once).
/// The device sets its (encrypted) name afterwards.
pub async fn create_session(conn: &mut PgConnection, account_id: Uuid) -> ApiResult<String> {
    let mut raw = [0u8; 32];
    OsRng.fill_bytes(&mut raw);
    let token = URL_SAFE_NO_PAD.encode(raw);
    let now = now_ms();
    sqlx::query(
        "INSERT INTO sessions (id, token_hash, account_id, created_at, last_used_at, expires_at)
         VALUES ($1, $2, $3, $4, $4, $5)",
    )
    .bind(Uuid::new_v4())
    .bind(hash_token(&token))
    .bind(account_id)
    .bind(now)
    .bind(now + SESSION_TTL_MS)
    .execute(conn)
    .await?;
    Ok(token)
}

fn hash_token(token: &str) -> Vec<u8> {
    Sha256::digest(token.as_bytes()).to_vec()
}
