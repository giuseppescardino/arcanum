# Arcanum

[![CI](https://github.com/giuseppescardino/arcanum/actions/workflows/ci.yml/badge.svg)](https://github.com/giuseppescardino/arcanum/actions/workflows/ci.yml)

A zero-knowledge, cross-platform, self-hosted password manager. The vault is encrypted on the device; the sync server stores only ciphertext and never sees the master password, the Secret Key or item contents.

- **Cryptography:** Argon2id + HKDF-SHA256 + XChaCha20-Poly1305, Secret Key and Emergency Kit, OPAQUE login.
- **App:** Flutter for Android, iOS, macOS and Windows, with password generator, TOTP, nested groups, site icons, import/export (CSV, encrypted backup, Bitwarden, 1Password, KeePass), biometric unlock, autofill on Android and a browser extension for Chrome, Opera and Safari that works with the desktop app.
- **Sync:** Rust + PostgreSQL server, deployed with Docker Compose and Caddy (automatic TLS), with daily age-encrypted backups.

The threat model and cryptographic design are described in [docs/SECURITY.md](docs/SECURITY.md).

> The app's user interface is currently in Italian.

## Layout

| Folder | Contents |
|---|---|
| `core/` | Rust workspace: `arcanum-crypto` (primitives and key hierarchy), `arcanum-proto` (API types), `arcanum-vault` (local vault), `arcanum-sync` (sync client), `arcanum-tools` (generator, strength, TOTP), `arcanum-bridge` (browser extension pairing and encryption), `arcanum-ffi` (Dart bindings via flutter_rust_bridge) |
| `server/` | `arcanum-server`, the sync server (axum + PostgreSQL) — see [server/README.md](server/README.md) |
| `app/` | Flutter app — see [app/README.md](app/README.md) |
| `extension/` | Browser extension for Chrome, Opera and Safari — see [extension/README.md](extension/README.md) |
| `deploy/` | Dockerfile, production and development Compose files, Caddy, backup and restore |
| `docs/` | Security documentation |

## Requirements

- Stable Rust (`rustup`), plus the mobile targets you need
- Flutter (version pinned in `.github/workflows/ci.yml`)
- Docker, for the server and the end-to-end tests
- Xcode + CocoaPods for iOS/macOS, Android SDK + JDK 17 for Android, Visual Studio for Windows

## Build and test

```bash
# Core
cd core && cargo test --workspace

# Server (needs PostgreSQL, see server/README.md)
cd server && cargo test

# App
cd app && flutter pub get && flutter test
cd app && flutter run

# Browser extension
cd extension && npm test
```

## Server

```bash
cd deploy
cp .env.example .env   # set ARCANUM_DOMAIN, POSTGRES_PASSWORD and BACKUP_AGE_RECIPIENT
docker compose up -d --build
docker compose exec server arcanum-server invite create --label "me"   # invite code for the first account
```

Configuration, backup and restore are covered in [server/README.md](server/README.md).

## CI

The GitHub Actions pipeline ([.github/workflows/ci.yml](.github/workflows/ci.yml)) lints and tests the core, the server and the app, builds the Docker image and produces unsigned builds for Android, iOS, macOS and Windows, downloadable as run artifacts.

The same jobs are also defined for Azure Pipelines in [azure-pipelines.yml](azure-pipelines.yml) (templates in `.azure/steps/`); there the pipeline runs only when started by hand.
