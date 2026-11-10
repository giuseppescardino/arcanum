#![allow(clippy::unwrap_used, clippy::expect_used)]

use arcanum_vault::transfer::{export_backup, export_csv, import, ImportFormat, TransferError};
use arcanum_vault::{ItemData, ItemKind};

fn login(title: &str) -> ItemData {
    let mut d = ItemData::default();
    d.title = title.into();
    d.username = "alice".into();
    d.password = "p,w \"quoted\"\nline2".into();
    d.urls = vec!["https://example.com".into(), "https://alt.example".into()];
    d.notes = "first\nsecond".into();
    d.totp = Some("JBSWY3DPEHPK3PXP".into());
    d.favorite = true;
    d.group = "Work/Clients".into();
    d
}

fn note(title: &str) -> ItemData {
    let mut d = ItemData::default();
    d.kind = ItemKind::SecureNote;
    d.title = title.into();
    d.notes = "wifi: 1234".into();
    d
}

#[test]
fn csv_round_trips_every_field() {
    let items = vec![login("GitHub"), note("Wi-Fi")];
    let csv = export_csv(&items);
    assert!(csv.starts_with("name,url,username,password,note,"));

    let back = import(csv.as_bytes(), None).unwrap();
    assert_eq!(back.format, ImportFormat::Csv);
    assert_eq!(back.skipped, 0);
    assert_eq!(back.items, items);
}

#[test]
fn chrome_csv_is_imported() {
    let csv = "\u{feff}name,url,username,password,note\r\n\
               Example,https://example.com/login,bob,hunter2,\r\n\
               ,https://www.nameless.org/a,carol,pw,hi\r\n\
               ,,,,\r\n";
    let got = import(csv.as_bytes(), None).unwrap();
    assert_eq!(got.format, ImportFormat::Csv);
    assert_eq!(got.items.len(), 2);
    assert_eq!(got.items[0].title, "Example");
    assert_eq!(got.items[0].username, "bob");
    assert_eq!(got.items[0].urls, ["https://example.com/login"]);
    // No name: the host stands in.
    assert_eq!(got.items[1].title, "nameless.org");
    assert_eq!(got.items[1].notes, "hi");
}

#[test]
fn backup_round_trips_and_needs_its_password() {
    let items = vec![login("GitHub"), note("Wi-Fi")];
    let file = export_backup(&items, b"backup password").unwrap();
    // Nothing readable in the file.
    let text = String::from_utf8(file.clone()).unwrap();
    assert!(!text.contains("GitHub") && !text.contains("alice"));

    assert!(matches!(
        import(&file, None),
        Err(TransferError::PasswordRequired)
    ));
    assert!(matches!(
        import(&file, Some(b"wrong")),
        Err(TransferError::WrongPassword)
    ));
    let back = import(&file, Some(b"backup password")).unwrap();
    assert_eq!(back.format, ImportFormat::ArcanumBackup);
    assert_eq!(back.items, items);
}

#[test]
fn backup_with_weak_kdf_is_refused() {
    let file = export_backup(&[login("X")], b"pw").unwrap();
    let mut json: serde_json::Value = serde_json::from_slice(&file).unwrap();
    json["kdf"]["memory_kib"] = 8.into();
    let tampered = serde_json::to_vec(&json).unwrap();
    assert!(matches!(
        import(&tampered, Some(b"pw")),
        Err(TransferError::UnsupportedFormat)
    ));
}

#[test]
fn bitwarden_json_maps_folders_and_skips_cards() {
    let json = r#"{
      "encrypted": false,
      "folders": [{"id": "f1", "name": "Social/Chat"}],
      "items": [
        {"type": 1, "name": "Slack", "notes": null, "favorite": true, "folderId": "f1",
         "login": {"username": "me", "password": "pw", "totp": "JBSW",
                   "uris": [{"uri": "https://slack.com"}, {"uri": "https://app.slack.com"}]}},
        {"type": 2, "name": "Recovery", "notes": "codes", "favorite": false, "folderId": null},
        {"type": 3, "name": "Visa", "card": {"number": "4111"}}
      ]
    }"#;
    let got = import(json.as_bytes(), None).unwrap();
    assert_eq!(got.format, ImportFormat::Bitwarden);
    assert_eq!(got.skipped, 1);
    assert_eq!(got.items.len(), 2);
    let slack = &got.items[0];
    assert_eq!(slack.group, "Social/Chat");
    assert!(slack.favorite);
    assert_eq!(slack.totp.as_deref(), Some("JBSW"));
    assert_eq!(slack.urls, ["https://slack.com", "https://app.slack.com"]);
    assert_eq!(got.items[1].kind, ItemKind::SecureNote);
    assert_eq!(got.items[1].notes, "codes");

    let encrypted = r#"{"encrypted": true, "items": []}"#;
    assert!(matches!(
        import(encrypted.as_bytes(), None),
        Err(TransferError::UnsupportedFormat)
    ));
}

