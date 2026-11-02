//! Two-device sync scenarios against an in-memory server that applies the
//! same rules as the real one (sequence cursor, optimistic concurrency).

#![allow(clippy::unwrap_used, clippy::expect_used)]

use std::cell::RefCell;
use std::collections::HashMap;
use std::rc::Rc;

use arcanum_proto::{ItemRecord, PullResponse, PushRequest, PushResponse};
use arcanum_vault::{
    ItemData, KdfParams, Result, SecretKey, SyncLink, SyncTransport, Vault, VaultError,
};

const PW: &[u8] = b"correct horse battery staple";

#[derive(Default, Clone)]
struct ServerState {
    items: HashMap<String, (ItemRecord, i64)>,
    seq: i64,
    page_size: usize,
    epoch: String,
}

#[derive(Clone, Default)]
struct FakeServer(Rc<RefCell<ServerState>>);

impl FakeServer {
    fn with_page_size(n: usize) -> Self {
        let s = Self::default();
        s.0.borrow_mut().page_size = n;
        s
    }

    fn record(&self, id: &str) -> ItemRecord {
        self.0.borrow().items[id].0.clone()
    }

    fn snapshot(&self) -> ServerState {
        self.0.borrow().clone()
    }

    /// Puts the server back to `backup`, like the restore procedure: same
    /// data and sequence as then, with a new epoch unless `keep_epoch`.
    fn restore(&self, backup: &ServerState, keep_epoch: bool) {
        let mut s = self.0.borrow_mut();
        let epoch = if keep_epoch {
            backup.epoch.clone()
        } else {
            format!("{}-restored", backup.epoch)
        };
        *s = ServerState {
            epoch,
            ..backup.clone()
        };
    }

    fn live_titles(&self, vault: &Vault) -> Vec<String> {
        let ids: Vec<String> = self
            .0
            .borrow()
            .items
            .values()
            .filter(|(r, _)| !r.deleted)
            .map(|(r, _)| r.id.clone())
            .collect();
        let mut titles: Vec<String> = ids
            .iter()
            .map(|id| vault.item(id).unwrap().data.title.clone())
            .collect();
        titles.sort();
        titles
    }
}

impl SyncTransport for FakeServer {
    fn pull(&mut self, since: i64) -> Result<PullResponse> {
        let s = self.0.borrow();
        if since > s.seq {
            return Err(VaultError::ServerRestored); // what arcanum-sync maps cursor_ahead to
        }
        let mut changes: Vec<_> = s.items.values().filter(|(_, seq)| *seq > since).collect();
        changes.sort_by_key(|(_, seq)| *seq);
        let page = if s.page_size == 0 {
            usize::MAX
        } else {
            s.page_size
        };
        let has_more = changes.len() > page;
        changes.truncate(page);
        Ok(PullResponse {
            cursor: changes.last().map_or(since, |(_, seq)| *seq),
            items: changes.into_iter().map(|(r, _)| r.clone()).collect(),
            has_more,
            epoch: s.epoch.clone(),
        })
    }

    fn push(&mut self, request: &PushRequest) -> Result<PushResponse> {
        let mut s = self.0.borrow_mut();
        let mut resp = PushResponse::default();
        for p in &request.items {
            let accept = match s.items.get(&p.item.id) {
                None => true,
                Some((cur, _)) => {
                    p.base_revision == Some(cur.revision) && p.item.revision > cur.revision
                }
            };
            if accept {
                s.seq += 1;
                let seq = s.seq;
                s.items.insert(p.item.id.clone(), (p.item.clone(), seq));
                resp.accepted.push(p.item.id.clone());
            } else {
                resp.conflicts.push(s.items[&p.item.id].0.clone());
            }
        }
        Ok(resp)
    }
}

fn login(title: &str, password: &str) -> ItemData {
    let mut d = ItemData::default();
    d.title = title.into();
    d.password = password.into();
    d
}

/// Device A creates the account; device B is set up from A's bundle.
fn two_devices() -> (Vault, Vault, SecretKey) {
    let mut a = Vault::open_in_memory().unwrap();
    let sk = a.create(PW, KdfParams::DEFAULT).unwrap();
    let mut b = Vault::open_in_memory().unwrap();
    b.import_account(&a.account_bundle().unwrap()).unwrap();
    assert!(!b.is_unlocked());
    b.unlock(PW, &sk).unwrap();
    (a, b, sk)
}

fn titles(v: &Vault) -> Vec<String> {
    v.items()
        .unwrap()
        .into_iter()
        .map(|i| i.data.title.clone())
        .collect()
}

