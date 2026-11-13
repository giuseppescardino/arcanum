# Vault UI redesign — design

Status: draft 2026-11-13, awaiting approval.

## Intent

The vault screen looks basic and unprofessional: it is the stock Material 3 theme on a phone layout stretched across a desktop window, with every setting and destructive action mixed in one popup menu. The redesign should make the app look deliberate and make the safe path the easy one: consulting an item must not risk changing it, risky state (compromised, expired) must be visible in the list, and destructive actions must sit apart from everyday ones.

## Goals

1. **Read-only item view.** Opening an item shows it read-only. Editing is an explicit step (*Modifica*) that opens the existing editor, where nothing is stored until *Salva*, as today.
2. **Last-modified date** shown on every item.
3. **Expiry date**: an optional date per item, flagged in the list and in the item view as it approaches and once it has passed.
4. **Three-column layout on wide windows** (sidebar, list, item view). Narrow windows and phones keep today's single column.
5. **Settings screen** replacing the popup menu, on both layouts, with destructive actions in their own section.
6. **A deliberate theme**: denser rows on desktop, flat bars, consistent shapes.

## Non-goals

- Password history, and a separate "password changed on" date (see Decisions → modified date).
- Notifications or reminders for expiry outside the app window.
- A visible auto-lock countdown. Every pointer event restarts the timer (`VaultController.touch`), so a countdown would sit at 5:00 whenever the user is looking at it.
- Expiry in CSV export/import and in the Bitwarden/KeePass importers. The encrypted backup carries it for free (it serializes `ItemData`).
- Changes to the browser extension, the server or the sync protocol.
- A bundled font. The platform font stays.

## Anti-goals

- Two UIs. Phone and desktop must share the list, the item view, the editor and the settings screen; only the outer shell differs.
- Any way to change an item without pressing *Salva*.
- Losing data on older clients' items: an item without `expires_on` must read exactly as before.

## Current state

- `app/lib/ui/vault_screen.dart` (1315 lines) holds the shell, the list, group dialogs, the item row, the change-password dialog and the popup menu.
- Tapping a row pushes `ItemEditorScreen` directly: there is no read-only view.
- `VaultItem.updatedAt` (Unix ms) already exists in the core and reaches Dart. It is the row timestamp used for sync conflict resolution, and it is never shown.
- `ItemData` (core) is one JSON blob per item, encrypted; fields carry `#[serde(default)]` so new fields read as absent on old data.
- Card items already have `card.expiry` (`MM/YY`).
- Lock button and sync button already exist in the app bar. Copying a secret already shows a snackbar with the 30 s clipboard clear.
- Locking pops every route to the first (`app.dart`), so any pushed screen closes on lock.

## Approaches

1. **One adaptive screen (chosen).** A single `VaultScreen` picks its shell from the window width; list, item view, editor and settings are shared widgets. Cost: `vault_screen.dart` must be split first. Benefit: one behaviour to maintain, a narrowed desktop window and a landscape tablet both do the right thing.
2. **Separate desktop and mobile screens chosen by platform.** Less refactoring up front, but two shells drift apart, and a narrow desktop window gets a three-column layout it has no room for.
3. **Polish only** (theme, denser rows, settings page; no columns, no item view). Cheapest, but the desktop stays a stretched phone layout and accidental edits stay possible.

The user picked the three-column layout for desktop, asked that mobile keep its current layout with a better menu, and asked for a read-only view with explicit save. Approach 1 delivers all three with shared widgets.

## Decisions

### Layout

- **Breakpoint: 840 logical px of window width** (the Material "expanded" class). Below: narrow shell. At or above: wide shell. It depends on width only, never on the platform.
- **Narrow shell** — unchanged structure: app bar (title, sync, lock, settings gear replacing the popup), search field, group chips, list, *Nuovo* FAB. Tapping a row pushes the item view full screen.
- **Wide shell** — three columns:
  - *Sidebar*, 232 px: **Tutti**, **Preferiti**, **Scadenze** (only when at least one item is expiring or expired, with a count), then **Gruppi** (root groups with their color and item count, plus *Senza gruppo*), then at the bottom **Password compromesse** (when the breach checker is available) and **Impostazioni**.
  - *List*, 380 px: search field on top, then the same list widget as narrow. The selected row is highlighted. Group chips are not shown (the sidebar replaces them).
  - *Item view*, the rest: the read-only view of the selected item, or the empty hint "Seleziona una voce per vederne i dettagli."
  - Top bar: sync button, **Blocca** as a labelled button, **Nuovo** as a filled button. No FAB.
- **Filters** become one value: all, favorites, expiring, or a root group (`''` for ungrouped). Narrow shows it as chips (existing chips, plus a *Scadenze* chip only when the count is above zero); wide shows it in the sidebar. *Preferiti* is sidebar-only.
- **The editor stays a pushed full-screen route on both layouts** (it is already capped at 640 px and centered). This keeps it untouched and removes the "unsaved changes while switching item" problem a docked editor would create. *(My call — the alternative, editing inside the right-hand column, was discussed and set aside for that reason.)*

### Read-only item view

