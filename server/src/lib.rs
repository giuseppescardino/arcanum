//! Zero-knowledge sync server.
//!
//! Stores only what clients encrypt: OPAQUE registration records, wrapped
//! keys and item ciphertexts. It can't decrypt anything and never sees the
//! master password, the Secret Key or a password-derived hash.

pub mod admin;
mod auth;
mod client_ip;
pub mod config;
mod error;
pub mod invites;
mod limiter;
mod routes;
mod state;
mod validate;

use std::time::{Duration, SystemTime, UNIX_EPOCH};

use axum::extract::{DefaultBodyLimit, Request, State};
use axum::http::StatusCode;
use axum::middleware::{self, Next};
use axum::response::{IntoResponse, Response};
use axum::routing::{delete, get, post, put};
use axum::Router;
use sqlx::PgPool;
use tower::limit::ConcurrencyLimitLayer;
use tower_http::timeout::TimeoutLayer;
use tower_http::trace::TraceLayer;

use client_ip::ClientIp;
use error::ApiError;

pub use config::{Config, Registration};
pub use state::AppState;

/// Request bodies: small everywhere, except item uploads.
const MAX_BODY_BYTES: usize = 64 * 1024;
const MAX_SYNC_BODY_BYTES: usize = 32 * 1024 * 1024;
const REQUEST_TIMEOUT: Duration = Duration::from_secs(30);
const MAX_CONCURRENT_REQUESTS: usize = 256;

pub async fn migrate(pool: &PgPool) -> Result<(), sqlx::migrate::MigrateError> {
    sqlx::migrate!("./migrations").run(pool).await
}

pub async fn app(pool: PgPool, config: Config) -> Result<Router, sqlx::Error> {
    let state = AppState::load(pool, config).await?;
    Ok(router(state))
}

fn router(state: AppState) -> Router {
    use routes::{account, devices, sync};
    let api = Router::new()
        .route("/v1/register/start", post(account::register_start))
        .route("/v1/register/finish", post(account::register_finish))
        .route("/v1/prelogin", post(account::prelogin))
        .route("/v1/login/start", post(account::login_start))
        .route("/v1/login/finish", post(account::login_finish))
        .route("/v1/logout", post(account::logout))
        .route("/v1/password/start", post(account::password_start))
        .route("/v1/password/finish", post(account::password_finish))
        .route(
            "/v1/sync",
            get(sync::pull)
                .post(sync::push)
                .layer(DefaultBodyLimit::max(MAX_SYNC_BODY_BYTES)),
        )
        .route("/v1/devices", get(devices::list))
        .route("/v1/devices/current", put(devices::set_current_name))
        .route("/v1/devices/{id}", delete(devices::revoke))
        .layer(middleware::from_fn_with_state(state.clone(), rate_limit));
    Router::new()
        .route("/health", get(|| async { "ok" }))
        .merge(api)
        .layer(DefaultBodyLimit::max(MAX_BODY_BYTES))
        .layer(TimeoutLayer::with_status_code(
            StatusCode::REQUEST_TIMEOUT,
            REQUEST_TIMEOUT,
        ))
        .layer(ConcurrencyLimitLayer::new(MAX_CONCURRENT_REQUESTS))
        .layer(TraceLayer::new_for_http())
        .with_state(state)
}

/// Per-IP limits: a general one on the whole API and stricter ones on the
/// unauthenticated account endpoints.
async fn rate_limit(
    State(s): State<AppState>,
    ClientIp(ip): ClientIp,
    request: Request,
    next: Next,
) -> Response {
    let path = request.uri().path();
    let specific = if path.starts_with("/v1/register/") {
        Some(&s.limits.register)
    } else if path == "/v1/prelogin" || path.starts_with("/v1/login/") {
        Some(&s.limits.auth)
    } else {
        None
    };
    let allowed = s.limits.api.allow(ip) && specific.map_or(true, |l| l.allow(ip));
    if !allowed {
        tracing::info!(%ip, path, "rate limited");
        return ApiError::too_many_requests().into_response();
    }
    next.run(request).await
}

pub(crate) fn now_ms() -> i64 {
    SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .map(|d| i64::try_from(d.as_millis()).unwrap_or(i64::MAX))
        .unwrap_or(0)
}
