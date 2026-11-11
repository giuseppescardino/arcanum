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
fn renaming_a_group_moves_its_subgroups() {
    let mut v = Vault::open_in_memory().unwrap();
    v.create(PW, KdfParams::DEFAULT).unwrap();
    for (title, group) in [
        ("A", "Work"),
        ("B", "Work/Clients"),
        ("C", "Work / Clients /Acme"),
        ("D", "Workshop"),
        ("E", ""),
    ] {
        let mut d = login(title, "p");
        d.group = group.into();
        v.add_item(&d).unwrap();
    }
    let groups = |v: &Vault| -> Vec<String> {
        v.items()
            .unwrap()
            .into_iter()
            .map(|i| i.data.group.clone())
            .collect()
    };

    // Prefix match is per level: "Workshop" is not inside "Work".
    assert_eq!(v.rename_group("Work", "Office/Main").unwrap(), 3);
    assert_eq!(
        groups(&v),
        [
            "Office/Main",
            "Office/Main/Clients",
            "Office/Main/Clients/Acme",
            "Workshop",
            ""
        ]
    );

    // A subgroup can be moved on its own, and removed with its children.
    assert_eq!(v.rename_group("Office/Main/Clients", "Clients").unwrap(), 2);
    assert_eq!(v.rename_group("Clients", "").unwrap(), 2);
    assert_eq!(groups(&v), ["Office/Main", "", "", "Workshop", ""]);
}

#[test]
fn add_items_inserts_all_at_once() {
    let mut v = Vault::open_in_memory().unwrap();
    v.create(PW, KdfParams::DEFAULT).unwrap();
    let batch = [login("One", "1"), login("Two", "2")];
    assert_eq!(v.add_items(&batch).unwrap(), 2);
    let items = v.items().unwrap();
    assert_eq!(items.len(), 2);
    assert!(items.iter().all(|i| i.revision == 1));
    assert_ne!(items[0].id, items[1].id);

    v.lock();
    assert!(matches!(v.add_items(&batch), Err(VaultError::Locked)));
}

#[test]
fn items_without_group_field_still_load() {
    let old: ItemData = serde_json::from_str(r#"{"title":"Old","password":"p"}"#).unwrap();
    assert_eq!(old.group, "");
}

#[test]
fn reset_erases_account_and_allows_new_one() {
    let mut v = Vault::open_in_memory().unwrap();
    let old_sk = v.create(PW, KdfParams::DEFAULT).unwrap();
    v.add_item(&login("GitHub", "gh-pass")).unwrap();

    v.reset().unwrap();
    assert!(!v.is_unlocked());
    assert!(!v.is_initialized().unwrap());
    assert!(!v.is_linked().unwrap());
    assert!(v.unlock(PW, &old_sk).is_err());

    let sk = v.create(b"another password", KdfParams::DEFAULT).unwrap();
    assert!(v.items().unwrap().is_empty());
    v.lock();
    v.unlock(b"another password", &sk).unwrap();
}

#[test]
fn group_colors_are_records_that_follow_their_group() {
    let mut v = Vault::open_in_memory().unwrap();
    v.create(PW, KdfParams::DEFAULT).unwrap();
    let mut d = login("Jira", "j");
    d.group = "Work/Clients".into();
    v.add_item(&d).unwrap();
    let colors = |v: &Vault| -> Vec<(String, Option<u32>)> {
        let mut c: Vec<_> = v
            .items()
            .unwrap()
            .into_iter()
            .filter(|i| i.data.kind == ItemKind::Group)
            .map(|i| (i.data.group.clone(), i.data.color))
            .collect();
        c.sort();
        c
    };

    v.set_group_color(" Work ", Some(0xFF00_00FF)).unwrap();
    v.set_group_color("Work/Clients", Some(0xFFFF_0000))
        .unwrap();
    v.set_group_color("Work", Some(0xFF00_FF00)).unwrap();
    v.set_group_color("", Some(1)).unwrap();
    assert_eq!(
        colors(&v),
        [
            ("Work".into(), Some(0xFF00_FF00)),
            ("Work/Clients".into(), Some(0xFFFF_0000))
        ]
    );

    // Settings records move with the group but are not counted as items.
    assert_eq!(v.rename_group("Work", "Office").unwrap(), 1);
    assert_eq!(
        colors(&v),
        [
            ("Office".into(), Some(0xFF00_FF00)),
            ("Office/Clients".into(), Some(0xFFFF_0000))
        ]
    );

    // Merging into a colored group keeps the destination's color.
    v.set_group_color("Home", Some(7)).unwrap();
    v.rename_group("Office", "Home").unwrap();
    assert_eq!(
        colors(&v),
        [
            ("Home".into(), Some(7)),
            ("Home/Clients".into(), Some(0xFFFF_0000))
        ]
    );

    v.set_group_color("Home", None).unwrap();
    v.rename_group("Home", "").unwrap();
    assert!(colors(&v).is_empty());
}
