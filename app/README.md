# Arcanum — app

The Arcanum Flutter app. The logic (cryptography, vault, sync) lives in the Rust core in `../core`, exposed to Dart with [flutter_rust_bridge](https://cjycode.com/flutter_rust_bridge/) through the `rust_builder/` plugin (cargokit compiles the `arcanum-ffi` crate during the build).

## Running

```bash
flutter pub get
flutter devices                    # list the available devices
flutter run -d <device-id>         # debug
flutter run --release -d <device-id>
```

## Rust bindings

After changing the API in `core/arcanum-ffi/src/api`, regenerate the bindings:

```bash
cargo install flutter_rust_bridge_codegen --version 2.13.0
flutter_rust_bridge_codegen generate
```

## Localization

Texts live in `lib/l10n/app_it.arb` (Italian) and `lib/l10n/app_en.arb` (English). After editing them, regenerate the localization classes (the generated files are committed):

```bash
flutter gen-l10n
```

## Interface

- **Item view:** opening an item shows it read-only; *Modifica* opens the editor and nothing is stored until *Salva*. Every item shows when it was last modified ("Modificata il …"), which changes on any stored change, sync included: it is not a "password changed" date.
- **Expiry dates:** logins, secure notes and Wi-Fi items can have an optional expiry date (cards use their own MM/YY). Items expiring within 30 days, or already expired, are flagged in the list and in the item view, and a *Scadenze* filter appears while something is expiring.
- **Layout:** windows at least 840 px wide show sidebar, list and item view side by side; narrower windows and phones keep the single column.
- **Settings:** a settings screen replaces the vault's popup menu. Removing the Secret Key and signing out are in a separate danger zone.

## Development server

Start PostgreSQL and `arcanum-server` locally on `127.0.0.1:8081` (from the repository root, with `deploy/.env` configured):

```bash
docker compose -f deploy/docker-compose.dev.yml up -d --build
```

Run the same command again to rebuild it after changes to `core/` or `server/`. To stop it (data stays in the `arcanum-dev_pgdata` volume):

```bash
docker compose -f deploy/docker-compose.dev.yml down
```

Plain HTTP is accepted only for `localhost`, `127.0.0.1`, `[::1]` and `10.0.2.2`. To reach the server from a physical device you need HTTPS, for example with Tailscale:

```bash
tailscale serve --bg --https=8443 http://127.0.0.1:8081   # https://<host>.<tailnet>.ts.net:8443
tailscale serve --https=8443 off                           # stop the tunnel
```

## Tests

```bash
flutter analyze
flutter test
# integration (sync_test.dart needs a development server)
flutter test integration_test -d <device-id>
```

## Linux

Build dependencies (Debian/Ubuntu names): `clang cmake ninja-build pkg-config libgtk-3-dev libsecret-1-dev libkeybinder-3.0-dev libx11-dev libxi-dev`.

```bash
flutter build linux --release      # bundle in build/linux/<arch>/release/bundle
```

At runtime the app needs GTK 3, libsecret and keybinder, plus a running Secret Service (GNOME Keyring, KWallet, KeePassXC...), where it keeps the Secret Key. From the extracted bundle (the CI artifact `Arcanum-linux-x64.tar.gz`), `./install.sh` installs it for the current user in `~/.local` with a menu entry; `./install.sh --uninstall` removes it. Quick unlock is not available on Linux, and the `Ctrl+Alt+P` global shortcut works only under X11. The tray icon is a StatusNotifierItem: KDE Plasma and most desktops show it, GNOME only with the AppIndicator extension (enabled on Ubuntu); without it, closing the window quits the app as before.

## Signing

The project contains no signing identity. To install on an iOS/macOS device you need your own Apple team: the keychain access group used by quick unlock requires a valid one. Copy `signing.local.xcconfig.example` to `signing.local.xcconfig` (ignored by git) and set `DEVELOPMENT_TEAM` to your Team ID; both the iOS and macOS projects include it, so `flutter build` and `flutter run` sign with that team.

The first macOS build on a Mac that is not yet registered in the team must register it and create the profile, once:

```bash
xcodebuild -workspace macos/Runner.xcworkspace -scheme Runner -configuration Release \
  -derivedDataPath build/macos -allowProvisioningUpdates -allowProvisioningDeviceRegistration build
```