- New `ItemDetailView` (body only) and `ItemDetailScreen` (scaffold wrapper for narrow).
- Shows, by kind: title, group, username, password (masked, with reveal and copy), strength meter and breach status, websites (tap opens the site, as a link), TOTP code (`TotpView`), Wi-Fi network (SSID, security, QR button), card (holder, number masked with reveal and copy, `MM/YY`, CVV and PIN masked with reveal and copy), notes rendered with `MarkdownNotesView`.
- Footer: expiry line (when set) and "Modificata il {date}".
- One action: **Modifica**, opening `ItemEditorScreen` for that item. Favorite and delete stay in the editor: both are changes, and changes go through *Salva* or the delete confirmation.
- The view follows the controller: after a save it shows the new values; if the item disappears (deleted, or removed by sync) the narrow screen pops and the wide column returns to the empty hint.
- **On phones too**, tapping a row opens the read-only view first. This adds one tap to reach the editor, which is the point: the copy buttons on the row and in the view cover everyday use. *(My call — the user asked for read-only against accidental edits without naming a platform.)*

### Modified date

- Shown from the existing `VaultItem.updatedAt`; no core change.
- It moves on **any** stored change to the item: an edit, a favorite toggle, a group rename that moves the item, and a sync that brings in a newer version (the winning version's timestamp). It is therefore "item last modified", not "password last changed". A password-specific date would need a new field maintained by the core and is left out.
- Format: the locale's short date (`MaterialLocalizations.formatShortDate`): `13/11/2026` in Italian.

### Expiry

- New optional field `expires_on` in `ItemData`, an ISO calendar date `YYYY-MM-DD` with no time and no time zone. Serialized only when set (`skip_serializing_if`), `#[serde(default)]` on read.
- The FFI drops anything that is not a real calendar date (`normalize_expiry`), the way it normalizes group paths.
- Offered in the editor for **login, secure note and Wi-Fi** items, as a date picker field with a clear button. **Card** items do not get the field: their expiry is `card.expiry`, read as the last day of that month in `20YY`.
- States, compared on the local calendar date: **expired** when today is after the date; **expiring** when the date is today or within the next **30 days**; otherwise fine.
- Shown as: an icon on the list row (error color when expired, tertiary when expiring) with a tooltip; a line in the item view ("Scaduta il …" / "Scade il …"); membership of the *Scadenze* filter.
- The browser extension's "update password" keeps the item's expiry unchanged. *(My call: the app cannot know whether the date belongs to the password.)*
- **Compatibility caveat**: an older app version that edits an item on another device rewrites the blob without `expires_on`, silently dropping it. The same limitation applied when Wi-Fi and card details were added; all devices should be updated together.

### Settings screen

`SettingsScreen`, reached from the gear icon (narrow) or the sidebar (wide), a pushed route with these sections, each entry keeping today's behaviour and visibility conditions:

| Section | Entries |
|---|---|
| Sicurezza | quick unlock (switch), change master password, compromised passwords, Android autofill |
| Sincronizzazione | sync, linked browsers |
| Dati | import, export |
| Aspetto | language, site icons (switch) |
| Informazioni | about |
| Zona pericolosa | remove Secret Key from this device, sign out — error color, separated by a divider |

### Theme

- Same indigo seed (`0xFF3F51B5`), Material 3.
- `VisualDensity.compact` on Windows, macOS and Linux; standard on Android and iOS.
- App bar: surface color, no elevation and no tint when scrolled under.
- Shapes: 8 px radius for inputs, buttons, list-row highlights, cards and dialogs' inner controls; dialogs 12 px.
- Inputs: outlined (as now), dense.
- List rows: selected row uses `secondaryContainer`; the leading avatar becomes a rounded square (8 px) rather than a circle.
- Dividers: 1 px `outlineVariant` between the three columns.

### Copy (Italian / English)

| Key | it | en |
|---|---|---|
| `itemEdit` | Modifica | Edit |
| `itemUpdatedOn(date)` | Modificata il {date} | Edited {date} |
| `itemExpiresOn(date)` | Scade il {date} | Expires {date} |
| `itemExpiredOn(date)` | Scaduta il {date} | Expired {date} |
| `expiryExpiredTooltip` | Scaduta | Expired |
| `expirySoonTooltip` | In scadenza | Expiring soon |
| `editorExpiryLabel` | Scadenza | Expiry date |
| `editorExpiryHelper` | Facoltativa. La voce viene segnalata quando la data si avvicina. | Optional. The item is flagged as the date approaches. |
| `editorExpiryClear` | Rimuovi scadenza | Clear expiry date |
| `vaultFavorites` | Preferiti | Favorites |
| `vaultExpiring` | Scadenze | Expiring |
| `vaultGroups` | Gruppi | Groups |
| `vaultSelectItem` | Seleziona una voce per vederne i dettagli. | Select an item to see its details. |
| `settingsTitle` | Impostazioni | Settings |
| `settingsSecurity` | Sicurezza | Security |
| `settingsData` | Dati | Data |
| `settingsAppearance` | Aspetto | Appearance |
| `settingsDangerZone` | Zona pericolosa | Danger zone |
| `settingsQuickUnlock(method)` | Sblocco con {method} | Unlock with {method} |
| `settingsSiteIcons` | Icone dei siti | Site icons |

Existing keys are reused wherever one already says the same thing (`syncTitle`, `browsersTitle`, `languageTitle`, `breachTitle`, `vaultImport`, `vaultExport`, `vaultAbout`, `vaultChangeMasterPassword`, `vaultEnableAutofill`, `vaultForgetSecretKey`, `vaultSignOut`, `vaultLock`, `vaultNew`).

## Left to the builder

- Exact paddings and text styles within the theme rules above.
- How the list widget is fed (parameters vs. a small view-model), as long as the shell owns search text, filter and selection.
- Icons for the new entries.