#[test]
fn bitwarden_csv_is_imported() {
    let csv = "folder,favorite,type,name,notes,fields,reprompt,login_uri,login_username,login_password,login_totp\n\
               Work,1,login,Jira,,,0,\"https://jira.example,https://wiki.example\",me,pw,\n\
               ,,note,Memo,remember,,0,,,,\n";
    let got = import(csv.as_bytes(), None).unwrap();
    assert_eq!(got.format, ImportFormat::Bitwarden);
    assert_eq!(got.items.len(), 2);
    assert_eq!(got.items[0].group, "Work");
    assert!(got.items[0].favorite);
    assert_eq!(
        got.items[0].urls,
        ["https://jira.example", "https://wiki.example"]
    );
    assert_eq!(got.items[1].kind, ItemKind::SecureNote);
}

#[test]
fn onepassword_csv_is_imported() {
    let csv = "Title,Url,Username,Password,OTPAuth,Favorite,Archived,Tags,Notes\n\
               Mail,https://mail.example,me,pw,otpauth://totp/x?secret=JBSW,true,false,Personal;Mail,n\n";
    let got = import(csv.as_bytes(), None).unwrap();
    assert_eq!(got.format, ImportFormat::OnePassword);
    let mail = &got.items[0];
    assert_eq!(mail.title, "Mail");
    assert_eq!(mail.group, "Personal");
    assert!(mail.favorite);
    assert_eq!(mail.totp.as_deref(), Some("otpauth://totp/x?secret=JBSW"));
}

#[test]
fn keepass_csv_is_imported() {
    let old = "\"Account\",\"Login Name\",\"Password\",\"Web Site\",\"Comments\"\n\
               \"Bank\",\"me\",\"p\"\"w\",\"https://bank.example\",\"line1\nline2\"\n";
    let got = import(old.as_bytes(), None).unwrap();
    assert_eq!(got.format, ImportFormat::KeePass);
    assert_eq!(got.items[0].title, "Bank");
    assert_eq!(got.items[0].password, "p\"w");
    assert_eq!(got.items[0].notes, "line1\nline2");

    let xc = "\"Group\",\"Title\",\"Username\",\"Password\",\"URL\",\"Notes\",\"TOTP\"\n\
              \"Passwords\",\"Top\",\"a\",\"1\",\"\",\"\",\"\"\n\
              \"Passwords/Internet/Mail\",\"Deep\",\"b\",\"2\",\"https://m.example\",\"\",\"\"\n";
    let got = import(xc.as_bytes(), None).unwrap();
    assert_eq!(got.format, ImportFormat::KeePass);
    assert_eq!(got.items[0].group, "");
    assert_eq!(got.items[1].group, "Internet/Mail");
}

#[test]
fn keepass_xml_keeps_group_tree_and_ignores_history() {
    let xml = r#"<?xml version="1.0" encoding="utf-8" standalone="yes"?>
<KeePassFile>
  <Meta><Generator>KeePass</Generator></Meta>
  <Root>
    <Group>
      <UUID>r</UUID>
      <Name>Database</Name>
      <Entry>
        <String><Key>Title</Key><Value>Root entry</Value></String>
        <String><Key>Password</Key><Value ProtectInMemory="True">a&amp;b&lt;c</Value></String>
        <String><Key>UserName</Key><Value>me</Value></String>
        <String><Key>URL</Key><Value>https://root.example</Value></String>
        <String><Key>Notes</Key><Value /></String>
        <History>
          <Entry>
            <String><Key>Title</Key><Value>Old version</Value></String>
            <String><Key>Password</Key><Value>old</Value></String>
          </Entry>
        </History>
      </Entry>
      <Group>
        <Name>Internet</Name>
        <Group>
          <Name>Mail</Name>
          <Entry>
            <String><Key>Title</Key><Value>Inbox</Value></String>
            <String><Key>Password</Key><Value><![CDATA[p<w]]></Value></String>
            <String><Key>otp</Key><Value>otpauth://totp/x?secret=JBSW</Value></String>
          </Entry>
        </Group>
      </Group>
    </Group>
  </Root>
</KeePassFile>"#;
    let got = import(xml.as_bytes(), None).unwrap();
    assert_eq!(got.format, ImportFormat::KeePass);
    assert_eq!(got.items.len(), 2);
    assert_eq!(got.items[0].title, "Root entry");
    assert_eq!(got.items[0].password, "a&b<c");
    assert_eq!(got.items[0].group, "");
    assert_eq!(got.items[0].urls, ["https://root.example"]);
    assert_eq!(got.items[1].title, "Inbox");
    assert_eq!(got.items[1].password, "p<w");
    assert_eq!(got.items[1].group, "Internet/Mail");
    assert_eq!(
        got.items[1].totp.as_deref(),
        Some("otpauth://totp/x?secret=JBSW")
    );
}

#[test]
fn unrelated_files_are_refused() {
    for data in [
        &b"hello world"[..],
        b"a,b,c\n1,2,3\n",
        b"{\"some\": \"json\"}",
        b"<html></html>",
        &[0xff, 0xfe, 0x00][..],
        b"",
    ] {
        assert!(
            matches!(import(data, None), Err(TransferError::UnsupportedFormat)),
            "{data:?}"
        );
    }
}
