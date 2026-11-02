# arcanum-server

Zero-knowledge sync server. It stores only data the clients have already encrypted:
- OPAQUE registration records;
- wrapped keys;
- item ciphertexts.

The cryptographic design is described in [docs/SECURITY.md](../docs/SECURITY.md).

## Production (Docker)

```bash
cd deploy
cp .env.example .env   # set ARCANUM_DOMAIN and POSTGRES_PASSWORD
docker compose up -d --build
```

Caddy terminates TLS with a Let's Encrypt certificate and forwards requests to `arcanum-server` on the internal network. Database migrations run automatically at startup.

## Backup and restore

All server state lives in the database: accounts, encrypted keys, items, sessions and the `server_config` table holding the server's OPAQUE secret (if it is lost, no existing account can sign in again). The `backup` service of both compose files (`deploy/docker-compose.yml` and `deploy/docker-compose.dev.yml`) takes an [age](https://age-encryption.org)-encrypted dump at startup and then once a day, and keeps the last 14 days.

Files are named `arcanum-YYYYMMDD-HHMMSS.dump.age` (UTC). They are first written as a temporary file and renamed only once the dump is complete, so the folder never contains half-written backups. Rotation runs only after a successful backup. The `*-pre-restore.dump.age` backups created by a restore are never deleted automatically.

### Setup

1. Generate the age key pair (from the `deploy` folder; for the development compose add `-f docker-compose.dev.yml`):

   ```bash
   docker compose run --rm -T backup age-keygen > arcanum-backup-key.txt
   chmod 600 arcanum-backup-key.txt
   ```

   The file contains the private key, which is needed **only to restore**: move it away from the server and from the backup folder (a password manager, a USB stick, printed together with the Emergency Kit). Without it the backups are unreadable.

2. Put the public key (the `public key: age1…` line of the file) in `deploy/.env`:

   ```
   BACKUP_AGE_RECIPIENT=age1...
   ```

3. Optional: choose the folder with `BACKUP_DIR` (default `./backups`, i.e. `deploy/backups`, ignored by git). It must be an absolute path, because Compose does not expand `~`. To keep a copy off the machine, point it at a synced folder: the dumps are encrypted and the container needs no cloud credentials, since the service's own client uploads them.

   ```
   BACKUP_DIR=/Users/<user>/Library/CloudStorage/Dropbox/Arcanum-backup
   ```

   The same works for Google Drive, OneDrive, iCloud Drive (`~/Library/Mobile Documents/com~apple~CloudDocs/…`) or a mounted NAS. If the folder does not exist or is not writable, the container exits immediately with an error in the log. Files deleted by rotation end up in the cloud service's trash.

4. Start or update the service:

   ```bash
   docker compose up -d --build backup
   docker compose logs backup   # should show "backup created: ..."
   ```

### Manual backup and listing

```bash
docker compose run --rm backup once   # back up now (with rotation)
docker compose run --rm backup list   # available backups, newest first
```

### Restore

The `deploy/backup/restore.sh` script runs on the host and uses the `backup` service to decrypt and restore (the host only needs Docker):

```bash
deploy/backup/restore.sh --list
deploy/backup/restore.sh --key arcanum-backup-key.txt latest
deploy/backup/restore.sh --key arcanum-backup-key.txt 20261103            # date prefix
deploy/backup/restore.sh --key arcanum-backup-key.txt ~/Downloads/arcanum-20261103-020000.dump.age
```

By default it uses `deploy/docker-compose.yml`; for the development compose add `-f deploy/docker-compose.dev.yml`. When several backups match the same prefix it picks the newest.

What it does, in order:

1. **Verify:** decrypts the backup and restores it into a temporary database (`arcanum_restore_check`), shows how many accounts, items and devices it contains and checks that the OPAQUE secret is there. If anything is wrong (wrong key, corrupted file) it stops without touching the database.
2. **Confirm** (skipped with `--yes`).
3. **Safety backup** of the current state (`arcanum-…-pre-restore.dump.age`): to undo the restore, run the script again with that file.
4. **Restore:** stops `server` and runs `pg_restore` in a single transaction: either everything applies or the database stays as it was.
5. **Cleanup:** deletes all sessions and pending logins (sessions revoked after the backup do not become valid again) and the `sync_epoch` key, which the server regenerates at startup.
6. Restarts `server` and waits for `/health` to answer `ok`.

The devices show "Riconnetti" (Reconnect). After signing in, the new `sync_epoch` makes the device resync from scratch: it downloads everything again and compares revisions item by item. The highest revision wins, items the server lost are uploaded again and deletions stay deleted. "(conflitto)" copies appear only if two devices changed the same item in different ways. Changes made after the backup are therefore not lost, as long as at least one device has them. If the server is restored by hand without the script, it still notices, but only when a device's sync cursor is ahead of the server (`cursor_ahead` error).

**Known limitations:**
- if after the restore a device edits an item that another device had already edited several times before the restore (i.e. with a higher revision), the version with the highest revision wins;
- if the **master password was changed after the backup**, the server accepts the old one again: reconnecting requires the old password, and it is a good idea to change it again afterwards;
- **accounts created after the backup** no longer exist on the server: on that device, disconnect sync and register the account again from the "Sincronizzazione" (Sync) screen.

## Local development

You need a reachable PostgreSQL. The easiest way is to start one with Docker:

```bash
docker run -d --name arcanum-pg -p 5433:5432 -e POSTGRES_HOST_AUTH_METHOD=trust postgres:18
createdb -h localhost -p 5433 -U postgres arcanum_dev
createdb -h localhost -p 5433 -U postgres arcanum_test
```

Alternatively, `deploy/docker-compose.dev.yml` starts PostgreSQL and `arcanum-server` already configured on `127.0.0.1:8081`.

```bash
DATABASE_URL=postgres://postgres@localhost:5433/arcanum_dev BIND_ADDR=127.0.0.1:8080 cargo run
```

In the app use `http://localhost:8080` as the server address. Plain HTTP is accepted only for `localhost`, `127.0.0.1`, `[::1]` and `10.0.2.2` (the Android emulator); every other host requires `https://`.

## Tests

```bash
cargo test
```

The end-to-end tests use `TEST_DATABASE_URL`, which defaults to `postgres://postgres@localhost:5433/arcanum_test`.

## API (`/v1`)

| Method | Path | Auth | Purpose |
|---|---|---|---|
| POST | `/register/start`, `/register/finish` | — | OPAQUE registration and vault upload |
| POST | `/prelogin` | — | KDF parameters and salt (fake but stable for non-existent emails) |
| POST | `/login/start`, `/login/finish` | — | OPAQUE login, returns the token |
| POST | `/logout` | Bearer | Revokes the current session |
| POST | `/password/start`, `/password/finish` | Bearer | Password change, signing out the other devices |
| GET | `/sync?since=N` | Bearer | Pulls the changes after the cursor |
| POST | `/sync` | Bearer | Push with optimistic concurrency control |
| GET | `/devices` | Bearer | Lists the sessions |
| DELETE | `/devices/{id}` | Bearer | Revokes a session |