#[test]
fn add_edit_delete_propagate() {
    let (mut a, mut b, _) = two_devices();
    let mut server = FakeServer::default();

    let id = a.add_item(&login("GitHub", "v1")).unwrap().id;
    let r = a.sync(&mut server).unwrap();
    assert_eq!(r.pushed, 1);

    let r = b.sync(&mut server).unwrap();
    assert_eq!(r.pulled, 1);
    assert_eq!(b.item(&id).unwrap().data.password, "v1");

    b.update_item(&id, &login("GitHub", "v2")).unwrap();
    b.sync(&mut server).unwrap();
    a.sync(&mut server).unwrap();
    assert_eq!(a.item(&id).unwrap().data.password, "v2");

    a.delete_item(&id).unwrap();
    a.sync(&mut server).unwrap();
    b.sync(&mut server).unwrap();
    assert!(b.items().unwrap().is_empty());
    assert!(server.record(&id).deleted);
}

#[test]
fn sync_is_idempotent() {
    let (mut a, _, _) = two_devices();
    let mut server = FakeServer::default();
    a.add_item(&login("x", "y")).unwrap();
    a.sync(&mut server).unwrap();
    let again = a.sync(&mut server).unwrap();
    assert_eq!((again.pulled, again.pushed, again.conflicts), (0, 0, 0));
}

#[test]
fn concurrent_edits_keep_both_versions() {
    let (mut a, mut b, _) = two_devices();
    let mut server = FakeServer::default();
    let id = a.add_item(&login("Bank", "base")).unwrap().id;
    a.sync(&mut server).unwrap();
    b.sync(&mut server).unwrap();

    a.update_item(&id, &login("Bank", "from-a")).unwrap();
    std::thread::sleep(std::time::Duration::from_millis(5));
    b.update_item(&id, &login("Bank", "from-b")).unwrap(); // newer

    a.sync(&mut server).unwrap();
    let r = b.sync(&mut server).unwrap();
    assert_eq!(r.conflicts, 1);
    a.sync(&mut server).unwrap();

    // Newest edit wins on the original item; the other survives as a copy.
    for v in [&a, &b] {
        assert_eq!(v.item(&id).unwrap().data.password, "from-b");
        assert_eq!(titles(v), ["Bank", "Bank (conflitto)"]);
        let copy = v.items().unwrap().into_iter().find(|i| i.id != id).unwrap();
        assert_eq!(copy.data.password, "from-a");
    }
}

#[test]
fn edit_beats_delete() {
    let (mut a, mut b, _) = two_devices();
    let mut server = FakeServer::default();
    let id = a.add_item(&login("Mail", "base")).unwrap().id;
    a.sync(&mut server).unwrap();
    b.sync(&mut server).unwrap();

    b.update_item(&id, &login("Mail", "edited")).unwrap();
    std::thread::sleep(std::time::Duration::from_millis(5));
    a.delete_item(&id).unwrap(); // newer, but a delete

    a.sync(&mut server).unwrap();
    b.sync(&mut server).unwrap();
    a.sync(&mut server).unwrap();

    for v in [&a, &b] {
        assert_eq!(v.item(&id).unwrap().data.password, "edited");
        assert_eq!(titles(v), ["Mail"]);
    }
}

#[test]
fn many_offline_edits_then_sync() {
    let (mut a, mut b, _) = two_devices();
    let mut server = FakeServer::default();
    let id = a.add_item(&login("x", "0")).unwrap().id;
    for i in 1..=5 {
        a.update_item(&id, &login("x", &i.to_string())).unwrap();
    }
    a.sync(&mut server).unwrap();
    b.sync(&mut server).unwrap();
    assert_eq!(b.item(&id).unwrap().data.password, "5");
}

#[test]
fn pull_follows_pages() {
    let (mut a, mut b, _) = two_devices();
    let mut server = FakeServer::with_page_size(3);
    for i in 0..10 {
        a.add_item(&login(&format!("item {i:02}"), "p")).unwrap();
    }
    a.sync(&mut server).unwrap();
    let r = b.sync(&mut server).unwrap();
    assert_eq!(r.pulled, 10);
    assert_eq!(b.items().unwrap().len(), 10);
}

#[test]
fn tampered_server_record_does_not_overwrite_local() {
    let (mut a, mut b, _) = two_devices();
    let mut server = FakeServer::default();
    let id = a.add_item(&login("Secret", "real")).unwrap().id;
    a.sync(&mut server).unwrap();
    b.sync(&mut server).unwrap();

    a.update_item(&id, &login("Secret", "mine")).unwrap();
    // A malicious server bumps the revision with garbage ciphertext.
    {
        let mut s = server.0.borrow_mut();
        s.seq += 1;
        let seq = s.seq;
        let (rec, _) = s.items.get_mut(&id).unwrap();
        rec.revision += 10;
        rec.ciphertext[30] ^= 1;
        let rec = rec.clone();
        s.items.insert(id.clone(), (rec, seq));
    }
    a.sync(&mut server).unwrap();
    assert_eq!(a.item(&id).unwrap().data.password, "mine");
    b.sync(&mut server).unwrap();
    assert_eq!(b.item(&id).unwrap().data.password, "mine");
}

