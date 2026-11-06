use std::sync::Arc;

use arcanum_proto::opaque_ke::ServerSetup;
use arcanum_proto::OpaqueSuite;
use rand_core::{OsRng, RngCore};
use sqlx::PgPool;
use uuid::Uuid;

use crate::config::Config;
use crate::limiter::{IpLimiter, LoginLimiter};

/// Per-IP limits (requests per window).
const AUTH_PER_MINUTE: u32 = 60;
const REGISTER_PER_HOUR: u32 = 20;
const API_PER_MINUTE: u32 = 600;

#[derive(Clone)]
pub struct AppState {
    pub pool: PgPool,
    pub opaque: Arc<ServerSetup<OpaqueSuite>>,
    /// Keys the fake prelogin salts returned for unknown login ids.
    pub prelogin_secret: Arc<[u8; 32]>,
    /// Sent with every pull. Deleting it from `server_config` (the restore
    /// procedure does) makes a new one on the next start, so clients notice
    /// the restore and resync.
    pub sync_epoch: Arc<str>,
    pub limiter: Arc<LoginLimiter>,
    pub limits: Arc<IpLimits>,
    pub config: Arc<Config>,
}

pub struct IpLimits {
    /// `/v1/prelogin` and `/v1/login/*`.
    pub auth: IpLimiter,
    /// `/v1/register/*`: bounds account creation on open servers.
    pub register: IpLimiter,
    /// Every `/v1` request.
    pub api: IpLimiter,
}

impl Default for IpLimits {
    fn default() -> Self {
        Self {
            auth: IpLimiter::new(AUTH_PER_MINUTE, 60 * 1000),
            register: IpLimiter::new(REGISTER_PER_HOUR, 60 * 60 * 1000),
            api: IpLimiter::new(API_PER_MINUTE, 60 * 1000),
        }
    }
}

impl AppState {
    /// Loads the long-term server secrets, generating them on first start.
    /// They must survive restarts: losing the OPAQUE setup invalidates
    /// every registration.
    pub async fn load(pool: PgPool, config: Config) -> Result<Self, sqlx::Error> {
        let setup_bytes = get_or_init(&pool, "opaque_server_setup", || {
            ServerSetup::<OpaqueSuite>::new(&mut OsRng)
                .serialize()
                .to_vec()
        })
        .await?;
        let opaque = ServerSetup::<OpaqueSuite>::deserialize(&setup_bytes)
            .map_err(|e| sqlx::Error::Protocol(format!("corrupt OPAQUE setup: {e:?}")))?;

        let secret_bytes = get_or_init(&pool, "prelogin_secret", || {
            let mut s = vec![0u8; 32];
            OsRng.fill_bytes(&mut s);
            s
        })
        .await?;
        let prelogin_secret: [u8; 32] = secret_bytes
            .try_into()
            .map_err(|_| sqlx::Error::Protocol("corrupt prelogin secret".into()))?;

        let epoch_bytes = get_or_init(&pool, "sync_epoch", || {
            let mut e = vec![0u8; 16];
            OsRng.fill_bytes(&mut e);
            e
        })
        .await?;
        let sync_epoch = Uuid::from_slice(&epoch_bytes)
            .map_err(|_| sqlx::Error::Protocol("corrupt sync epoch".into()))?
            .simple()
            .to_string();

        Ok(Self {
            pool,
            sync_epoch: sync_epoch.into(),
            opaque: Arc::new(opaque),
            prelogin_secret: Arc::new(prelogin_secret),
            limiter: Arc::new(LoginLimiter::default()),
            limits: Arc::new(IpLimits::default()),
            config: Arc::new(config),
        })
    }
}

async fn get_or_init(
    pool: &PgPool,
    key: &str,
    init: impl FnOnce() -> Vec<u8>,
) -> Result<Vec<u8>, sqlx::Error> {
    // Concurrent first starts race safely: only one insert wins.
    sqlx::query(
        "INSERT INTO server_config (key, value) VALUES ($1, $2) ON CONFLICT (key) DO NOTHING",
    )
    .bind(key)
    .bind(init())
    .execute(pool)
    .await?;
    sqlx::query_scalar("SELECT value FROM server_config WHERE key = $1")
        .bind(key)
        .fetch_one(pool)
        .await
}
