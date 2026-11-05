//! Registration, login and password change, all over OPAQUE.

use arcanum_crypto::account::EncryptedAccountKeys;
use arcanum_crypto::kdf::SALT_LEN;
use arcanum_crypto::KdfParams;
use arcanum_proto::limits::MAX_INVITE_CHARS;
use arcanum_proto::opaque_ke::{
    CredentialFinalization, CredentialRequest, Identifiers, RegistrationRequest,
    RegistrationUpload, ServerLogin, ServerLoginParameters, ServerRegistration,
};
use arcanum_proto::{
    LoginFinishRequest, LoginStartRequest, LoginStartResponse, OpaqueMessage, OpaqueSuite,
    PasswordFinishRequest, PreloginRequest, PreloginResponse, RegisterFinishRequest,
    RegisterStartRequest, SessionResponse, VaultRecord, OPAQUE_CONTEXT,
};
use axum::extract::State;
use axum::http::StatusCode;
use axum::Json;
use hmac::{Hmac, Mac};
use rand_core::OsRng;
use sha2::Sha256;
use sqlx::types::Json as DbJson;
use sqlx::PgPool;
use uuid::Uuid;

use crate::auth::{create_session, AuthSession};
use crate::client_ip::ClientIp;
use crate::config::Registration;
use crate::error::{ApiError, ApiResult};
use crate::{invites, now_ms, validate, AppState};

const PENDING_LOGIN_TTL_MS: i64 = 5 * 60 * 1000;
const MAX_WRAPPED_KEY_BYTES: usize = 1024;

fn bad_opaque<E>(_: E) -> ApiError {
    ApiError::bad_request("invalid OPAQUE message")
}

fn login_params() -> ServerLoginParameters<'static, 'static> {
    ServerLoginParameters {
        context: Some(OPAQUE_CONTEXT),
        identifiers: Identifiers::default(),
    }
}

pub async fn register_start(
    State(s): State<AppState>,
    Json(req): Json<RegisterStartRequest>,
) -> ApiResult<Json<OpaqueMessage>> {
    if s.config.registration == Registration::Closed {
        return Err(ApiError::registration_closed());
    }
    let login_id = validate::login_id(&req.login_id)?;
    let request =
        RegistrationRequest::<OpaqueSuite>::deserialize(&req.message).map_err(bad_opaque)?;
    let start = ServerRegistration::<OpaqueSuite>::start(&s.opaque, request, login_id.as_bytes())
        .map_err(bad_opaque)?;
    Ok(Json(OpaqueMessage {
        message: start.message.serialize().to_vec(),
    }))
}

