#![allow(clippy::unwrap_used, clippy::expect_used)]

use arcanum_vault::{ItemData, ItemKind, KdfParams, Vault, VaultError};

const PW: &[u8] = b"correct horse battery staple";

fn login(title: &str, password: &str) -> ItemData {
    let mut d = ItemData::default();
    d.title = title.into();
    d.username = "alice".into();
    d.password = password.into();
    d.urls = vec!["https://example.com".into()];
    d
}

#[test]
fn create_add_lock_unlock() {
    let mut v = Vault::open_in_memory().unwrap();
    assert!(!v.is_initialized().unwrap());
    let sk = v.create(PW, KdfParams::DEFAULT).unwrap();
    assert!(v.is_unlocked());

    let added = v.add_item(&login("GitHub", "gh-pass")).unwrap();
    assert_eq!(added.revision, 1);

    v.lock();
    assert!(matches!(v.items(), Err(VaultError::Locked)));

    v.unlock(PW, &sk).unwrap();
    let items = v.items().unwrap();
    assert_eq!(items.len(), 1);
    assert_eq!(items[0].data.password, "gh-pass");
}

#[test]
fn cannot_create_twice() {
    let mut v = Vault::open_in_memory().unwrap();
    v.create(PW, KdfParams::DEFAULT).unwrap();
    assert!(matches!(
        v.create(PW, KdfParams::DEFAULT),
        Err(VaultError::AlreadyInitialized)
    ));
}

#[test]
fn unlock_before_create_fails() {
    let mut v = Vault::open_in_memory().unwrap();
    let sk = arcanum_vault::SecretKey::generate().unwrap();
    assert!(matches!(v.unlock(PW, &sk), Err(VaultError::NotInitialized)));
}

#[test]
fn wrong_credentials() {
    let mut v = Vault::open_in_memory().unwrap();
    let sk = v.create(PW, KdfParams::DEFAULT).unwrap();
    v.lock();
    assert!(matches!(
        v.unlock(b"nope", &sk),
        Err(VaultError::WrongCredentials)
    ));
    let other = arcanum_vault::SecretKey::generate().unwrap();
    assert!(matches!(
        v.unlock(PW, &other),
        Err(VaultError::WrongCredentials)
    ));
    assert!(!v.is_unlocked());
}

#[test]
fn update_and_delete() {
    let mut v = Vault::open_in_memory().unwrap();
    v.create(PW, KdfParams::DEFAULT).unwrap();
    let a = v.add_item(&login("A", "1")).unwrap();
    let b = v.add_item(&login("b", "2")).unwrap();

    let updated = v.update_item(&a.id, &login("A", "1-new")).unwrap();
    assert_eq!(updated.revision, 2);
    assert_eq!(v.item(&a.id).unwrap().data.password, "1-new");

    v.delete_item(&b.id).unwrap();
    assert!(matches!(v.item(&b.id), Err(VaultError::NotFound)));
    assert!(matches!(
        v.update_item(&b.id, &login("b", "x")),
        Err(VaultError::NotFound)
    ));
    let titles: Vec<_> = v
        .items()
        .unwrap()
        .into_iter()
        .map(|i| i.data.title.clone())
        .collect();
    assert_eq!(titles, ["A"]);
}

#[test]
fn items_are_sorted_case_insensitively() {
    let mut v = Vault::open_in_memory().unwrap();
    v.create(PW, KdfParams::DEFAULT).unwrap();
    for t in ["zeta", "Alpha", "beta"] {
        v.add_item(&login(t, "x")).unwrap();
    }
    let titles: Vec<_> = v
        .items()
        .unwrap()
        .into_iter()
        .map(|i| i.data.title.clone())
        .collect();
    assert_eq!(titles, ["Alpha", "beta", "zeta"]);
}

