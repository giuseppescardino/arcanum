#!/usr/bin/env bash
# Encrypted backups of the sync server database.
#
#   backup.sh [loop]   back up now, then every BACKUP_INTERVAL_HOURS (default)
#   backup.sh once     one manual backup (with rotation)
#   backup.sh list     list backups, newest first
#
# Commands used by restore.sh (on the host):
#   resolve <latest|file|prefix>, verify <file>, pre-restore,
#   restore <file>, wait-health
#
# Any other command is run as is (e.g. `age-keygen`).
#
# Connects to the DB through the standard PGHOST, PGUSER, PGDATABASE and
# PGPASSWORD variables. Files are `arcanum-YYYYMMDD-HHMMSS.dump.age` (UTC)
# in /backups, encrypted with age to BACKUP_AGE_RECIPIENT.

set -euo pipefail
umask 077

BACKUP_DIR=/backups
RETENTION_DAYS=${BACKUP_RETENTION_DAYS:-14}
INTERVAL_HOURS=${BACKUP_INTERVAL_HOURS:-24}
AGE_KEY_FILE=${AGE_KEY_FILE:-/run/restore/key.txt}
HEALTH_URL=${HEALTH_URL:-http://server:8080/health}
CHECK_DB=arcanum_restore_check
export PGOPTIONS='-c client_min_messages=warning'

log() { echo "$(date -u '+%Y-%m-%d %H:%M:%S') $*" >&2; }
die() { log "ERROR: $*"; exit 1; }

require_writable_dir() {
  local probe="$BACKUP_DIR/.write-test-$$"
  if ! touch "$probe" 2>/dev/null; then
    die "$BACKUP_DIR is not writable: check BACKUP_DIR in deploy/.env (absolute path, existing folder shared with Docker)"
  fi
  rm -f "$probe"
}

require_key() {
  [ -r "$AGE_KEY_FILE" ] || die "age private key not found at $AGE_KEY_FILE"
}

# Backup recipient: the configured one or, during a restore, the public key
# derived from the mounted private key.
recipient() {
  if [ -n "${BACKUP_AGE_RECIPIENT:-}" ]; then
    echo "$BACKUP_AGE_RECIPIENT"
  elif [ -r "$AGE_KEY_FILE" ]; then
    age-keygen -y "$AGE_KEY_FILE"
  else
    die "BACKUP_AGE_RECIPIENT is not set in deploy/.env (generate the keys with: docker compose run --rm backup age-keygen)"
  fi
}

# Writes a backup and prints its path. $1 = optional suffix.
backup_now() {
  local suffix=${1:+-$1} rcpt name tmp
  rcpt=$(recipient) || return 1
  name="arcanum-$(date -u +%Y%m%d-%H%M%S)$suffix.dump.age"
  tmp="$BACKUP_DIR/.$name.tmp"
  # No partial files: write to .tmp and rename only once the dump is complete.
  if ! pg_dump -Fc | age -r "$rcpt" -o "$tmp"; then
    rm -f "$tmp"
    die "backup failed"
  fi
  mv "$tmp" "$BACKUP_DIR/$name" || die "cannot rename $tmp"
  log "backup created: $name ($(du -h "$BACKUP_DIR/$name" | cut -f1))"
  echo "$BACKUP_DIR/$name"
}

# Pre-restore backups never expire: delete them by hand.
rotate() {
  find "$BACKUP_DIR" -maxdepth 1 -type f -name 'arcanum-*.dump.age' \
    ! -name '*-pre-restore.dump.age' -mtime +$((RETENTION_DAYS - 1)) \
    -print -delete | while read -r f; do log "rotation: deleted $(basename "$f")"; done
}

backup_and_rotate() {
  backup_now >/dev/null && rotate
}

cmd_loop() {
  require_writable_dir
  recipient >/dev/null
  log "backup every ${INTERVAL_HOURS}h to $BACKUP_DIR, keeping ${RETENTION_DAYS} days"
  trap 'exit 0' TERM INT
  while true; do
    # An error is logged and the loop goes on.
    ( backup_and_rotate ) || true
    sleep $((INTERVAL_HOURS * 3600)) &
    wait $!
  done
}

# Backups by modification time, newest first: "mtime path".
sorted_backups() {
  find "$BACKUP_DIR" -maxdepth 1 -type f -name 'arcanum-*.dump.age' -printf '%T@ %p\n' | sort -rn
}

cmd_list() {
  local found=0 mtime path
  while read -r mtime path; do
    found=1
    printf '%s  %6s  %s\n' "$(date -u -d "@${mtime%.*}" '+%Y-%m-%d %H:%M UTC')" \
      "$(du -h "$path" | cut -f1)" "$(basename "$path")"
  done < <(sorted_backups)
  [ "$found" = 1 ] || echo "No backups in BACKUP_DIR." >&2
}

# Prints the path of the chosen backup: `latest`, a file name, a prefix
# (`20261103`, `arcanum-20261103-02`) or an already mounted path.
cmd_resolve() {
  local arg=${1:?missing the backup to restore} match="" mtime path
  if [ "${arg#/}" != "$arg" ] && [ -f "$arg" ]; then
    echo "$arg"; return
  fi
  if [ "$arg" = latest ]; then
    match=$(sorted_backups | head -n1 | cut -d' ' -f2-)
    [ -n "$match" ] || die "no backups in BACKUP_DIR"
    echo "$match"; return
  fi
  [ -f "$BACKUP_DIR/$arg" ] && { echo "$BACKUP_DIR/$arg"; return; }
  local prefix="arcanum-${arg#arcanum-}" count=0
  while read -r mtime path; do
    case "$(basename "$path")" in
      "$prefix"*) count=$((count + 1)); [ -n "$match" ] || match=$path ;;
    esac
  done < <(sorted_backups)
  [ -n "$match" ] || die "no backup matches '$arg' (use --list)"
  [ "$count" = 1 ] || log "$count backups match '$arg': using the newest"
  echo "$match"
}