pub async fn register_finish(
    State(s): State<AppState>,
    ClientIp(ip): ClientIp,
    Json(req): Json<RegisterFinishRequest>,
) -> ApiResult<Json<SessionResponse>> {
    let invite = match s.config.registration {
        Registration::Closed => return Err(ApiError::registration_closed()),
        Registration::Open => None,
        Registration::Invite => {
            let code = req.invite.as_deref().map(str::trim).unwrap_or_default();
            if code.is_empty() {
                tracing::info!(%ip, "registration refused: invite required");
                return Err(ApiError::invite_required());
            }
            if code.len() > MAX_INVITE_CHARS {
                return Err(ApiError::invalid_invite());
            }
            Some(code)
        }
    };
    let login_id = validate::login_id(&req.login_id)?;
    let account_id = validate::uuid(&req.account_id, "account id")?;
    let vault_id = validate::uuid(&req.vault.id, "vault id")?;
    validate::account_keys(&req.account_keys)?;
    if req.vault.wrapped_key.is_empty() || req.vault.wrapped_key.len() > MAX_WRAPPED_KEY_BYTES {
        return Err(ApiError::bad_request("invalid wrapped vault key"));
    }
    let upload =
        RegistrationUpload::<OpaqueSuite>::deserialize(&req.message).map_err(bad_opaque)?;
    let record = ServerRegistration::<OpaqueSuite>::finish(upload)
        .serialize()
        .to_vec();

    let mut tx = s.pool.begin().await?;
    let inserted = sqlx::query(
        "INSERT INTO accounts (id, login_id, opaque_record, account_keys, created_at)
         VALUES ($1, $2, $3, $4, $5) ON CONFLICT DO NOTHING",
    )
    .bind(account_id)
    .bind(&login_id)
    .bind(record)
    .bind(DbJson(&req.account_keys))
    .bind(now_ms())
    .execute(&mut *tx)
    .await?
    .rows_affected();
    if inserted == 0 {
        return Err(ApiError::account_exists());
    }
    if let Some(code) = invite {
        // Dropping `tx` on error rolls the account back and frees the code.
        let Some(label) = invites::consume(&mut tx, code, account_id).await? else {
            tracing::info!(%ip, "registration refused: invalid invite");
            return Err(ApiError::invalid_invite());
        };
        sqlx::query("UPDATE accounts SET label = $2 WHERE id = $1")
            .bind(account_id)
            .bind(label)
            .execute(&mut *tx)
            .await?;
    }
    let inserted = sqlx::query(
        "INSERT INTO vaults (id, account_id, wrapped_key) VALUES ($1, $2, $3) ON CONFLICT DO NOTHING",
    )
    .bind(vault_id)
    .bind(account_id)
    .bind(&req.vault.wrapped_key)
    .execute(&mut *tx)
    .await?
    .rows_affected();
    if inserted == 0 {
        return Err(ApiError::bad_request("vault id already in use"));
    }
    let token = create_session(&mut tx, account_id).await?;
    tx.commit().await?;

    tracing::info!(%account_id, %ip, policy = s.config.registration.as_str(), "account registered");
    Ok(Json(SessionResponse {
        token,
        account_id: account_id.to_string(),
        account_keys: req.account_keys,
        vaults: vec![req.vault],
    }))
}

pub async fn prelogin(
    State(s): State<AppState>,
    Json(req): Json<PreloginRequest>,
) -> ApiResult<Json<PreloginResponse>> {
    let login_id = validate::login_id(&req.login_id)?;
    let keys: Option<DbJson<EncryptedAccountKeys>> =
        sqlx::query_scalar("SELECT account_keys FROM accounts WHERE login_id = $1")
            .bind(&login_id)
            .fetch_optional(&s.pool)
            .await?;
    Ok(Json(match keys {
        Some(DbJson(k)) => PreloginResponse {
            kdf: k.kdf,
            salt: k.salt,
        },
        None => fake_prelogin(&s.prelogin_secret, &login_id)?,
    }))
}

/// Deterministic per login id, so repeated probes for a non-existent
/// account look exactly like a real one.
fn fake_prelogin(secret: &[u8; 32], login_id: &str) -> ApiResult<PreloginResponse> {
    let mut mac = <Hmac<Sha256> as Mac>::new_from_slice(secret).map_err(ApiError::internal)?;
    mac.update(login_id.as_bytes());
    let digest = mac.finalize().into_bytes();
    let mut salt = [0u8; SALT_LEN];
    salt.copy_from_slice(&digest[..SALT_LEN]);
    Ok(PreloginResponse {
        kdf: KdfParams::DEFAULT,
        salt,
    })
}

