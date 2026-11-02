//! Zero-knowledge sync server.
//!
//! Stores only what clients encrypt: OPAQUE registration records, wrapped
//! keys and item ciphertexts. It can't decrypt anything and never sees the
//! master password, the Secret Key or a password-derived hash.

mod auth;
mod error;
mod limiter;
mod routes;
mod state;
mod validate;

use std::time::{SystemTime, UNIX_EPOCH};

use axum::extract::DefaultBodyLimit;
use axum::routing::{delete, get, post};
use axum::Router;
use sqlx::PgPool;
use tower_http::trace::TraceLayer;

pub use state::AppState;

const MAX_BODY_BYTES: usize = 32 * 1024 * 1024;

pub async fn migrate(pool: &PgPool) -> Result<(), sqlx::migrate::MigrateError> {
    sqlx::migrate!("./migrations").run(pool).await
}

pub async fn app(pool: PgPool) -> Result<Router, sqlx::Error> {
    let state = AppState::load(pool).await?;
    Ok(router(state))
}

fn router(state: AppState) -> Router {
    use routes::{account, devices, sync};
    Router::new()
        .route("/health", get(|| async { "ok" }))
        .route("/v1/register/start", post(account::register_start))
        .route("/v1/register/finish", post(account::register_finish))
        .route("/v1/prelogin", post(account::prelogin))
        .route("/v1/login/start", post(account::login_start))
        .route("/v1/login/finish", post(account::login_finish))
        .route("/v1/logout", post(account::logout))
        .route("/v1/password/start", post(account::password_start))
        .route("/v1/password/finish", post(account::password_finish))
        .route("/v1/sync", get(sync::pull).post(sync::push))
        .route("/v1/devices", get(devices::list))
        .route("/v1/devices/{id}", delete(devices::revoke))
        .layer(DefaultBodyLimit::max(MAX_BODY_BYTES))
        .layer(TraceLayer::new_for_http())
        .with_state(state)
}

pub(crate) fn now_ms() -> i64 {
    SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .map(|d| i64::try_from(d.as_millis()).unwrap_or(i64::MAX))
        .unwrap_or(0)
}