decrypt() { age -d -i "$AGE_KEY_FILE" "$1"; }

# Restores the backup into a temporary DB and checks its contents, without
# touching the real DB.
cmd_verify() {
  local file=${1:?missing the file}
  require_key
  [ -f "$file" ] || die "file not found: $file"
  dropdb --if-exists "$CHECK_DB"
  trap 'dropdb --if-exists "$CHECK_DB" || true' EXIT
  createdb "$CHECK_DB"
  decrypt "$file" | pg_restore --no-owner --exit-on-error -d "$CHECK_DB" \
    || die "cannot decrypt or restore $(basename "$file") (wrong key or corrupted file?)"
  local q="psql -d $CHECK_DB -XAtq -v ON_ERROR_STOP=1 -c"
  local opaque accounts items deleted sessions
  opaque=$($q "SELECT count(*) FROM server_config WHERE key = 'opaque_server_setup'")
  [ "$opaque" = 1 ] || die "the backup does not contain the server OPAQUE secret (server_config.opaque_server_setup)"
  accounts=$($q "SELECT count(*) FROM accounts")
  items=$($q "SELECT count(*) FROM items WHERE NOT deleted")
  deleted=$($q "SELECT count(*) FROM items WHERE deleted")
  sessions=$($q "SELECT count(*) FROM sessions")
  echo "  accounts:     $accounts"
  echo "  items:        $items (plus $deleted deleted)"
  echo "  devices:      $sessions (will be signed out)"
  echo "  server OPAQUE secret: present"
}

cmd_pre_restore() {
  require_writable_dir
  backup_now pre-restore
}

# Replaces the real DB with the backup (the server must be stopped).
cmd_restore() {
  local file=${1:?missing the file}
  require_key
  # --single-transaction: either everything applies or the DB stays as it was.
  decrypt "$file" | pg_restore --clean --if-exists --no-owner --single-transaction \
    --exit-on-error -d "$PGDATABASE" || die "restore failed: the database was not modified"
  # Every device has to sign in again (sessions revoked after the backup do
  # not become valid again) and the server generates a new sync_epoch at
  # startup, which tells clients to resync from scratch.
  psql -XAtq -v ON_ERROR_STOP=1 -d "$PGDATABASE" <<'SQL'
BEGIN;
DELETE FROM sessions;
DELETE FROM pending_logins;
DELETE FROM server_config WHERE key = 'sync_epoch';
COMMIT;
SQL
  log "database restored from $(basename "$file")"
}

cmd_wait_health() {
  local i
  for i in $(seq 1 90); do
    if [ "$(curl -fsS --max-time 2 "$HEALTH_URL" 2>/dev/null)" = ok ]; then
      log "server is up ($HEALTH_URL = ok)"
      return
    fi
    sleep 1
  done
  die "the server is not responding at $HEALTH_URL"
}

case "${1:-loop}" in
  loop) cmd_loop ;;
  once) require_writable_dir; backup_and_rotate ;;
  list) cmd_list ;;
  resolve) shift; cmd_resolve "$@" ;;
  verify) shift; cmd_verify "$@" ;;
  pre-restore) cmd_pre_restore ;;
  restore) shift; cmd_restore "$@" ;;
  wait-health) cmd_wait_health ;;
  *) exec "$@" ;;
esac
