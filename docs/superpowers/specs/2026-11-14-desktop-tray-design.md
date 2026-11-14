# Desktop: keep Arcanum running in the tray

## Why

The browser bridge (`app/lib/browser/bridge_server.dart`) runs inside the
Flutter process and stops when the window closes, so the extension stops
working as soon as the user closes Arcanum. The goal is an extension that
keeps working with the window closed.

## Goals

- Closing the window hides it; the app, and the bridge with it, keep running
  with an icon in the system tray (menu bar on macOS).
- Tray menu: Open Arcanum, Lock, Quit.
- Optional launch at login, off by default; when on, the app starts hidden.
- One instance at a time: starting Arcanum again brings the running window
  forward instead of failing to bind the bridge ports.

## Non-goals

- A separate background service. Bridge, pairing, keys and the auto-lock
  stay exactly as they are.
- Changes to the pairing protocol. The 6-digit code is a fingerprint of the
  X25519 exchange compared by the user, not a secret that can be attacked
  offline, so replacing it with the master password would add risk (the
  password would be typed in the browser) without closing any gap.

## Anti-goals

- Hiding the window with no way to bring it back. Where no tray is
  available (e.g. GNOME without AppIndicator), closing the window quits as
  it does today.
- Keeping the vault open longer: the 5-minute auto-lock applies whether the
  window is visible or hidden.

## Approaches

| Approach | Trade-off |
|---|---|
| **Tray-resident app (chosen)** | Small change, no new process, no new IPC to secure. The vault and the decrypted items stay in the Flutter process, as today. |
| Background service in Rust owning vault and bridge | Isolates keys from the UI and could serve other local clients, but means moving the bridge and vault state out of Dart, a new app↔service channel, and per-OS installation. Not needed to keep the extension working. |
| Native messaging host | Chrome starts the host on demand, but it would still need the unlocked vault from the app, so it adds a process without removing the need for the app to run. Already rejected in `docs/SECURITY.md`. |

## Design

- `app/lib/app/background_mode.dart`: `BackgroundMode` (a `ChangeNotifier`,
  like `BreachChecker`) holds two preferences in `<appSupport>/background.json`:
  `keepRunning` (default on) and `launchAtLogin` (default off). It drives the
  tray, the window and the login item through small injectable interfaces so
  tests use fakes.
- Packages: `tray_manager` and `launch_at_startup` (same author as the
  `window_manager` and `hotkey_manager` already in use).
- `main(args)`: `--hidden` (passed by the login item) starts with the window
  hidden. The bridge's `showApp` callback, the tray's Open and the quick
  access shortcut share one show-window function.
- Settings: a new "Desktop" group after Appearance with the two switches,
  shown on desktop only.
- Native runners:
  - Windows: named mutex for single instance; the second instance finds the
    first window, shows it and exits. With `--hidden` the first frame does not
    show the window.
  - Linux: drop `G_APPLICATION_NON_UNIQUE`; a second launch re-activates the
    first, which presents its window. `--hidden` skips the first show.
  - macOS: don't terminate after the last window closes; clicking the Dock
    icon shows the window again.

## Left to the builder

- The macOS login item under the App Sandbox: if `launch_at_startup` cannot
  do it, register it with `SMAppService` through a method channel.
- Tray icon assets per platform (ICO on Windows, template PNG on macOS).