#[test]
fn sync_link_is_encrypted_and_requires_unlock() {
    let (mut a, _, sk) = two_devices();
    let link = SyncLink {
        server_url: "https://sync.example".into(),
        email: "a@example.com".into(),
        token: "secret-token".into(),
    };
    a.set_sync_link(&link).unwrap();
    assert_eq!(a.sync_link().unwrap(), Some(link.clone()));

    a.lock();
    assert!(a.is_linked().unwrap());
    assert!(matches!(a.sync_link(), Err(VaultError::Locked)));

    a.unlock(PW, &sk).unwrap();
    a.clear_sync_link().unwrap();
    assert_eq!(a.sync_link().unwrap(), None);
}

#[test]
fn relinking_uploads_everything_again() {
    let (mut a, _, _) = two_devices();
    let mut server = FakeServer::default();
    a.add_item(&login("x", "y")).unwrap();
    a.sync(&mut server).unwrap();

    a.clear_sync_link().unwrap();
    let mut fresh = FakeServer::default();
    let r = a.sync(&mut fresh).unwrap();
    assert_eq!(r.pushed, 1);
}

#[test]
fn import_into_initialized_vault_fails() {
    let (a, mut b, _) = two_devices();
    assert!(matches!(
        b.import_account(&a.account_bundle().unwrap()),
        Err(VaultError::AlreadyInitialized)
    ));
}

#[test]
fn auth_key_requires_correct_password() {
    let (a, _, sk) = two_devices();
    assert!(a.auth_key(PW, &sk).is_ok());
    assert!(matches!(
        a.auth_key(b"nope", &sk),
        Err(VaultError::WrongCredentials)
    ));
}

#[test]
fn phase2_database_is_migrated() {
    let dir = tempfile::tempdir().unwrap();
    let path = dir.path().join("vault.db");
    let sk;
    {
        let mut v = Vault::open(&path).unwrap();
        sk = v.create(PW, KdfParams::DEFAULT).unwrap();
        v.add_item(&login("old", "data")).unwrap();
    }
    // Roll the file back to the phase-2 (v1) schema.
    {
        let conn = rusqlite::Connection::open(&path).unwrap();
        conn.execute_batch(
            "ALTER TABLE items DROP COLUMN server_revision; PRAGMA user_version = 1;",
        )
        .unwrap();
    }
    let mut v = Vault::open(&path).unwrap();
    v.unlock(PW, &sk).unwrap();
    assert_eq!(titles(&v), ["old"]);
    let r = v.sync(&mut FakeServer::default()).unwrap();
    assert_eq!(r.pushed, 1);
}

fn sorted_titles(v: &Vault) -> Vec<String> {
    let mut t = titles(v);
    t.sort();
    t
}

/// A: two items synced, backup taken, then changes made after it.
fn restore_scenario(keep_epoch: bool) -> (Vault, FakeServer) {
    let (mut a, _, _) = two_devices();
    let server = FakeServer::default();
    server.0.borrow_mut().epoch = "e1".into();
    let mut t = server.clone();
    let old = a.add_item(&login("Old", "1")).unwrap();
    let edited = a.add_item(&login("Edited", "1")).unwrap();
    a.sync(&mut t).unwrap();
    let backup = server.snapshot();

    a.add_item(&login("New after backup", "2")).unwrap();
    let mut data = a.item(&edited.id).unwrap().data;
    data.password = "changed".into();
    a.update_item(&edited.id, &data).unwrap();
    a.sync(&mut t).unwrap();
    // A later periodic sync moves the cursor past our own pushes.
    a.sync(&mut t).unwrap();
    assert_eq!(a.item(&old.id).unwrap().data.title, "Old");

    server.restore(&backup, keep_epoch);
    (a, server)
}

#[test]
fn server_restore_with_new_epoch_resyncs_without_losing_data() {
    let (mut a, server) = restore_scenario(false);
    let mut t = server.clone();
    a.sync(&mut t).unwrap();

    // Nothing lost locally, no conflict copies, and the server has it all.
    assert_eq!(sorted_titles(&a), ["Edited", "New after backup", "Old"]);
    assert_eq!(
        server.live_titles(&a),
        ["Edited", "New after backup", "Old"]
    );
    let edited = a
        .items()
        .unwrap()
        .into_iter()
        .find(|i| i.data.title == "Edited")
        .unwrap();
    assert_eq!(server.record(&edited.id).revision, edited.revision);
    assert_eq!(edited.data.password, "changed");

    // Back to normal: a second sync has nothing to do.
    let r = a.sync(&mut t).unwrap();
    assert_eq!((r.pulled, r.pushed, r.conflicts), (0, 0, 0));
}