#[test]
fn secure_note_round_trip() {
    let mut v = Vault::open_in_memory().unwrap();
    v.create(PW, KdfParams::DEFAULT).unwrap();
    let mut note = ItemData::default();
    note.kind = ItemKind::SecureNote;
    note.title = "Wi-Fi".into();
    note.notes = "line1\nline2".into();
    let id = v.add_item(&note).unwrap().id;
    assert_eq!(v.item(&id).unwrap().data, note);
}

#[test]
fn change_password() {
    let mut v = Vault::open_in_memory().unwrap();
    let sk = v.create(PW, KdfParams::DEFAULT).unwrap();
    v.add_item(&login("A", "1")).unwrap();

    assert!(matches!(
        v.change_password(b"wrong", b"new", &sk, KdfParams::DEFAULT),
        Err(VaultError::WrongCredentials)
    ));
    v.change_password(PW, b"new", &sk, KdfParams::DEFAULT)
        .unwrap();
    v.lock();
    assert!(matches!(
        v.unlock(PW, &sk),
        Err(VaultError::WrongCredentials)
    ));
    v.unlock(b"new", &sk).unwrap();
    assert_eq!(v.items().unwrap()[0].data.password, "1");
}

#[test]
fn persists_and_stores_no_plaintext() {
    let dir = tempfile::tempdir().unwrap();
    let path = dir.path().join("vault.db");
    let sk;
    {
        let mut v = Vault::open(&path).unwrap();
        sk = v.create(PW, KdfParams::DEFAULT).unwrap();
        v.add_item(&login("VerySecretBankTitle", "P4ssw0rd-Pl41nt3xt"))
            .unwrap();
    }
    {
        let mut v = Vault::open(&path).unwrap();
        assert!(v.is_initialized().unwrap());
        v.unlock(PW, &sk).unwrap();
        assert_eq!(v.items().unwrap()[0].data.title, "VerySecretBankTitle");
    }

    // Checkpointing happened on close; scan every file SQLite left behind.
    let mut bytes = Vec::new();
    for entry in std::fs::read_dir(dir.path()).unwrap() {
        bytes.extend(std::fs::read(entry.unwrap().path()).unwrap());
    }
    for needle in [
        &b"VerySecretBankTitle"[..],
        b"P4ssw0rd-Pl41nt3xt",
        b"alice",
        b"example.com",
        PW,
    ] {
        assert!(
            !bytes.windows(needle.len()).any(|w| w == needle),
            "plaintext {:?} found on disk",
            String::from_utf8_lossy(needle)
        );
    }
}

#[test]
fn groups_are_stored_and_renamed() {
    let mut v = Vault::open_in_memory().unwrap();
    v.create(PW, KdfParams::DEFAULT).unwrap();
    let mut work = login("Jira", "j");
    work.group = "Lavoro".into();
    let jira = v.add_item(&work).unwrap();
    work.title = "Slack".into();
    v.add_item(&work).unwrap();
    v.add_item(&login("Netflix", "n")).unwrap();

    assert_eq!(v.item(&jira.id).unwrap().data.group, "Lavoro");
    assert_eq!(v.rename_group("Lavoro", " Ufficio ").unwrap(), 2);
    let groups: Vec<_> = v
        .items()
        .unwrap()
        .into_iter()
        .map(|i| i.data.group.clone())
        .collect();
    assert_eq!(groups, ["Ufficio", "", "Ufficio"]);
    // Renamed items get a new revision so the change syncs.
    assert_eq!(v.item(&jira.id).unwrap().revision, 2);

    // Renaming to empty ungroups; unknown or empty source is a no-op.
    assert_eq!(v.rename_group("Ufficio", "").unwrap(), 2);
    assert_eq!(v.rename_group("Nessuno", "X").unwrap(), 0);
    assert_eq!(v.rename_group("", "X").unwrap(), 0);
    assert!(v.items().unwrap().iter().all(|i| i.data.group.is_empty()));
}

#[test]
fn items_without_group_field_still_load() {
    let old: ItemData = serde_json::from_str(r#"{"title":"Old","password":"p"}"#).unwrap();
    assert_eq!(old.group, "");
}
