//! End-to-end: real server binary + PostgreSQL + the HTTP sync client.
//!
//! Needs a database: `TEST_DATABASE_URL` (default
//! `postgres://postgres@localhost:5433/arcanum_test`), and the server binary:
//! `cargo build` in `server/`, or `ARCANUM_SERVER_BIN`. Each test starts its
//! own server process on a free port and creates fresh accounts (each with its
//! own Secret Key, hence login id), so tests can share the database.

#![allow(clippy::unwrap_used, clippy::expect_used)]

use std::env;
use std::net::TcpListener;
use std::path::PathBuf;
use std::process::{Child, Command, Stdio};
use std::thread;
use std::time::{Duration, Instant};

use arcanum_crypto::kdf::login_id;
use arcanum_sync::SyncError;
use arcanum_vault::{ItemData, KdfParams, SecretKey, Vault, VaultError};
use postgres::{Client, NoTls};
use uuid::Uuid;

const PW: &[u8] = b"correct horse battery staple";

fn database_url() -> String {
    env::var("TEST_DATABASE_URL")
        .unwrap_or_else(|_| "postgres://postgres@localhost:5433/arcanum_test".into())
}

fn server_bin() -> PathBuf {
    if let Some(path) = env::var_os("ARCANUM_SERVER_BIN") {
        return path.into();
    }
    let path = PathBuf::from(env!("CARGO_MANIFEST_DIR"))
        .join("../server/target/debug")
        .join(format!("arcanum-server{}", env::consts::EXE_SUFFIX));
    assert!(
        path.exists(),
        "server binary not found at {} (run `cargo build` in server/ or set ARCANUM_SERVER_BIN)",
        path.display()
    );
    path
}

/// The server binary with a clean environment pointing at the test database.
fn server_command() -> Command {
    let mut cmd = Command::new(server_bin());
    cmd.env("DATABASE_URL", database_url())
        .env("RUST_LOG", "warn")
        .env_remove("BIND_ADDR")
        .env_remove("ARCANUM_REGISTRATION")
        .env_remove("ARCANUM_MAX_ITEMS_PER_ACCOUNT")
        .env_remove("TRUST_PROXY");
    cmd
}

/// Direct database access, to check what the server stored. The schema
/// exists once a server has started or an admin command has run (both
/// apply the migrations).
fn db() -> Client {
    Client::connect(&database_url(), NoTls)
        .expect("test database not reachable (set TEST_DATABASE_URL)")
}

/// A running `arcanum-server` process, stopped when dropped.
struct Server {
    child: Child,
    url: String,
}

impl Server {
    /// Starts a server configured through environment variables, as in
    /// production. With none set the server is invite-only.
    fn start(config: &[(&str, &str)]) -> Self {
        let port = TcpListener::bind("127.0.0.1:0")
            .and_then(|l| l.local_addr())
            .expect("free port")
            .port();
        let mut cmd = server_command();
        cmd.env("BIND_ADDR", format!("127.0.0.1:{port}"))
            .stdout(Stdio::null());
        for (key, value) in config {
            cmd.env(key, value);
        }
        let child = cmd.spawn().expect("start arcanum-server");
        let mut server = Self {
            child,
            url: format!("http://127.0.0.1:{port}"),
        };
        server.wait_ready();
        server
    }

    fn wait_ready(&mut self) {
        let health = format!("{}/health", self.url);
        let deadline = Instant::now() + Duration::from_secs(60);
        loop {
            if ureq::get(&health).call().is_ok() {
                return;
            }
            if let Some(status) = self.child.try_wait().expect("server status") {
                panic!("arcanum-server exited before answering: {status}");
            }
            assert!(
                Instant::now() < deadline,
                "arcanum-server did not answer on {}",
                self.url
            );
            thread::sleep(Duration::from_millis(50));
        }
    }
}

impl Drop for Server {
    fn drop(&mut self) {
        let _ = self.child.kill();
        let _ = self.child.wait();
    }
}

/// A server with open registration.
fn open_server() -> Server {
    Server::start(&[("ARCANUM_REGISTRATION", "open")])
}

/// Runs an admin command (`arcanum-server invite …` / `account …`).
fn admin(args: &[&str]) -> Result<String, String> {
    let out = server_command()
        .args(args)
        .output()
        .expect("run arcanum-server admin command");
    if out.status.success() {
        Ok(String::from_utf8_lossy(&out.stdout).into_owned())
    } else {
        Err(String::from_utf8_lossy(&out.stderr).into_owned())
    }
}