#[test]
fn server_restore_is_caught_by_cursor_even_with_the_old_epoch() {
    let (mut a, server) = restore_scenario(true);
    let mut t = server.clone();
    a.sync(&mut t).unwrap();
    assert_eq!(
        server.live_titles(&a),
        ["Edited", "New after backup", "Old"]
    );
}

#[test]
fn first_epoch_seen_does_not_resync() {
    let (mut a, _, _) = two_devices();
    let server = FakeServer::default();
    let mut t = server.clone();
    a.add_item(&login("x", "y")).unwrap();
    a.sync(&mut t).unwrap(); // server without epoch

    server.0.borrow_mut().epoch = "e1".into(); // server upgraded
    let r = a.sync(&mut t).unwrap();
    assert_eq!((r.pulled, r.pushed, r.conflicts), (0, 0, 0));
}

#[test]
fn deletion_after_backup_survives_restore() {
    let (mut a, _, _) = two_devices();
    let server = FakeServer::default();
    server.0.borrow_mut().epoch = "e1".into();
    let mut t = server.clone();
    let gone = a.add_item(&login("Gone", "1")).unwrap();
    a.add_item(&login("Kept", "1")).unwrap();
    a.sync(&mut t).unwrap();
    let backup = server.snapshot();

    a.delete_item(&gone.id).unwrap();
    a.sync(&mut t).unwrap();
    server.restore(&backup, false);

    a.sync(&mut t).unwrap();
    assert_eq!(titles(&a), ["Kept"]);
    assert!(server.record(&gone.id).deleted);
}

#[test]
fn edit_on_another_device_after_restore_is_kept_as_conflict() {
    let (mut a, mut b, _) = two_devices();
    let server = FakeServer::default();
    server.0.borrow_mut().epoch = "e1".into();
    let mut t = server.clone();
    let item = a.add_item(&login("Shared", "1")).unwrap();
    a.sync(&mut t).unwrap();
    b.sync(&mut t).unwrap();
    let backup = server.snapshot();

    let mut data = a.item(&item.id).unwrap().data;
    data.password = "from-a".into();
    a.update_item(&item.id, &data).unwrap();
    a.sync(&mut t).unwrap();
    a.sync(&mut t).unwrap();
    server.restore(&backup, false);

    // B resyncs first and edits the restored copy; A must not overwrite it.
    b.sync(&mut t).unwrap();
    let mut data = b.item(&item.id).unwrap().data;
    data.password = "from-b".into();
    b.update_item(&item.id, &data).unwrap();
    b.sync(&mut t).unwrap();

    a.sync(&mut t).unwrap();
    let passwords: Vec<String> = a
        .items()
        .unwrap()
        .into_iter()
        .map(|i| i.data.password.clone())
        .collect();
    assert!(passwords.contains(&"from-a".to_string()));
    assert!(passwords.contains(&"from-b".to_string()));
}

/// Two devices both kept working before the restore; the one that resyncs
/// second must take the other's re-pushed changes, not fight them.
#[test]
fn second_device_resyncs_without_spurious_conflicts() {
    let (mut a, mut b, _) = two_devices();
    let server = FakeServer::default();
    server.0.borrow_mut().epoch = "e1".into();
    let mut t = server.clone();
    let edited = a.add_item(&login("Edited", "1")).unwrap();
    let gone = a.add_item(&login("Gone", "1")).unwrap();
    a.sync(&mut t).unwrap();
    b.sync(&mut t).unwrap();
    let backup = server.snapshot();

    let mut data = a.item(&edited.id).unwrap().data;
    data.password = "changed".into();
    a.update_item(&edited.id, &data).unwrap();
    a.delete_item(&gone.id).unwrap();
    b.add_item(&login("From B", "b")).unwrap();
    a.sync(&mut t).unwrap();
    b.sync(&mut t).unwrap();
    a.sync(&mut t).unwrap();
    b.sync(&mut t).unwrap();
    server.restore(&backup, false);

    let ra = a.sync(&mut t).unwrap();
    let rb = b.sync(&mut t).unwrap();
    a.sync(&mut t).unwrap();
    assert_eq!((ra.conflicts, rb.conflicts), (0, 0));
    for v in [&a, &b] {
        assert_eq!(sorted_titles(v), ["Edited", "From B"]);
        assert_eq!(v.item(&edited.id).unwrap().data.password, "changed");
    }
    assert_eq!(server.live_titles(&a), ["Edited", "From B"]);
}
