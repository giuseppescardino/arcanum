use std::sync::Arc;

use arcanum_proto::opaque_ke::ServerSetup;
use arcanum_proto::OpaqueSuite;
use rand_core::{OsRng, RngCore};
use sqlx::PgPool;
use uuid::Uuid;

use crate::limiter::LoginLimiter;

#[derive(Clone)]
pub struct AppState {
    pub pool: PgPool,
    pub opaque: Arc<ServerSetup<OpaqueSuite>>,
    /// Keys the fake prelogin salts returned for unknown emails.
    pub prelogin_secret: Arc<[u8; 32]>,
    /// Sent with every pull. Deleting it from `server_config` (the restore
    /// procedure does) makes a new one on the next start, so clients notice
    /// the restore and resync.
    pub sync_epoch: Arc<str>,
    pub limiter: Arc<LoginLimiter>,
}

impl AppState {
    /// Loads the long-term server secrets, generating them on first start.
    /// They must survive restarts: losing the OPAQUE setup invalidates
    /// every registration.
    pub async fn load(pool: PgPool) -> Result<Self, sqlx::Error> {
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