/// Creates a 7-day invite with the admin CLI: (invite id, code).
fn create_invite(label: Option<&str>) -> (Uuid, String) {
    let mut args = vec!["invite", "create", "--days", "7"];
    if let Some(label) = label {
        args.extend(["--label", label]);
    }
    let out = admin(&args).unwrap();
    let id = out
        .split_whitespace()
        .nth(1)
        .and_then(|w| Uuid::parse_str(w).ok())
        .unwrap_or_else(|| panic!("no invite id in {out:?}"));
    (id, invite_code(&out))
}

fn invite_code(admin_output: &str) -> String {
    admin_output
        .split_whitespace()
        .find(|w| w.starts_with("INV-"))
        .unwrap_or_else(|| panic!("no invite code in {admin_output:?}"))
        .to_owned()
}

fn login(title: &str, password: &str) -> ItemData {
    let mut d = ItemData::default();
    d.title = title.into();
    d.username = "alice".into();
    d.password = password.into();
    d
}

/// Device A: new local vault with one item, registered on the server.
fn registered_device(url: &str) -> (Vault, SecretKey) {
    let mut a = Vault::open_in_memory().unwrap();
    let sk = a.create(PW, KdfParams::DEFAULT).unwrap();
    a.add_item(&login("GitHub", "gh-secret-1")).unwrap();
    let r = arcanum_sync::register(&mut a, url, PW, &sk, "Laptop", None).unwrap();
    assert_eq!(r.pushed, 1);
    (a, sk)
}

#[test]
fn register_sign_in_and_sync_both_ways() {
    let server = open_server();
    let url = &server.url;
    let (mut a, sk) = registered_device(url);

    let mut b = Vault::open_in_memory().unwrap();
    let r = arcanum_sync::sign_in(&mut b, url, PW, &sk, "Phone").unwrap();
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
}

#[test]
fn bad_credentials_look_like_unknown_accounts() {
    let server = open_server();
    let url = &server.url;
    let (_, sk) = registered_device(url);

    let wrong_pw = arcanum_sync::sign_in(
        &mut Vault::open_in_memory().unwrap(),
        url,
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
        url,
        PW,
        &other_sk,
        "X",
    );
    assert!(
        matches!(wrong_sk, Err(SyncError::InvalidLogin)),
        "{wrong_sk:?}"
    );

    // Prelogin answers consistently for accounts that don't exist.
    let client = arcanum_sync::Client::new(url).unwrap();
    let ghost = login_id(&SecretKey::generate().unwrap()).unwrap();
    assert_eq!(
        client.prelogin(&ghost).unwrap(),
        client.prelogin(&ghost).unwrap()
    );
}

#[test]
fn account_cannot_be_registered_twice() {
    let server = open_server();
    let url = &server.url;
    let (mut a, sk) = registered_device(url);
    arcanum_sync::unlink(&mut a).unwrap();
    let r = arcanum_sync::register(&mut a, url, PW, &sk, "X", None);
    assert!(matches!(r, Err(SyncError::AccountExists)), "{r:?}");
}

#[test]
fn password_change_signs_out_other_devices() {
    let server = open_server();
    let url = &server.url;
    let (mut a, sk) = registered_device(url);
    let mut b = Vault::open_in_memory().unwrap();
    arcanum_sync::sign_in(&mut b, url, PW, &sk, "Phone").unwrap();

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

    let old = arcanum_sync::sign_in(&mut Vault::open_in_memory().unwrap(), url, PW, &sk, "C");
    assert!(matches!(old, Err(SyncError::InvalidLogin)));
    let mut c = Vault::open_in_memory().unwrap();
    arcanum_sync::sign_in(&mut c, url, b"new password!", &sk, "C").unwrap();
    assert_eq!(c.items().unwrap().len(), 1);

    a.lock();
    a.unlock(b"new password!", &sk).unwrap();
}

#[test]
fn unlink_revokes_the_session() {
    let server = open_server();
    let url = &server.url;
    let (mut a, _) = registered_device(url);
    let link = a.sync_link().unwrap().unwrap();
    arcanum_sync::unlink(&mut a).unwrap();
    assert!(!a.is_linked().unwrap());

    let stale = arcanum_sync::Client::new(url)
        .unwrap()
        .with_token(link.token.clone());
    assert!(matches!(stale.devices(), Err(SyncError::Unauthorized)));
}

