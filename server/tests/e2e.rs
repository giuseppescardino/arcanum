//! End-to-end: real server + PostgreSQL + the HTTP sync client.
//!
//! Needs a database: `TEST_DATABASE_URL` (default
//! `postgres://postgres@localhost:5433/arcanum_test`). Each test starts its own
//! server on a random port and uses unique emails, so tests can share it.

#![allow(clippy::unwrap_used, clippy::expect_used)]

use std::env;

use arcanum_sync::SyncError;
use arcanum_vault::{ItemData, KdfParams, SecretKey, Vault, VaultError};
use sqlx::postgres::PgPoolOptions;
use sqlx::PgPool;
use tokio::net::TcpListener;
use uuid::Uuid;

const PW: &[u8] = b"correct horse battery staple";

async fn pool() -> PgPool {
    let url = env::var("TEST_DATABASE_URL")
        .unwrap_or_else(|_| "postgres://postgres@localhost:5433/arcanum_test".into());
    let pool = PgPoolOptions::new()
        .max_connections(4)
        .connect(&url)
        .await
        .expect("test database not reachable (set TEST_DATABASE_URL)");
    arcanum_server::migrate(&pool).await.expect("migrations");
    pool
}

/// Returns the base URL of a fresh server instance.
async fn start_server(pool: PgPool) -> String {
    let app = arcanum_server::app(pool).await.expect("app");
    let listener = TcpListener::bind("127.0.0.1:0").await.expect("bind");
    let port = listener.local_addr().expect("addr").port();
    tokio::spawn(async move {
        axum::serve(listener, app).await.expect("serve");
    });
    format!("http://127.0.0.1:{port}")
}

fn email() -> String {
    format!("{}@test.local", Uuid::new_v4())
}

fn login(title: &str, password: &str) -> ItemData {
    let mut d = ItemData::default();
    d.title = title.into();
    d.username = "alice".into();
    d.password = password.into();
    d
}

/// Device A: new local vault with one item, registered on the server.
fn registered_device(url: &str, email: &str) -> (Vault, SecretKey) {
    let mut a = Vault::open_in_memory().unwrap();
    let sk = a.create(PW, KdfParams::DEFAULT).unwrap();
    a.add_item(&login("GitHub", "gh-secret-1")).unwrap();
    let r = arcanum_sync::register(&mut a, url, email, PW, &sk, "Laptop").unwrap();
    assert_eq!(r.pushed, 1);
    (a, sk)
}

fn blocking<T: Send + 'static>(
    f: impl FnOnce() -> T + Send + 'static,
) -> tokio::task::JoinHandle<T> {
    tokio::task::spawn_blocking(f)
}

#[tokio::test(flavor = "multi_thread")]
async fn register_sign_in_and_sync_both_ways() {
    let url = start_server(pool().await).await;
    blocking(move || {
        let email = email();
        let (mut a, sk) = registered_device(&url, &email);

        let mut b = Vault::open_in_memory().unwrap();
        let r = arcanum_sync::sign_in(&mut b, &url, &email, PW, &sk, "Phone").unwrap();
        assert_eq!(r.pulled, 1);
        assert!(b.is_unlocked());
        let item = b.items().unwrap().pop().unwrap();
        assert_eq!(item.data.password, "gh-secret-1");

        b.update_item(&item.id, &login("GitHub", "gh-secret-2"))
            .unwrap();
        b.add_item(&login("Bank", "bank-pw")).unwrap();
        assert_eq!(arcanum_sync::sync_now(&mut b).unwrap().pushed, 2);

        assert_eq!(arcanum_sync::sync_now(&mut a).unwrap().pulled, 2);
        assert_eq!(a.item(&item.id).unwrap().data.password, "gh-secret-2");
        assert_eq!(a.items().unwrap().len(), 2);

        // Sign-in survives lock/unlock: the link is stored encrypted.
        b.lock();
        assert!(b.is_linked().unwrap());
        b.unlock(PW, &sk).unwrap();
        assert_eq!(arcanum_sync::sync_now(&mut b).unwrap().pulled, 0);
    })
    .await
    .unwrap();
}

