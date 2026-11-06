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

## Signing

The project contains no signing identity. To install on an iOS/macOS device you need your own Apple team: the keychain access group used by quick unlock requires a valid one. Copy `signing.local.xcconfig.example` to `signing.local.xcconfig` (ignored by git) and set `DEVELOPMENT_TEAM` to your Team ID; both the iOS and macOS projects include it, so `flutter build` and `flutter run` sign with that team.

The first macOS build on a Mac that is not yet registered in the team must register it and create the profile, once:

```bash
xcodebuild -workspace macos/Runner.xcworkspace -scheme Runner -configuration Release \
  -derivedDataPath build/macos -allowProvisioningUpdates -allowProvisioningDeviceRegistration build
```
