#!/usr/bin/env bash
# Restores the sync server database from an encrypted backup.
# Runs on the host and needs only Docker: age and pg_restore live in the
# compose `backup` service.
#
#   restore.sh [-f compose.yml]... --key <private-key.txt> \
#              [--list | latest | <file or date prefix>] [--yes]
#
#   -f FILE     compose file to use (repeatable; default: ../docker-compose.yml)
#   --key FILE  age private key (not needed with --list)
#   --list      list the backups in BACKUP_DIR
#   latest      the newest backup
#   <file>      a file name in BACKUP_DIR, a prefix of one (20261103,
#               20261103-02) or the path of a file on the host
#   --yes       do not ask for confirmation
#
# Steps: verify the backup in a temporary DB, confirm, take a pre-restore
# backup of the current state, stop the server, pg_restore in a single
# transaction, sign out every device and reset sync_epoch, restart the
# server and wait for /health.

set -euo pipefail

here=$(cd "$(dirname "$0")" && pwd)
compose_files=()
key="" target="" list=0 yes=0

usage() { sed -n '2,20s/^# \{0,1\}//p' "$0"; exit "${1:-0}"; }
die() { echo "ERROR: $*" >&2; exit 1; }
abs_path() { echo "$(cd "$(dirname "$1")" && pwd)/$(basename "$1")"; }

while [ $# -gt 0 ]; do
  case "$1" in
    -f|--file) [ $# -ge 2 ] || usage 1; compose_files+=(-f "$2"); shift 2 ;;
    --key) [ $# -ge 2 ] || usage 1; key=$2; shift 2 ;;
    --list) list=1; shift ;;
    --yes|-y) yes=1; shift ;;
    -h|--help) usage ;;
    -*) echo "Unknown option: $1" >&2; usage 1 ;;
    *) [ -z "$target" ] || usage 1; target=$1; shift ;;
  esac
done
[ ${#compose_files[@]} -gt 0 ] || compose_files=(-f "$here/../docker-compose.yml")

dc() { docker compose "${compose_files[@]}" "$@"; }

mounts=()
# Runs a backup.sh command in a throwaway container of the backup service,
# with key and dump mounted read-only.
backup_run() { dc run --rm -T ${mounts[@]+"${mounts[@]}"} backup "$@" </dev/null; }

if [ "$list" = 1 ]; then
  backup_run list
  exit
fi

[ -n "$target" ] || die "specify the backup to restore (latest, a file or a date; --list to list them)"
[ -n "$key" ] || die "missing --key <private-key.txt>"
[ -f "$key" ] || die "private key not found: $key"
mounts+=(-v "$(abs_path "$key"):/run/restore/key.txt:ro")

# A host file outside BACKUP_DIR is mounted separately.
if [ -f "$target" ]; then
  mounts+=(-v "$(abs_path "$target"):/restore/$(basename "$target"):ro")
  target="/restore/$(basename "$target")"
fi

echo "==> Choosing the backup"
file=$(backup_run resolve "$target")
name=$(basename "$file")
echo "    $name"

echo "==> Verifying in a temporary database"
summary=$(backup_run verify "$file") || die "verification failed: the current database was not touched"
echo "$summary"

if [ "$yes" != 1 ]; then
  [ -t 0 ] || die "no terminal to confirm on: use --yes"
  echo
  echo "The current database will be replaced with $name."
  echo "A pre-restore backup of the current state is saved first."
  printf 'Proceed? [y/N] '
  read -r answer
  case "$answer" in y|Y|yes|YES) ;; *) echo "Cancelled."; exit 1 ;; esac
fi

echo "==> Safety backup of the current state"
pre=$(backup_run pre-restore) || die "pre-restore backup failed: restore cancelled"
echo "    $(basename "$pre")"

echo "==> Stopping the server"
dc stop server
# From here on the server must be restarted no matter what.
trap 'echo "==> Restarting the server"; dc start server' EXIT

echo "==> Restoring $name"
backup_run restore "$file"

trap - EXIT
echo "==> Restarting the server"
dc start server
backup_run wait-health

cat <<EOF

Restore from $name complete.
Previous state saved in $(basename "$pre"): to undo the restore, run this
script again with that file.

On the devices:
- every session was closed: the apps ask to reconnect ("Riconnetti") and
  need the master password (the one that was valid at the backup date);
- after reconnecting, each device resyncs from scratch and merges its data
  with the server's: changes and deletions made after the backup are
  uploaded again by the devices that have them;
- accounts created after the backup no longer exist: on those devices,
  disconnect sync and register the account again.
EOF