#[tokio::test(flavor = "multi_thread")]
async fn bad_credentials_look_like_unknown_accounts() {
    let url = start_server(pool().await).await;
    blocking(move || {
        let email = email();
        let (_, sk) = registered_device(&url, &email);

        let wrong_pw = arcanum_sync::sign_in(
            &mut Vault::open_in_memory().unwrap(),
            &url,
            &email,
            b"nope",
            &sk,
            "X",
        );
        assert!(
            matches!(wrong_pw, Err(SyncError::InvalidLogin)),
            "{wrong_pw:?}"
        );

        let other_sk = SecretKey::generate().unwrap();
        let wrong_sk = arcanum_sync::sign_in(
            &mut Vault::open_in_memory().unwrap(),
            &url,
            &email,
            PW,
            &other_sk,
            "X",
        );
        assert!(
            matches!(wrong_sk, Err(SyncError::InvalidLogin)),
            "{wrong_sk:?}"
        );

        let unknown = arcanum_sync::sign_in(
            &mut Vault::open_in_memory().unwrap(),
            &url,
            &self::email(),
            PW,
            &sk,
            "X",
        );
        assert!(
            matches!(unknown, Err(SyncError::InvalidLogin)),
            "{unknown:?}"
        );

        // Prelogin answers consistently for accounts that don't exist.
        let client = arcanum_sync::Client::new(&url).unwrap();
        let ghost = self::email();
        assert_eq!(
            client.prelogin(&ghost).unwrap(),
            client.prelogin(&ghost).unwrap()
        );
    })
    .await
    .unwrap();
}

#[tokio::test(flavor = "multi_thread")]
async fn email_cannot_be_registered_twice() {
    let url = start_server(pool().await).await;
    blocking(move || {
        let email = email();
        registered_device(&url, &email);
        let mut other = Vault::open_in_memory().unwrap();
        let sk = other.create(PW, KdfParams::DEFAULT).unwrap();
        let r = arcanum_sync::register(&mut other, &url, &email.to_uppercase(), PW, &sk, "X");
        assert!(matches!(r, Err(SyncError::EmailTaken)), "{r:?}");
    })
    .await
    .unwrap();
}

#[tokio::test(flavor = "multi_thread")]
async fn password_change_signs_out_other_devices() {
    let url = start_server(pool().await).await;
    blocking(move || {
        let email = email();
        let (mut a, sk) = registered_device(&url, &email);
        let mut b = Vault::open_in_memory().unwrap();
        arcanum_sync::sign_in(&mut b, &url, &email, PW, &sk, "Phone").unwrap();

        arcanum_sync::change_password(&mut a, PW, b"new password!", &sk).unwrap();
        assert!(
            arcanum_sync::sync_now(&mut a).is_ok(),
            "changing device stays signed in"
        );

        let r = arcanum_sync::sync_now(&mut b);
        assert!(
            matches!(r, Err(SyncError::Vault(VaultError::Unauthorized))),
            "{r:?}"
        );

        let old = arcanum_sync::sign_in(
            &mut Vault::open_in_memory().unwrap(),
            &url,
            &email,
            PW,
            &sk,
            "C",
        );
        assert!(matches!(old, Err(SyncError::InvalidLogin)));
        let mut c = Vault::open_in_memory().unwrap();
        arcanum_sync::sign_in(&mut c, &url, &email, b"new password!", &sk, "C").unwrap();
        assert_eq!(c.items().unwrap().len(), 1);

        a.lock();
        a.unlock(b"new password!", &sk).unwrap();
    })
    .await
    .unwrap();
}

#[tokio::test(flavor = "multi_thread")]
async fn unlink_revokes_the_session() {
    let url = start_server(pool().await).await;
    blocking(move || {
        let email = email();
        let (mut a, _) = registered_device(&url, &email);
        let link = a.sync_link().unwrap().unwrap();
        arcanum_sync::unlink(&mut a).unwrap();
        assert!(!a.is_linked().unwrap());

        let stale = arcanum_sync::Client::new(&url)
            .unwrap()
            .with_token(link.token.clone());
        assert!(matches!(stale.devices(), Err(SyncError::Unauthorized)));
    })
    .await
    .unwrap();
}

#[tokio::test(flavor = "multi_thread")]
async fn devices_can_be_listed_and_revoked() {
    let url = start_server(pool().await).await;
    blocking(move || {
        let email = email();
        let (a, sk) = registered_device(&url, &email);
        let mut b = Vault::open_in_memory().unwrap();
        arcanum_sync::sign_in(&mut b, &url, &email, PW, &sk, "Phone").unwrap();

        let token = a.sync_link().unwrap().unwrap().token.clone();
        let client = arcanum_sync::Client::new(&url).unwrap().with_token(token);
        let devices = client.devices().unwrap();
        assert_eq!(devices.len(), 2);
        let phone = devices.iter().find(|d| d.name == "Phone").unwrap();
        assert!(!phone.current);
        client.revoke_device(&phone.id).unwrap();

        assert!(matches!(
            arcanum_sync::sync_now(&mut b),
            Err(SyncError::Vault(VaultError::Unauthorized))
        ));
    })
    .await
    .unwrap();
}