pub async fn login_start(
    State(s): State<AppState>,
    ClientIp(ip): ClientIp,
    Json(req): Json<LoginStartRequest>,
) -> ApiResult<Json<LoginStartResponse>> {
    let login_id = validate::login_id(&req.login_id)?;
    if s.limiter.is_blocked(&login_id) {
        tracing::info!(%ip, "login refused: too many attempts for this account");
        return Err(ApiError::too_many_requests());
    }
    let request =
        CredentialRequest::<OpaqueSuite>::deserialize(&req.message).map_err(bad_opaque)?;
    // With OPAQUE a wrong password is detected by the *client*, which then
    // never calls finish; so every well-formed start counts as an attempt
    // until a successful finish resets the counter.
    s.limiter.record_failure(&login_id);
    let record: Option<Vec<u8>> =
        sqlx::query_scalar("SELECT opaque_record FROM accounts WHERE login_id = $1")
            .bind(&login_id)
            .fetch_optional(&s.pool)
            .await?;
    // Unknown login ids still get a well-formed (fake) response.
    let password_file = record
        .map(|r| ServerRegistration::<OpaqueSuite>::deserialize(&r))
        .transpose()
        .map_err(|_| ApiError::internal("corrupt OPAQUE record"))?;
    let start = ServerLogin::start(
        &mut OsRng,
        &s.opaque,
        password_file,
        request,
        login_id.as_bytes(),
        login_params(),
    )
    .map_err(bad_opaque)?;

    let now = now_ms();
    sqlx::query("DELETE FROM pending_logins WHERE expires_at < $1")
        .bind(now)
        .execute(&s.pool)
        .await?;
    let attempt_id = Uuid::new_v4();
    sqlx::query(
        "INSERT INTO pending_logins (id, login_id, state, expires_at) VALUES ($1, $2, $3, $4)",
    )
    .bind(attempt_id)
    .bind(&login_id)
    .bind(start.state.serialize().to_vec())
    .bind(now + PENDING_LOGIN_TTL_MS)
    .execute(&s.pool)
    .await?;

    Ok(Json(LoginStartResponse {
        attempt_id: attempt_id.to_string(),
        message: start.message.serialize().to_vec(),
    }))
}

pub async fn login_finish(
    State(s): State<AppState>,
    ClientIp(ip): ClientIp,
    Json(req): Json<LoginFinishRequest>,
) -> ApiResult<Json<SessionResponse>> {
    let attempt_id = validate::uuid(&req.attempt_id, "attempt id")?;

    // Single use: the pending state is consumed whatever the outcome.
    let pending: Option<(String, Vec<u8>)> = sqlx::query_as(
        "DELETE FROM pending_logins WHERE id = $1 AND expires_at > $2 RETURNING login_id, state",
    )
    .bind(attempt_id)
    .bind(now_ms())
    .fetch_optional(&s.pool)
    .await?;
    let (login_id, state) = pending.ok_or_else(ApiError::invalid_login)?;

    let finalization =
        CredentialFinalization::<OpaqueSuite>::deserialize(&req.message).map_err(bad_opaque)?;
    let server_login = ServerLogin::<OpaqueSuite>::deserialize(&state)
        .map_err(|_| ApiError::internal("corrupt pending login"))?;
    if server_login.finish(finalization, login_params()).is_err() {
        tracing::info!(%ip, "login failed");
        return Err(ApiError::invalid_login());
    }
    s.limiter.reset(&login_id);

    let account: Option<(Uuid, DbJson<EncryptedAccountKeys>)> =
        sqlx::query_as("SELECT id, account_keys FROM accounts WHERE login_id = $1")
            .bind(&login_id)
            .fetch_optional(&s.pool)
            .await?;
    let (account_id, DbJson(account_keys)) = account.ok_or_else(ApiError::invalid_login)?;

    let mut conn = s.pool.acquire().await?;
    let token = create_session(&mut conn, account_id).await?;
    let vaults = load_vaults(&s.pool, account_id).await?;
    tracing::info!(%account_id, %ip, "signed in");
    Ok(Json(SessionResponse {
        token,
        account_id: account_id.to_string(),
        account_keys,
        vaults,
    }))
}

pub async fn logout(auth: AuthSession, State(s): State<AppState>) -> ApiResult<StatusCode> {
    sqlx::query("DELETE FROM sessions WHERE id = $1")
        .bind(auth.session_id)
        .execute(&s.pool)
        .await?;
    Ok(StatusCode::NO_CONTENT)
}

/// First half of a password change: a fresh OPAQUE registration for the
/// new auth key.
pub async fn password_start(
    auth: AuthSession,
    State(s): State<AppState>,
    Json(req): Json<OpaqueMessage>,
) -> ApiResult<Json<OpaqueMessage>> {
    let login_id: String = sqlx::query_scalar("SELECT login_id FROM accounts WHERE id = $1")
        .bind(auth.account_id)
        .fetch_one(&s.pool)
        .await?;
    let request =
        RegistrationRequest::<OpaqueSuite>::deserialize(&req.message).map_err(bad_opaque)?;
    let start = ServerRegistration::<OpaqueSuite>::start(&s.opaque, request, login_id.as_bytes())
        .map_err(bad_opaque)?;
    Ok(Json(OpaqueMessage {
        message: start.message.serialize().to_vec(),
    }))
}

