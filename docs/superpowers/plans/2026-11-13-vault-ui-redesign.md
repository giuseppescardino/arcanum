# Vault UI Redesign Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Give the vault a read-only item view with explicit editing, a visible last-modified date, an optional expiry date, a three-column layout on wide windows, a settings screen in place of the popup menu, and a deliberate theme.

**Architecture:** The core gains one optional field (`expires_on`) on the encrypted item blob, passed through the FFI. In the app, `vault_screen.dart` is split into a shared list widget, a shared read-only item view and a settings screen; `VaultScreen` becomes a thin shell that picks a narrow (today's) or wide (three-column) layout from the window width. The editor is unchanged apart from the new expiry field and stays a pushed route.

**Tech Stack:** Rust (`serde`, existing `arcanum-vault` / `arcanum-ffi`), flutter_rust_bridge 2.13.0, Flutter/Dart (Material 3, `flutter_localizations`, `url_launcher` — all already dependencies). No new dependencies.

**Spec:** `docs/superpowers/specs/2026-11-13-vault-ui-redesign-design.md`

## Global Constraints

- No new Rust crates or Dart packages.
- Wide layout at window width **≥ 840** logical px; narrow below. Width only, never `Platform`.
- Wide columns: sidebar **232** px, list **380** px, item view takes the rest.
- Expiry is `YYYY-MM-DD`, no time, no time zone; JSON key `expires_on`; omitted when unset.
- "Expiring" window: today through **30 days** ahead, inclusive. "Expired": today is after the date. Compared on local calendar dates.
- Card expiry `MM/YY` means the last day of that month in `20YY`.
- Dates are shown with `MaterialLocalizations.of(context).formatCompactDate`.
- Nothing is stored without *Salva* (or the delete confirmation). The item view has no control that writes.
- UI copy: Italian in `app/lib/l10n/app_it.arb`, English in `app_en.arb`, keys and strings exactly as in the spec's Copy table. Regenerate with `flutter gen-l10n` (run in `app/`); generated files are committed.
- After changing `core/arcanum-ffi/src/api/`, regenerate bindings with `flutter_rust_bridge_codegen generate` (run in `app/`); generated files are committed.
- Checks before each commit: `cargo fmt --all --check`, `cargo clippy --workspace --all-targets --locked -- -D warnings`, `cargo test --workspace --locked` (in `core/`, when Rust changed); `flutter analyze` and `flutter test` (in `app/`).
- Widget tests state their window size explicitly through the helpers from Task 3 (`useNarrowWindow`, `useWideWindow`).

## Review Focus

1. **Item written by an older client** (JSON without `expires_on`): it must load, show no expiry, and round-trip unchanged. Rust test in Task 1.
2. **A hand-typed or synced bad date** (`2026-02-30`, `13/11/2026`, empty string): stored as no expiry, never a crash. Rust test in Task 1; Dart `expiryOf` test in Task 2.
3. **The open item disappears** (deleted in the editor, removed by a sync, vault locked): the narrow item screen pops, the wide column shows the empty hint, no exception. Tests in Task 4 and Task 6.
4. **The window is resized across 840 px with an item selected or open**: no exception; the list keeps its search text and filter. Test in Task 6.
5. **The browser extension updates a password on an item that has an expiry**: the expiry is still there afterwards. Test in Task 1.

---

### Task 1: `expires_on` in the core, the FFI and the Dart model

**Files:**
- Modify: `core/arcanum-vault/src/model.rs` (field + `normalize_expiry`), `core/arcanum-vault/src/lib.rs` (re-export)
- Modify: `core/arcanum-ffi/src/api/vault.rs` (`ItemFields.expires_on`, both `From` impls)
- Regenerate: `app/lib/src/rust/**`, `core/arcanum-ffi/src/frb_generated.rs`
- Create: `app/lib/app/item_fields.dart`
- Modify: `app/lib/browser/bridge_handler.dart` (the `update` case), `app/test/fakes.dart` (`_withGroup`, `login(...)` helper)
- Test: `core/arcanum-vault/src/model.rs` (unit tests), `core/arcanum-vault/tests/transfer.rs`, `app/test/browser_handler_test.dart`

**Interfaces:**
- Produces (Rust): `ItemData.expires_on: Option<String>`; `pub fn normalize_expiry(value: &str) -> Option<String>` exported from `arcanum_vault`; `ItemFields.expires_on: Option<String>`.
- Produces (Dart): `ItemFields.expiresOn` (`String?`, generated); in `app/lib/app/item_fields.dart`:
  ```dart
  extension ItemFieldsCopy on ItemFields {
    /// Copy with the given fields replaced. `expiresOn` uses a sentinel-free
    /// pair: pass `clearExpiry: true` to remove it.
    ItemFields copyWith({String? password, String? group, bool? favorite,
        String? expiresOn, bool clearExpiry = false});
  }
  ```

- [ ] **Step 1: Write the failing Rust tests** in `model.rs` (`#[cfg(test)] mod tests`):

```rust
#[test]
fn normalize_expiry_accepts_only_real_dates() {
    assert_eq!(normalize_expiry("2026-11-13").as_deref(), Some("2026-11-13"));
    assert_eq!(normalize_expiry(" 2028-02-29 ").as_deref(), Some("2028-02-29"));
    for bad in ["", "2026-02-30", "2027-02-29", "2026-13-01", "2026-00-10",
                "13/11/2026", "2026-1-3", "2026-11-13T00:00:00Z"] {
        assert_eq!(normalize_expiry(bad), None, "{bad}");
    }
}

#[test]
fn old_items_read_without_expiry_and_roundtrip_unchanged() {
    let old = r#"{"kind":"login","title":"Bank","password":"x"}"#;
    let d: ItemData = serde_json::from_str(old).unwrap();
    assert_eq!(d.expires_on, None);
    assert!(!serde_json::to_string(&d).unwrap().contains("expires_on"));
}

#[test]
fn expiry_is_serialized_when_set() {
    let mut d = ItemData::default();
    d.expires_on = Some("2027-01-31".into());
    let back: ItemData = serde_json::from_str(&serde_json::to_string(&d).unwrap()).unwrap();
    assert_eq!(back.expires_on.as_deref(), Some("2027-01-31"));
}
```

In `core/arcanum-vault/tests/transfer.rs` add `backup_keeps_expiry`: export one item with `expires_on = Some("2027-01-31")` via `export_backup`, `import` it with the same password, assert the imported item's `expires_on` is `Some("2027-01-31")`.

- [ ] **Step 2: Run** `cargo test -p arcanum-vault` in `core/`. Expected: FAIL to compile (`expires_on`, `normalize_expiry` unknown).

- [ ] **Step 3: Implement.** Add to `ItemData`, after `card`:

```rust
/// Day the item expires, as `YYYY-MM-DD`; a calendar date with no time zone.
#[serde(default, skip_serializing_if = "Option::is_none")]
pub expires_on: Option<String>,
```

`normalize_expiry` trims, requires exactly `dddd-dd-dd`, month 1–12, day within the month (Gregorian leap rule), and returns the trimmed string. No date crate.

- [ ] **Step 4: Run** `cargo test -p arcanum-vault`. Expected: PASS.

- [ ] **Step 5: FFI.** Add `pub expires_on: Option<String>` to `ItemFields` (doc comment: `` /// Expiry day as `YYYY-MM-DD`. ``). `From<ItemFields> for ItemData` sets `d.expires_on = f.expires_on.as_deref().and_then(normalize_expiry)`; `From<&ItemData> for ItemFields` clones it. Run `flutter_rust_bridge_codegen generate` in `app/`. Expected: `app/lib/src/rust/api/vault.dart` has `final String? expiresOn;` in `ItemFields`.

- [ ] **Step 6: Write the failing Dart test** in `app/test/browser_handler_test.dart`, following the file's existing setup for an `update` request:

```dart
test('update keeps the expiry of the item', () async {
  // save a login for example.com with expiresOn: '2027-01-31', send
  // {'type':'update','id':<id>,'url':'https://example.com','password':'new'}
  final after = controller.items.single.fields;
  expect(after.password, 'new');
  expect(after.expiresOn, '2027-01-31');
});
```

Add an optional `String? expiresOn` parameter to the `login(...)` helper in `fakes.dart` for this.

- [ ] **Step 7: Run** `flutter test test/browser_handler_test.dart`. Expected: FAIL (`expiresOn` is null after update).

- [ ] **Step 8: Implement** `ItemFieldsCopy.copyWith` in `app/lib/app/item_fields.dart`; use it in `bridge_handler.dart`'s `update` case (`f.copyWith(password: ...)`) and in `FakeVaultHandle._withGroup` (`f.copyWith(group: group)`), replacing the hand-written constructors.

- [ ] **Step 9: Run** `flutter analyze && flutter test` in `app/`. Expected: no issues, all tests pass.

- [ ] **Step 10: Commit** — `feat(core): optional expiry date on items`.

---

### Task 2: Expiry logic, editor field and row badge

**Files:**
- Create: `app/lib/app/expiry.dart`
- Modify: `app/lib/ui/item_editor_screen.dart` (field + `_fields()`), `app/lib/ui/vault_screen.dart` (`_ItemTile`), `app/lib/l10n/app_it.arb`, `app_en.arb` (+ regenerate)
- Test: `app/test/expiry_test.dart` (new)

**Interfaces:**
- Consumes: `ItemFields.expiresOn` (Task 1).
- Produces, in `app/lib/app/expiry.dart`:
  ```dart
  const expirySoonWindow = Duration(days: 30);
  enum ExpiryState { none, ok, soon, expired }
  /// Last valid day (local midnight), from `expiresOn` or, for cards, from
  /// `card.expiry` (`MM/YY` → last day of that month in 20YY). Null when
  /// unset or unparseable.
  DateTime? expiryOf(ItemFields fields);
  ExpiryState expiryState(ItemFields fields, DateTime now);
  String formatExpiry(DateTime day);          // 'YYYY-MM-DD'
  ```
- Produces (l10n): `itemExpiresOn`, `itemExpiredOn`, `expiryExpiredTooltip`, `expirySoonTooltip`, `editorExpiryLabel`, `editorExpiryHelper`, `editorExpiryClear`.

- [ ] **Step 1: Write the failing tests** in `app/test/expiry_test.dart`:

```dart
final now = DateTime(2026, 11, 13, 15, 30);

test('states around the 30-day window', () {
  ExpiryState of(String? d) => expiryState(login('x', expiresOn: d), now);
  expect(of(null), ExpiryState.none);
  expect(of('2026-11-12'), ExpiryState.expired);
  expect(of('2026-11-13'), ExpiryState.soon);     // today still counts
  expect(of('2026-12-13'), ExpiryState.soon);     // day 30
  expect(of('2026-12-14'), ExpiryState.ok);       // day 31
});

test('bad dates mean no expiry', () {
  for (final bad in ['', '2026-02-30', '13/11/2026', 'soon']) {
    expect(expiryOf(login('x', expiresOn: bad)), isNull, reason: bad);
  }
});

test('a card expires on the last day of its month', () {
  ItemFields card(String e) => /* kind card, CardFields(expiry: e, ...) */;
  expect(expiryOf(card('02/28')), DateTime(2028, 2, 29));
  expect(expiryState(card('10/26'), now), ExpiryState.expired);
  expect(expiryState(card('11/26'), now), ExpiryState.soon);
  expect(expiryOf(card('')), isNull);
  expect(expiryOf(card('13/26')), isNull);
});

test('formatExpiry pads', () => expect(formatExpiry(DateTime(2027, 1, 5)), '2027-01-05'));

testWidgets('the editor sets and clears the expiry', (tester) async {
  // useNarrowWindow is not available yet: pump ItemEditorScreen directly in a
  // MaterialApp with the app's localization delegates, locale it.
  // Tap the 'Scadenza' field → date picker → OK; tap 'Salva'.
  // expect(controller.items.single.fields.expiresOn, isNotNull);
  // Reopen the editor for that item, tap the 'Rimuovi scadenza' tooltip, 'Salva'.
  // expect(controller.items.single.fields.expiresOn, isNull);
});

testWidgets('a card item has no expiry field', (tester) async {
  // new item, choose 'Carta': find.text('Scadenza') as a field label of the
  // new control findsNothing (the card's own MM/YY field is labelled differently).
});

testWidgets('rows flag expired and expiring items', (tester) async {
  // vault with 'Old' (2020-01-01), 'Soon' (today + 5 days), 'Fine' (none)
  expect(find.byTooltip('Scaduta'), findsOneWidget);
  expect(find.byTooltip('In scadenza'), findsOneWidget);
});
```

- [ ] **Step 2: Run** `flutter test test/expiry_test.dart`. Expected: FAIL to compile.

- [ ] **Step 3: Implement `expiry.dart`.** `expiryOf` parses strictly (regex `^\d{4}-\d{2}-\d{2}$`, then rejects when `DateTime(y, m, d)` does not give back the same y/m/d). Comparison uses `DateTime(now.year, now.month, now.day)`.

- [ ] **Step 4: Add the l10n keys** (spec Copy table) and run `flutter gen-l10n`.

- [ ] **Step 5: Editor field.** In `_ItemEditorScreenState` add `String? _expiresOn` (from `f?.expiresOn`), include it in `_fields()` as `expiresOn: _kind == VaultItemKind.card ? null : _expiresOn`. Below the notes field's predecessor (just above `MarkdownNotesField`) and only when `_kind != VaultItemKind.card`, add a read-only `TextFormField` labelled `editorExpiryLabel` with helper `editorExpiryHelper`, showing the date via `formatCompactDate`; `onTap` opens `showDatePicker(firstDate: DateTime(2000), lastDate: DateTime(2100, 12, 31), initialDate: current ?? today)`; when a date is set, a suffix `IconButton` with tooltip `editorExpiryClear` clears it.

- [ ] **Step 6: Row badge.** `_ItemTile` gets `required ExpiryState expiry`; next to the existing compromised icon it shows `Icons.event_busy` in `colorScheme.error` with tooltip `expiryExpiredTooltip` for `expired`, `Icons.schedule` in `colorScheme.tertiary` with tooltip `expirySoonTooltip` for `soon`. `_buildList` passes `expiryState(item.fields, DateTime.now())`.

- [ ] **Step 7: Run** `flutter analyze && flutter test`. Expected: PASS.

- [ ] **Step 8: Commit** — `feat(app): expiry date in the editor and on list rows`.

---

### Task 3: Split `vault_screen.dart` (no behaviour change)

**Files:**
- Create: `app/lib/ui/vault_list.dart` (sections, `VaultFilter`, `VaultList`, group header, item tile, empty state), `app/lib/ui/group_dialogs.dart` (rename / color / delete-confirm dialogs), `app/lib/ui/account_actions.dart` (change-password dialog, sign-out flow, forget-Secret-Key confirm)
- Modify: `app/lib/ui/vault_screen.dart` (keeps the scaffold, search field, chips, FAB, popup menu — now calling the moved code)
- Create: `app/test/window.dart`
- Modify: every test in `app/test/` that pumps `ArcanumApp` or `VaultScreen` (use the helper)

**Interfaces:**
- Produces, in `vault_list.dart`:
  ```dart
  sealed class VaultFilter { const VaultFilter(); }
  class AllItems extends VaultFilter { const AllItems(); }
  class FavoriteItems extends VaultFilter { const FavoriteItems(); }
  class ExpiringItems extends VaultFilter { const ExpiringItems(); }   // soon or expired
  class GroupItems extends VaultFilter {                                // '' = ungrouped
    const GroupItems(this.root); final String root; }
  // all four with value equality

  /// Items passing [filter] and [query]; the same matching rules as today.
  List<VaultItem> filterItems(VaultController c, VaultFilter filter, String query, DateTime now);

  class VaultList extends StatefulWidget {
    const VaultList({super.key, required this.controller, required this.filter,
        required this.query, required this.onOpen, this.selectedId,
        this.bottomPadding = 0});
    final void Function(VaultItem item) onOpen;   // row tap
    final String? selectedId;                      // highlighted row, wide only
  }
  ```
  `VaultList` owns the collapsed/expanded state of sections and the group header menu (rename, color, delete).
- Produces, in `account_actions.dart`: `Future<void> showChangePasswordDialog(BuildContext, VaultController)`, `Future<void> signOutOfDevice(BuildContext, VaultController)`, `Future<void> forgetSecretKeyOnDevice(BuildContext, VaultController)` — each including its confirmation dialog, as today.
- Produces, in `app/test/window.dart`:
  ```dart
  void useNarrowWindow(WidgetTester tester);  // 480 x 900 logical, dpr 1, reset on teardown
  void useWideWindow(WidgetTester tester);    // 1200 x 900 logical, dpr 1, reset on teardown
  ```

- [ ] **Step 1: Add `app/test/window.dart`** and switch the existing vault-facing tests to `useNarrowWindow(tester)` in place of their hand-set `physicalSize` (`app_flow_test`, `groups_test`, `favicons_test`, `quick_access_test`, `quick_unlock_test`, `breach_check_test`, `cards_wifi_test`, `tools_ui_test`, `about_test`, `autofill_test`, `expiry_test`). Where a test needs more height keep the height it had.

- [ ] **Step 2: Run** `flutter test`. Expected: PASS (the current screen has one layout, so the size change must not matter; fix any test that depended on width before moving code).

- [ ] **Step 3: Move the code.** `_groupFilter: String?` becomes `VaultFilter _filter = const AllItems()` in the screen state (`null` → `AllItems`, `''` → `GroupItems('')`). The "filtered group no longer exists" reset stays in the screen. `_copyFirstMatch` uses `filterItems`. No visible change, no string change.

- [ ] **Step 4: Add tests** to `app/test/groups_test.dart`:

```dart
test('filterItems applies filter and query together', () async {
  // items: 'A' in Work (favorite), 'B' in Work/Clients, 'C' ungrouped, expiresOn 2020-01-01
  final now = DateTime(2026, 11, 13);
  expect(titles(filterItems(c, const AllItems(), '', now)), ['A', 'B', 'C']);
  expect(titles(filterItems(c, const GroupItems('Work'), '', now)), ['A', 'B']);
  expect(titles(filterItems(c, const GroupItems(''), '', now)), ['C']);
  expect(titles(filterItems(c, const FavoriteItems(), '', now)), ['A']);
  expect(titles(filterItems(c, const ExpiringItems(), '', now)), ['C']);
  expect(titles(filterItems(c, const GroupItems('Work'), 'b', now)), ['B']);
});
```

- [ ] **Step 5: Run** `flutter analyze && flutter test`. Expected: PASS, with `vault_screen.dart` under 400 lines.

- [ ] **Step 6: Commit** — `refactor(app): split the vault screen into list, dialogs and account actions`.

---

### Task 4: Read-only item view

**Files:**
- Create: `app/lib/ui/item_detail.dart`
- Modify: `app/lib/ui/vault_screen.dart` (row tap pushes `ItemDetailScreen`), `app/lib/l10n/*.arb` (+ regenerate), `app/test/fakes.dart` (clock for `updatedAt`)
- Test: `app/test/item_detail_test.dart` (new); update `app/test/app_flow_test.dart`, `cards_wifi_test.dart`, `tools_ui_test.dart`, `favicons_test.dart`, `breach_check_test.dart` where they tap a row and expect the editor

**Interfaces:**
- Consumes: `expiryOf`, `expiryState` (Task 2); `MarkdownNotesView`, `TotpView`, `StrengthMeter`, `BreachStatus`, `showWifiQr`, `copySecret`, `maskCardNumber` (existing).
- Produces:
  ```dart
  /// Read-only view of the item with [itemId], following [controller]. Shows
  /// [empty] when the item is not in the vault.
  class ItemDetailView extends StatelessWidget {
    const ItemDetailView({super.key, required this.controller,
        required this.itemId, required this.onEdit, this.empty});
    final void Function(VaultItem item) onEdit;
    final Widget? empty;
  }

  /// Narrow layout: [ItemDetailView] in a scaffold; pops itself when the
  /// item is gone. Its app bar action 'Modifica' pushes [ItemEditorScreen].
  class ItemDetailScreen extends StatelessWidget {
    const ItemDetailScreen({super.key, required this.controller, required this.itemId});
  }
  ```
- Produces (l10n): `itemEdit`, `itemUpdatedOn`.
- `FakeVaultHandle({DateTime Function()? clock})`: `addItem`/`updateItem` stamp `updatedAt` with `clock().millisecondsSinceEpoch`; default clock returns `DateTime(2026, 11, 13, 9, 30)`.

- [ ] **Step 1: Write the failing tests** in `app/test/item_detail_test.dart` (all `useNarrowWindow`, locale `it`):

```dart
testWidgets('opening an item shows it read-only with its dates', (tester) async {
  // login 'Bank', user 'alice', password 'top-secret', expiresOn '2020-01-01'
  await tester.tap(find.text('Bank')); await tester.pumpAndSettle();
  expect(find.byType(TextFormField), findsNothing);
  expect(find.text('alice'), findsOneWidget);
  expect(find.text('top-secret'), findsNothing);              // masked
  expect(find.text('Modificata il 13/11/2026'), findsOneWidget);
  expect(find.text('Scaduta il 01/01/2020'), findsOneWidget);
  expect(find.text('Salva'), findsNothing);
});

testWidgets('reveal shows the password, copy copies it', (tester) async {
  // tap the reveal tooltip → find.text('top-secret') findsOneWidget
  // tap the copy tooltip next to it → clipboard text is 'top-secret'
});

testWidgets('Modifica opens the editor and a save comes back updated', (tester) async {
  await tester.tap(find.text('Modifica')); await tester.pumpAndSettle();
  // change the username field to 'bob', tap 'Salva'
  expect(find.byType(TextFormField), findsNothing);           // back on the view
  expect(find.text('bob'), findsOneWidget);
});

testWidgets('deleting from the editor closes the view too', (tester) async {
  // Modifica → delete → confirm
  expect(find.text('Il vault è vuoto', skipOffstage: true), findsNothing); // adjust to the real empty text finder used in app_flow_test
  expect(find.text('Modifica'), findsNothing);
});

testWidgets('a sync removing the open item closes the view', (tester) async {
  // with the view open: await controller.delete(id); pumpAndSettle
  expect(find.text('Modifica'), findsNothing);
  expect(tester.takeException(), isNull);
});

testWidgets('card and wifi items show their details', (tester) async {
  // card: holder visible, number shown masked (maskCardNumber), CVV not visible
  // wifi: SSID visible, QR button present
});
```

Update `app_flow_test.dart`: in `'locking closes an open editor'` the tap on `'Bank'` now lands on the item view — the assertions on `'Modifica'` hold as written (it is now the view's action); add a second test that opens the editor from the view, locks, and expects `'Sblocca il vault'`. Update the other listed tests to reach the editor through `find.text('Modifica')`.

- [ ] **Step 2: Run** `flutter test test/item_detail_test.dart`. Expected: FAIL to compile.

- [ ] **Step 3: Implement `item_detail.dart`** per the spec's "Read-only item view" section. Layout: a `ListView` capped at 640 px; header (leading icon as in the row, title, group as a small label); one row per field with a caption, the value, and trailing reveal/copy buttons; secrets masked with `••••••••` until revealed, reveal state local to the row and reset when `itemId` changes. Websites open with `launchUrl` (external application). Footer shows the expiry line (`itemExpiredOn` in `colorScheme.error` when expired, `itemExpiresOn` otherwise, tertiary color when `soon`) and `itemUpdatedOn`. `ItemDetailScreen` wraps it in a `ListenableBuilder` on the controller and schedules `Navigator.pop` when the item is missing.

- [ ] **Step 4: Wire it.** In `vault_screen.dart`, row tap pushes `ItemDetailScreen`; the FAB still pushes `ItemEditorScreen` for a new item.

- [ ] **Step 5: Run** `flutter analyze && flutter test`. Expected: PASS.

- [ ] **Step 6: Commit** — `feat(app): read-only item view with explicit edit`.

---

### Task 5: Settings screen replaces the popup menu

**Files:**
- Create: `app/lib/ui/settings_screen.dart`
- Modify: `app/lib/ui/vault_screen.dart` (remove `_MenuAction`, the `PopupMenuButton` and `_MenuEntry`; add a gear `IconButton` with tooltip `settingsTitle`), `app/lib/l10n/*.arb` (+ regenerate)
- Test: `app/test/settings_test.dart` (new); update tests that open the popup menu (`about_test`, `breach_check_test`, `browser_pairing_test`, `language_test`, `quick_unlock_test`, `transfer_test`, `sync_controller_test` if it drives the UI)

**Interfaces:**
- Consumes: `showChangePasswordDialog`, `signOutOfDevice`, `forgetSecretKeyOnDevice` (Task 3); existing `SyncScreen`, `BrowserPairingScreen`, `BreachCheckScreen`, `showLanguageDialog`, `importFromFile`, `exportToFile`, `showArcanumAbout`, `AndroidAutofill`, `BridgeScope`, `BreachScope`, `FaviconScope`, `fileDialogs`.
- Produces: `class SettingsScreen extends StatelessWidget { const SettingsScreen({super.key, required this.controller}); }`.
- Produces (l10n): `settingsTitle`, `settingsSecurity`, `settingsData`, `settingsAppearance`, `settingsDangerZone`, `settingsQuickUnlock`, `settingsSiteIcons`.

- [ ] **Step 1: Write the failing tests** in `app/test/settings_test.dart` (`useNarrowWindow`):

```dart
testWidgets('settings are grouped and the danger zone comes last', (tester) async {
  await tester.tap(find.byTooltip('Impostazioni')); await tester.pumpAndSettle();
  for (final s in ['Sicurezza', 'Sincronizzazione', 'Dati', 'Aspetto', 'Zona pericolosa']) {
    await tester.scrollUntilVisible(find.text(s), 200);
    expect(find.text(s), findsOneWidget);
  }
  final danger = tester.getTopLeft(find.text('Zona pericolosa')).dy;
  expect(tester.getTopLeft(find.text('Esci da questo dispositivo')).dy, greaterThan(danger));
});

testWidgets('entries follow availability', (tester) async {
  // quick unlock unavailable, no BridgeScope, fileDialogs.canSave false:
  // 'Browser collegati' and 'Esporta…' and the quick-unlock switch are absent.
});

testWidgets('the site-icons switch toggles the preference', (tester) async {
  // with a FaviconScope: tap the switch → icons.enabled flips.
});

testWidgets('sign out still asks for confirmation', (tester) async {
  // tap 'Esci da questo dispositivo' → the existing confirmation dialog title is shown;
  // 'Annulla' leaves the vault unlocked.
});

testWidgets('the vault screen has no popup menu', (tester) async {
  expect(find.descendant(of: find.byType(AppBar), matching: find.byWidgetPredicate((w) => w is PopupMenuButton)), findsNothing);
});
```

- [ ] **Step 2: Run** `flutter test test/settings_test.dart`. Expected: FAIL to compile.

- [ ] **Step 3: Implement `SettingsScreen`** — a scaffold titled `settingsTitle`, a `ListView` capped at 640 px, section headers as small labels, entries as `ListTile`s (switches as `SwitchListTile`), sections and visibility conditions exactly as the spec's Settings table and today's menu. The danger zone follows a `Divider`, its entries in `colorScheme.error`. Language shows the current language as the tile's subtitle; sync shows the server host (`controller.syncInfo`) when linked.

- [ ] **Step 4: Replace the popup** in `vault_screen.dart` and update the tests listed above to go through the settings screen.

- [ ] **Step 5: Run** `flutter analyze && flutter test`. Expected: PASS.

- [ ] **Step 6: Commit** — `feat(app): settings screen in place of the vault menu`.

---

### Task 6: Wide three-column shell

**Files:**
- Create: `app/lib/ui/vault_sidebar.dart`
- Modify: `app/lib/ui/vault_screen.dart`, `app/lib/l10n/*.arb` (+ regenerate)
- Test: `app/test/wide_layout_test.dart` (new)

**Interfaces:**
- Consumes: `VaultList`, `VaultFilter`, `filterItems` (Task 3); `ItemDetailView`, `ItemDetailScreen` (Task 4); `SettingsScreen` (Task 5).
- Produces:
  ```dart
  const wideLayoutMinWidth = 840.0;   // in vault_screen.dart

  class VaultSidebar extends StatelessWidget {
    const VaultSidebar({super.key, required this.controller, required this.filter,
        required this.onFilter, required this.onSettings, this.onBreachCheck});
    final ValueChanged<VaultFilter> onFilter;
    final VoidCallback? onBreachCheck;   // null hides the entry
  }
  ```
- Produces (l10n): `vaultFavorites`, `vaultExpiring`, `vaultGroups`, `vaultSelectItem`.

- [ ] **Step 1: Write the failing tests** in `app/test/wide_layout_test.dart`:

```dart
testWidgets('wide: sidebar, list and item view side by side', (tester) async {
  useWideWindow(tester);
  // vault: 'Bank' (Work), 'Mail' (Personale, favorite), 'Old' (no group, expiresOn 2020-01-01)
  expect(find.text('Preferiti'), findsOneWidget);
  expect(find.text('Gruppi'), findsOneWidget);
  expect(find.text('Seleziona una voce per vederne i dettagli.'), findsOneWidget);
  expect(find.byType(FloatingActionButton), findsNothing);
  expect(find.byType(ChoiceChip), findsNothing);

  await tester.tap(find.text('Bank')); await tester.pumpAndSettle();
  expect(find.text('Modifica'), findsOneWidget);
  expect(find.text('Mail'), findsOneWidget);                  // the list is still there
});

testWidgets('wide: sidebar filters', (tester) async {
  useWideWindow(tester);
  await tester.tap(find.text('Preferiti')); await tester.pumpAndSettle();
  expect(find.text('Mail'), findsOneWidget); expect(find.text('Bank'), findsNothing);
  await tester.tap(find.text('Scadenze')); await tester.pumpAndSettle();
  expect(find.text('Old'), findsOneWidget); expect(find.text('Mail'), findsNothing);
  await tester.tap(find.widgetWithText(ListTile, 'Work')); await tester.pumpAndSettle();
  expect(find.text('Bank'), findsOneWidget);
});

testWidgets('wide: Scadenze is hidden when nothing expires', (tester) async {
  useWideWindow(tester);   // vault without expiry dates
  expect(find.text('Scadenze'), findsNothing);
});

testWidgets('wide: the selected item disappearing clears the item view', (tester) async {
  useWideWindow(tester);
  // select 'Bank', then await controller.delete(id)
  expect(find.text('Seleziona una voce per vederne i dettagli.'), findsOneWidget);
  expect(tester.takeException(), isNull);
});

testWidgets('resizing across the breakpoint keeps search and filter', (tester) async {
  useWideWindow(tester);
  // type 'ban' in the search field, select 'Bank'
  useNarrowWindow(tester); await tester.pumpAndSettle();
  expect(find.text('ban'), findsOneWidget);                   // search text kept
  expect(find.text('Bank'), findsOneWidget); expect(find.text('Mail'), findsNothing);
  expect(tester.takeException(), isNull);
  useWideWindow(tester); await tester.pumpAndSettle();
  expect(tester.takeException(), isNull);
});

testWidgets('narrow: chips, FAB and a Scadenze chip only when needed', (tester) async {
  useNarrowWindow(tester);
  expect(find.byType(FloatingActionButton), findsOneWidget);
  expect(find.widgetWithText(ChoiceChip, 'Scadenze'), findsOneWidget);
  expect(find.text('Preferiti'), findsNothing);
});

testWidgets('wide: Nuovo and Modifica open the editor as a route; lock closes it', (tester) async {
  useWideWindow(tester);
  await tester.tap(find.text('Nuovo')); await tester.pumpAndSettle();
  expect(find.text('Salva'), findsOneWidget);
  controller.lock(); await tester.pumpAndSettle();
  expect(find.text('Sblocca il vault'), findsOneWidget);
});
```

- [ ] **Step 2: Run** `flutter test test/wide_layout_test.dart`. Expected: FAIL.

- [ ] **Step 3: Implement.** `_VaultScreenState` owns search controller, `_filter` and `String? _selectedId`, and builds from a `LayoutBuilder`: narrow below `wideLayoutMinWidth` (today's scaffold, plus the *Scadenze* chip when `filterItems(..., const ExpiringItems(), '', now)` is non-empty), wide otherwise: a scaffold whose app bar holds the title, sync button, a `TextButton.icon` *Blocca* and a `FilledButton.icon` *Nuovo*; body `Row[SizedBox(232, VaultSidebar), VerticalDivider(width: 1), SizedBox(380, Column[search field, banners, VaultList(selectedId)]), VerticalDivider(width: 1), Expanded(ItemDetailView(empty: hint))]`. Row tap: narrow pushes `ItemDetailScreen`, wide sets `_selectedId`. A selected id whose item is gone is cleared. A `FavoriteItems` filter left over when the window turns narrow falls back to `AllItems`. The session-expired and breach-reminder banners stay above the list in both layouts.

- [ ] **Step 4: Sidebar.** `ListTile` rows with `selected:` for the active filter and a trailing count; group rows show the folder icon in the group color; *Senza gruppo* appears only when ungrouped items exist; the bottom block (after a `Spacer`) holds *Password compromesse* (`breachTitle`) and *Impostazioni*.

- [ ] **Step 5: Run** `flutter analyze && flutter test`. Expected: PASS.

- [ ] **Step 6: Commit** — `feat(app): three-column vault layout on wide windows`.

---

### Task 7: Theme

**Files:**
- Modify: `app/lib/ui/theme.dart`, `app/lib/ui/vault_list.dart` (leading avatar shape, selected row), `app/lib/ui/site_icon.dart` (rounded square)
- Test: `app/test/theme_test.dart` (new)

**Interfaces:**
- Produces: `ThemeData appTheme(Brightness brightness, {TargetPlatform? platform})` — `platform` defaults to `defaultTargetPlatform`; existing call sites compile unchanged.

- [ ] **Step 1: Write the failing tests** in `app/test/theme_test.dart`:

```dart
test('desktop is compact, mobile is standard', () {
  for (final p in [TargetPlatform.windows, TargetPlatform.macOS, TargetPlatform.linux]) {
    expect(appTheme(Brightness.light, platform: p).visualDensity, VisualDensity.compact);
  }
  for (final p in [TargetPlatform.android, TargetPlatform.iOS]) {
    expect(appTheme(Brightness.light, platform: p).visualDensity, VisualDensity.standard);
  }
});

test('flat app bar and 8 px shapes in both brightnesses', () {
  for (final b in Brightness.values) {
    final t = appTheme(b, platform: TargetPlatform.windows);
    expect(t.appBarTheme.scrolledUnderElevation, 0);
    expect(t.appBarTheme.backgroundColor, t.colorScheme.surface);
    final input = t.inputDecorationTheme.border as OutlineInputBorder;
    expect(input.borderRadius, BorderRadius.circular(8));
    expect(t.inputDecorationTheme.isDense, isTrue);
    expect((t.dialogTheme.shape as RoundedRectangleBorder).borderRadius, BorderRadius.circular(12));
    expect(t.listTileTheme.selectedTileColor, t.colorScheme.secondaryContainer);
    expect(t.dividerTheme.color, t.colorScheme.outlineVariant);
  }
});
```

- [ ] **Step 2: Run** `flutter test test/theme_test.dart`. Expected: FAIL.

- [ ] **Step 3: Implement** per the spec's Theme section: seed `0xFF3F51B5` kept; `appBarTheme` (surface background, `elevation: 0`, `scrolledUnderElevation: 0`, `surfaceTintColor: Colors.transparent`); 8 px `RoundedRectangleBorder` for filled/outlined/text buttons, chips, cards and `listTileTheme.shape`; dialogs 12 px; `dividerTheme` 1 px `outlineVariant`. Leading avatars in the list and `SiteIcon` become 8 px rounded squares of the same size as today.

- [ ] **Step 4: Run** `flutter analyze && flutter test`. Expected: PASS.

- [ ] **Step 5: Look at it.** Run the Windows app (`flutter run -d windows` in `app/`) with a vault that has groups, a favorite, an expired item and a compromised one; check light and dark, the window at 700 px and at 1300 px wide, the item view, the editor, the settings screen. Fix what reads wrong against the spec; report what was seen.

- [ ] **Step 6: Commit** — `feat(app): compact desktop theme and consistent shapes`.

---

### Task 8: Documentation

**Files:**
- Modify: `README.md` and `app/README.md` (feature list: read-only item view, expiry dates, settings screen; note on the regenerate commands if not already there), `docs/SECURITY.md` (one paragraph: the expiry date is inside the encrypted item blob like every other field; older clients drop it when they rewrite an item), the spec's `Status:` line (→ implemented, with date)

- [ ] **Step 1: Update the documents.**
- [ ] **Step 2: Run** the full check list from Global Constraints once more. Expected: all green.
- [ ] **Step 3: Commit** — `docs: vault UI redesign and expiry dates`.