#[tokio::test(flavor = "multi_thread")]
async fn repeated_failed_logins_are_throttled() {
    let url = start_server(pool().await).await;
    blocking(move || {
        let email = email();
        let (_, sk) = registered_device(&url, &email);
        let mut throttled = false;
        for _ in 0..12 {
            let r = arcanum_sync::sign_in(
                &mut Vault::open_in_memory().unwrap(),
                &url,
                &email,
                b"guess",
                &sk,
                "X",
            );
            if matches!(r, Err(SyncError::TooManyRequests)) {
                throttled = true;
                break;
            }
        }
        assert!(throttled);
    })
    .await
    .unwrap();
}

#[tokio::test(flavor = "multi_thread")]
async fn server_stores_no_plaintext() {
    let pool = pool().await;
    let url = start_server(pool.clone()).await;
    let email = email();
    let account_id = {
        let (url, email) = (url.clone(), email.clone());
        blocking(move || {
            let (a, _) = registered_device(&url, &email);
            a.account_bundle().unwrap().account_id
        })
        .await
        .unwrap()
    };

    let account_id = Uuid::parse_str(&account_id).unwrap();
    let mut blobs: Vec<Vec<u8>> = sqlx::query_scalar(
        "SELECT i.ciphertext FROM items i JOIN vaults v ON v.id = i.vault_id WHERE v.account_id = $1",
    )
    .bind(account_id)
    .fetch_all(&pool)
    .await
    .unwrap();
    assert_eq!(blobs.len(), 1);
    let record: Vec<u8> = sqlx::query_scalar("SELECT opaque_record FROM accounts WHERE id = $1")
        .bind(account_id)
        .fetch_one(&pool)
        .await
        .unwrap();
    blobs.push(record);
    let keys: String = sqlx::query_scalar("SELECT account_keys::text FROM accounts WHERE id = $1")
        .bind(account_id)
        .fetch_one(&pool)
        .await
        .unwrap();
    blobs.push(keys.into_bytes());

    let all: Vec<u8> = blobs.concat();
    for needle in [&b"gh-secret-1"[..], b"GitHub", b"alice", PW] {
        assert!(
            !all.windows(needle.len()).any(|w| w == needle),
            "plaintext {:?} found in server database",
            String::from_utf8_lossy(needle)
        );
    }
}

#[tokio::test(flavor = "multi_thread")]
async fn reconnect_after_password_change_elsewhere() {
    let url = start_server(pool().await).await;
    blocking(move || {
        let email = email();
        let (mut a, sk) = registered_device(&url, &email);
        let mut b = Vault::open_in_memory().unwrap();
        arcanum_sync::sign_in(&mut b, &url, &email, PW, &sk, "Phone").unwrap();

        arcanum_sync::change_password(&mut a, PW, b"new password!", &sk).unwrap();
        a.add_item(&login("After change", "x")).unwrap();
        arcanum_sync::sync_now(&mut a).unwrap();

        // B is still unlocked with the old local keys and gets signed out.
        assert!(matches!(
            arcanum_sync::sync_now(&mut b),
            Err(SyncError::Vault(VaultError::Unauthorized))
        ));
        let r = arcanum_sync::reconnect(&mut b, PW, &sk, "Phone");
        assert!(matches!(r, Err(SyncError::InvalidLogin)), "{r:?}");

        assert_eq!(
            arcanum_sync::reconnect(&mut b, b"new password!", &sk, "Phone")
                .unwrap()
                .pulled,
            1
        );
        // The new password now also unlocks B locally.
        b.lock();
        assert!(b.unlock(PW, &sk).is_err());
        b.unlock(b"new password!", &sk).unwrap();
        assert_eq!(b.items().unwrap().len(), 2);
    })
    .await
    .unwrap();
}