#[test]
fn devices_can_be_listed_and_revoked() {
    let server = open_server();
    let url = &server.url;
    let (a, sk) = registered_device(url);
    let mut b = Vault::open_in_memory().unwrap();
    arcanum_sync::sign_in(&mut b, url, PW, &sk, "Phone").unwrap();

    let devices = arcanum_sync::devices(&a).unwrap();
    assert_eq!(devices.len(), 2);
    let phone = devices
        .iter()
        .find(|d| d.name.as_deref() == Some("Phone"))
        .unwrap();
    assert!(!phone.current);
    let laptop = devices.iter().find(|d| d.current).unwrap();
    assert_eq!(laptop.name.as_deref(), Some("Laptop"));
    arcanum_sync::revoke_device(&a, &phone.id).unwrap();

    assert!(matches!(
        arcanum_sync::sync_now(&mut b),
        Err(SyncError::Vault(VaultError::Unauthorized))
    ));
}

#[test]
fn repeated_failed_logins_are_throttled() {
    let server = open_server();
    let url = &server.url;
    let (_, sk) = registered_device(url);
    let mut throttled = false;
    for _ in 0..12 {
        let r = arcanum_sync::sign_in(
            &mut Vault::open_in_memory().unwrap(),
            url,
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
}

#[test]
fn server_stores_no_plaintext() {
    let server = open_server();
    let (a, _) = registered_device(&server.url);
    let account_id = Uuid::parse_str(&a.account_bundle().unwrap().account_id).unwrap();

    let mut db = db();
    let mut blobs: Vec<Vec<u8>> = db
        .query(
            "SELECT i.ciphertext FROM items i JOIN vaults v ON v.id = i.vault_id WHERE v.account_id = $1",
            &[&account_id],
        )
        .unwrap()
        .iter()
        .map(|row| row.get(0))
        .collect();
    assert_eq!(blobs.len(), 1);
    let record: Vec<u8> = db
        .query_one(
            "SELECT opaque_record FROM accounts WHERE id = $1",
            &[&account_id],
        )
        .unwrap()
        .get(0);
    blobs.push(record);
    let keys: String = db
        .query_one(
            "SELECT account_keys::text FROM accounts WHERE id = $1",
            &[&account_id],
        )
        .unwrap()
        .get(0);
    blobs.push(keys.into_bytes());
    let names: Vec<Option<Vec<u8>>> = db
        .query(
            "SELECT device_name FROM sessions WHERE account_id = $1",
            &[&account_id],
        )
        .unwrap()
        .iter()
        .map(|row| row.get(0))
        .collect();
    assert!(names.iter().all(Option::is_some), "device name was set");
    blobs.extend(names.into_iter().flatten());

    let all: Vec<u8> = blobs.concat();
    for needle in [&b"gh-secret-1"[..], b"GitHub", b"alice", b"Laptop", PW] {
        assert!(
            !all.windows(needle.len()).any(|w| w == needle),
            "plaintext {:?} found in server database",
            String::from_utf8_lossy(needle)
        );
    }
}

#[test]
fn reconnect_after_password_change_elsewhere() {
    let server = open_server();
    let url = &server.url;
    let (mut a, sk) = registered_device(url);
    let mut b = Vault::open_in_memory().unwrap();
    arcanum_sync::sign_in(&mut b, url, PW, &sk, "Phone").unwrap();

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
}

#[test]
fn stolen_token_cannot_change_password() {
    let server = open_server();
    let url = &server.url;
    let (a, sk) = registered_device(url);
    let token = a.sync_link().unwrap().unwrap().token.clone();
    let thief = arcanum_sync::Client::new(url).unwrap().with_token(token);

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
    let id = login_id(&sk).unwrap();
    let r = thief.change_password(&id, &fake(b"guess"), &fake(b"mine"), &keys);
    assert!(matches!(r, Err(SyncError::InvalidLogin)), "{r:?}");

    // The real owner can still sign in with the original password.
    let mut b = Vault::open_in_memory().unwrap();
    arcanum_sync::sign_in(&mut b, url, PW, &sk, "Phone").unwrap();
}

/// What the restore procedure leaves behind: data from before the backup,
/// no sessions, no epoch. A device that kept working afterwards must get
/// everything back onto the server after reconnecting.
#[test]
fn restored_server_gets_resynced_by_devices() {
    let server = open_server();
    let (mut a, sk) = registered_device(&server.url);
    a.add_item(&login("After backup", "x")).unwrap();
    arcanum_sync::sync_now(&mut a).unwrap();
    let account = a.sync_link().unwrap().unwrap();

    let mut db = db();
    let account_id: Uuid = db
        .query_one(
            "SELECT id FROM accounts WHERE login_id = $1",
            &[&login_id(&sk).unwrap()],
        )
        .unwrap()
        .get(0);
    let count = |db: &mut Client| -> i64 {
        db.query_one(
            "SELECT count(*) FROM items i JOIN vaults v ON v.id = i.vault_id
             WHERE v.account_id = $1 AND NOT i.deleted",
            &[&account_id],
        )
        .unwrap()
        .get(0)
    };
    assert_eq!(count(&mut db), 2);

    // "Restore": the newest item is gone, sessions are cleared and the
    // epoch is dropped, then the server starts again.
    db.execute(
        "DELETE FROM items WHERE id = (SELECT i.id FROM items i JOIN vaults v ON v.id = i.vault_id
         WHERE v.account_id = $1 ORDER BY i.seq DESC LIMIT 1)",
        &[&account_id],
    )
    .unwrap();
    db.execute("DELETE FROM sessions WHERE account_id = $1", &[&account_id])
        .unwrap();
    db.execute("DELETE FROM server_config WHERE key = 'sync_epoch'", &[])
        .unwrap();
    drop(server);
    let restarted = open_server();
    assert_eq!(count(&mut db), 1);

    // Same server address after a real restart; here a new port.
    a.set_sync_link(&arcanum_vault::SyncLink {
        server_url: restarted.url.clone(),
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
    assert_eq!(count(&mut db), 2);
}

#[test]
fn cursor_beyond_the_server_is_reported() {
    use arcanum_vault::SyncTransport;

    let server = open_server();
    let url = &server.url;
    let (a, _) = registered_device(url);
    let token = a.sync_link().unwrap().unwrap().token.clone();
    let mut client = arcanum_sync::Client::new(url).unwrap().with_token(token);
    assert!(client.pull(0).is_ok());
    assert!(matches!(
        client.pull(i64::MAX / 2),
        Err(VaultError::ServerRestored)
    ));
}

/// A registration that goes through: fresh vault, optional invite.
fn try_register(url: &str, invite: Option<&str>) -> Result<(Vault, SecretKey), SyncError> {
    let mut v = Vault::open_in_memory().unwrap();
    let sk = v.create(PW, KdfParams::DEFAULT).unwrap();
    arcanum_sync::register(&mut v, url, PW, &sk, "Laptop", invite)?;
    Ok((v, sk))
}

#[test]
fn invite_only_registration() {
    let server = Server::start(&[]); // the default: invite-only
    let url = &server.url;
    let (invite_id, code) = create_invite(Some("Mario (E1234)"));
    let (expired_id, expired) = create_invite(None);
    let mut db = db();
    db.execute(
        "UPDATE invites SET expires_at = 0 WHERE id = $1",
        &[&expired_id],
    )
    .unwrap();

    let r = try_register(url, None).map(drop);
    assert!(matches!(r, Err(SyncError::InviteRequired)), "{r:?}");
    let r = try_register(url, Some("INV-NOPE")).map(drop);
    assert!(matches!(r, Err(SyncError::InvalidInvite)), "{r:?}");
    let r = try_register(url, Some(&expired)).map(drop);
    assert!(matches!(r, Err(SyncError::InvalidInvite)), "{r:?}");

    // Typed sloppily from paper: still accepted.
    let typed = code.to_lowercase().replace('-', " ");
    let (_, sk) = try_register(url, Some(&typed)).unwrap();
    // Single use.
    let r = try_register(url, Some(&code)).map(drop);
    assert!(matches!(r, Err(SyncError::InvalidInvite)), "{r:?}");

    let label: Option<String> = db
        .query_one(
            "SELECT label FROM accounts WHERE login_id = $1",
            &[&login_id(&sk).unwrap()],
        )
        .unwrap()
        .get(0);
    assert_eq!(label.as_deref(), Some("Mario (E1234)"));
    let used: Option<i64> = db
        .query_one("SELECT used_at FROM invites WHERE id = $1", &[&invite_id])
        .unwrap()
        .get(0);
    assert!(used.is_some());
}

#[test]
fn failed_registration_does_not_burn_the_invite() {
    let server = Server::start(&[]);
    let url = &server.url;
    let (_, first) = create_invite(None);
    let (_, second) = create_invite(None);

    let (mut a, sk) = try_register(url, Some(&first)).unwrap();
    // A duplicate registration fails and leaves `second` unused...
    arcanum_sync::unlink(&mut a).unwrap();
    let r = arcanum_sync::register(&mut a, url, PW, &sk, "X", Some(&second));
    assert!(matches!(r, Err(SyncError::AccountExists)), "{r:?}");
    // ...so someone else can still use it.
    try_register(url, Some(&second)).unwrap();
}

#[test]
fn closed_registration() {
    let server = Server::start(&[("ARCANUM_REGISTRATION", "closed")]);
    let r = try_register(&server.url, Some("INV-ANYTHING")).map(drop);
    assert!(matches!(r, Err(SyncError::RegistrationClosed)), "{r:?}");
}

#[test]
fn admin_commands() {
    let code = invite_code(&admin(&["invite", "create", "--label", "Ufficio"]).unwrap());
    let server = Server::start(&[]);
    let sk = try_register(&server.url, Some(&code)).unwrap().1;
    let id: Uuid = db()
        .query_one(
            "SELECT id FROM accounts WHERE login_id = $1",
            &[&login_id(&sk).unwrap()],
        )
        .unwrap()
        .get(0);
    let id_text = id.to_string();

    let list = admin(&["account", "list"]).unwrap();
    assert!(
        list.contains(&id_text) && list.contains("Ufficio"),
        "{list}"
    );
    admin(&["account", "delete", &id_text]).unwrap();
    let left: i64 = db()
        .query_one("SELECT count(*) FROM accounts WHERE id = $1", &[&id])
        .unwrap()
        .get(0);
    assert_eq!(left, 0);
    assert!(admin(&["bogus"]).is_err());
}

#[test]
fn item_quota_is_enforced() {
    let server = Server::start(&[
        ("ARCANUM_REGISTRATION", "open"),
        ("ARCANUM_MAX_ITEMS_PER_ACCOUNT", "2"),
    ]);
    let (mut a, _) = registered_device(&server.url); // 1 item
    a.add_item(&login("Second", "x")).unwrap();
    assert_eq!(arcanum_sync::sync_now(&mut a).unwrap().pushed, 1);
    a.add_item(&login("Third", "x")).unwrap();
    let r = arcanum_sync::sync_now(&mut a);
    assert!(
        matches!(&r, Err(SyncError::Vault(VaultError::Transport(m))) if m.contains("quota")),
        "{r:?}"
    );
}

#[test]
fn unauthenticated_bodies_are_small() {
    let server = open_server();
    let big = format!(r#"{{"login_id":"{}"}}"#, "a".repeat(100 * 1024));
    let r = ureq::post(&format!("{}/v1/prelogin", server.url))
        .set("Content-Type", "application/json")
        .send_string(&big);
    // The server stops reading at the limit, answers 413 and closes the
    // connection. The client sees the 413, or, when it is still uploading,
    // the connection closing under it: both mean the body was refused.
    let refused = match &r {
        Err(ureq::Error::Status(413, _)) => true,
        Err(ureq::Error::Transport(t)) => std::error::Error::source(t)
            .and_then(|e| e.downcast_ref::<std::io::Error>())
            .is_some_and(|e| {
                matches!(
                    e.kind(),
                    std::io::ErrorKind::BrokenPipe | std::io::ErrorKind::ConnectionReset
                )
            }),
        _ => false,
    };
    assert!(refused, "{r:?}");
    // Refused, not crashed.
    let h = ureq::get(&format!("{}/health", server.url)).call().unwrap();
    assert_eq!(h.into_string().unwrap(), "ok");
}

#[test]
fn auth_endpoints_are_rate_limited_per_ip() {
    let server = open_server();
    let url = &server.url;
    let client = arcanum_sync::Client::new(url).unwrap();
    let id = login_id(&SecretKey::generate().unwrap()).unwrap();
    let mut limited = false;
    for _ in 0..70 {
        match client.prelogin(&id) {
            Ok(_) => {}
            Err(SyncError::TooManyRequests) => {
                limited = true;
                break;
            }
            Err(e) => panic!("{e:?}"),
        }
    }
    assert!(limited);
    // Other endpoints of the API still answer for this client.
    let h = ureq::get(&format!("{url}/health")).call().unwrap();
    assert_eq!(h.into_string().unwrap(), "ok");
}

#[test]
fn malformed_login_attempts_do_not_lock_the_account() {
    let server = open_server();
    let url = &server.url;
    let (_, sk) = registered_device(url);
    let id = login_id(&sk).unwrap();
    // Garbage OPAQUE messages are rejected without counting as attempts.
    for _ in 0..15 {
        let r = ureq::post(&format!("{url}/v1/login/start"))
            .send_json(serde_json::json!({"login_id": id, "message": "AAAA"}));
        assert!(matches!(r, Err(ureq::Error::Status(400, _))), "{r:?}");
    }
    let mut b = Vault::open_in_memory().unwrap();
    arcanum_sync::sign_in(&mut b, url, PW, &sk, "Phone").unwrap();
}