/// Stores the new OPAQUE record and re-wrapped Account Key atomically and
/// signs out every other device. Requires a fresh OPAQUE proof of the
/// current password, so a stolen session token can't lock the owner out.
pub async fn password_finish(
    auth: AuthSession,
    State(s): State<AppState>,
    Json(req): Json<PasswordFinishRequest>,
) -> ApiResult<StatusCode> {
    validate::account_keys(&req.account_keys)?;
    let attempt_id = validate::uuid(&req.attempt_id, "attempt id")?;
    let upload =
        RegistrationUpload::<OpaqueSuite>::deserialize(&req.message).map_err(bad_opaque)?;
    let finalization = CredentialFinalization::<OpaqueSuite>::deserialize(&req.login_message)
        .map_err(bad_opaque)?;

    let login_id: String = sqlx::query_scalar("SELECT login_id FROM accounts WHERE id = $1")
        .bind(auth.account_id)
        .fetch_one(&s.pool)
        .await?;
    // The pending login must belong to this account; consumed either way.
    let state: Option<Vec<u8>> = sqlx::query_scalar(
        "DELETE FROM pending_logins WHERE id = $1 AND login_id = $2 AND expires_at > $3
         RETURNING state",
    )
    .bind(attempt_id)
    .bind(&login_id)
    .bind(now_ms())
    .fetch_optional(&s.pool)
    .await?;
    let state = state.ok_or_else(ApiError::invalid_login)?;
    let server_login = ServerLogin::<OpaqueSuite>::deserialize(&state)
        .map_err(|_| ApiError::internal("corrupt pending login"))?;
    if server_login.finish(finalization, login_params()).is_err() {
        tracing::info!(account_id = %auth.account_id, "password change refused: wrong current password");
        return Err(ApiError::invalid_login());
    }
    s.limiter.reset(&login_id);

    let record = ServerRegistration::<OpaqueSuite>::finish(upload)
        .serialize()
        .to_vec();

    let mut tx = s.pool.begin().await?;
    sqlx::query("UPDATE accounts SET opaque_record = $2, account_keys = $3 WHERE id = $1")
        .bind(auth.account_id)
        .bind(record)
        .bind(DbJson(&req.account_keys))
        .execute(&mut *tx)
        .await?;
    sqlx::query("DELETE FROM sessions WHERE account_id = $1 AND id <> $2")
        .bind(auth.account_id)
        .bind(auth.session_id)
        .execute(&mut *tx)
        .await?;
    tx.commit().await?;
    tracing::info!(account_id = %auth.account_id, "password changed, other devices signed out");
    Ok(StatusCode::NO_CONTENT)
}

async fn load_vaults(pool: &PgPool, account_id: Uuid) -> ApiResult<Vec<VaultRecord>> {
    let rows: Vec<(Uuid, Vec<u8>)> =
        sqlx::query_as("SELECT id, wrapped_key FROM vaults WHERE account_id = $1")
            .bind(account_id)
            .fetch_all(pool)
            .await?;
    Ok(rows
        .into_iter()
        .map(|(id, wrapped_key)| VaultRecord {
            id: id.to_string(),
            wrapped_key,
        })
        .collect())
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn fake_prelogin_is_deterministic_per_email() {
        let secret = [7u8; 32];
        let a = fake_prelogin(&secret, "id-a").unwrap();
        assert_eq!(a, fake_prelogin(&secret, "id-a").unwrap());
        assert_ne!(a.salt, fake_prelogin(&secret, "id-x").unwrap().salt);
        assert_ne!(a.salt, fake_prelogin(&[8u8; 32], "id-a").unwrap().salt);
        assert_eq!(a.kdf, KdfParams::DEFAULT);
    }
}