#[tokio::test(flavor = "multi_thread")]
async fn stolen_token_cannot_change_password() {
    let url = start_server(pool().await).await;
    blocking(move || {
        let email = email();
        let (a, sk) = registered_device(&url, &email);
        let token = a.sync_link().unwrap().unwrap().token.clone();
        let thief = arcanum_sync::Client::new(&url).unwrap().with_token(token);

        // The attacker has the token but not the password + Secret Key.
        let fake = |pw: &[u8]| {
            arcanum_crypto::kdf::derive_keys(
                pw,
                &SecretKey::generate().unwrap(),
                &[0; 16],
                &KdfParams::DEFAULT,
            )
            .unwrap()
            .auth_key
        };
        let keys = a.account_bundle().unwrap().keys;
        let r = thief.change_password(&email, &fake(b"guess"), &fake(b"mine"), &keys);
        assert!(matches!(r, Err(SyncError::InvalidLogin)), "{r:?}");

        // The real owner can still sign in with the original password.
        let mut b = Vault::open_in_memory().unwrap();
        arcanum_sync::sign_in(&mut b, &url, &email, PW, &sk, "Phone").unwrap();
    })
    .await
    .unwrap();
}

/// What the restore procedure leaves behind: data from before the backup,
/// no sessions, no epoch. A device that kept working afterwards must get
/// everything back onto the server after reconnecting.
#[tokio::test(flavor = "multi_thread")]
async fn restored_server_gets_resynced_by_devices() {
    let pool = pool().await;
    let url = start_server(pool.clone()).await;
    let email = email();
    let (mut a, sk, account) = {
        let (url, email) = (url.clone(), email.clone());
        blocking(move || {
            let (mut a, sk) = registered_device(&url, &email);
            a.add_item(&login("After backup", "x")).unwrap();
            arcanum_sync::sync_now(&mut a).unwrap();
            let link = a.sync_link().unwrap().unwrap();
            (a, sk, link)
        })
        .await
        .unwrap()
    };
    let account_id: Uuid = sqlx::query_scalar("SELECT id FROM accounts WHERE email = $1")
        .bind(&account.email)
        .fetch_one(&pool)
        .await
        .unwrap();
    let count = |pool: PgPool| async move {
        sqlx::query_scalar::<_, i64>(
            "SELECT count(*) FROM items i JOIN vaults v ON v.id = i.vault_id
             WHERE v.account_id = $1 AND NOT i.deleted",
        )
        .bind(account_id)
        .fetch_one(&pool)
        .await
        .unwrap()
    };
    assert_eq!(count(pool.clone()).await, 2);

    // "Restore": the newest item is gone, sessions are cleared and the
    // epoch is dropped, then the server starts again.
    sqlx::query(
        "DELETE FROM items WHERE id = (SELECT i.id FROM items i JOIN vaults v ON v.id = i.vault_id
         WHERE v.account_id = $1 ORDER BY i.seq DESC LIMIT 1)",
    )
    .bind(account_id)
    .execute(&pool)
    .await
    .unwrap();
    sqlx::query("DELETE FROM sessions WHERE account_id = $1")
        .bind(account_id)
        .execute(&pool)
        .await
        .unwrap();
    sqlx::query("DELETE FROM server_config WHERE key = 'sync_epoch'")
        .execute(&pool)
        .await
        .unwrap();
    let restarted = start_server(pool.clone()).await;
    assert_eq!(count(pool.clone()).await, 1);

    blocking(move || {
        // Same server address after a real restart; here a new port.
        a.set_sync_link(&arcanum_vault::SyncLink {
            server_url: restarted,
            email: account.email.clone(),
            token: account.token.clone(),
        })
        .unwrap();
        assert!(matches!(
            arcanum_sync::sync_now(&mut a),
            Err(SyncError::Vault(VaultError::Unauthorized))
        ));
        let r = arcanum_sync::reconnect(&mut a, PW, &sk, "Laptop").unwrap();
        assert_eq!(r.pushed, 1, "{r:?}"); // only the item the restore lost
        assert_eq!(r.conflicts, 0, "{r:?}");
        assert_eq!(a.items().unwrap().len(), 2);
    })
    .await
    .unwrap();
    assert_eq!(count(pool).await, 2);
}

#[tokio::test(flavor = "multi_thread")]
async fn cursor_beyond_the_server_is_reported() {
    let url = start_server(pool().await).await;
    blocking(move || {
        use arcanum_vault::SyncTransport;
        let (a, _) = registered_device(&url, &email());
        let token = a.sync_link().unwrap().unwrap().token.clone();
        let mut client = arcanum_sync::Client::new(&url).unwrap().with_token(token);
        assert!(client.pull(0).is_ok());
        assert!(matches!(
            client.pull(i64::MAX / 2),
            Err(VaultError::ServerRestored)
        ));
    })
    .await
    .unwrap();
}
