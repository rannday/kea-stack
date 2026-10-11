#!/bin/sh
# Identical in both build contexts; regression coverage checks that they agree.
set -eu
mode="${1:?Usage: kea-schema.sh init|check|backup|upgrade lease|shared}"
case "${2:-}" in
  lease)
    PGDATABASE="${LEASE_DB_NAME:-kea_leases}"
    PGUSER="${LEASE_DB_USER:-kea_lease}"
    ;;
  shared)
    PGDATABASE="${SHARED_DB_NAME:-kea_db}"
    PGUSER="${SHARED_DB_USER:-kea}"
    ;;
  *) echo "[schema] select lease or shared" >&2; exit 2 ;;
esac
PGHOST=/var/run/postgresql
PGPORT=5432
export PGDATABASE PGUSER PGHOST PGPORT
expected="${KEA_SCHEMA_VERSION:-34.0}"

sql() {
  psql -X -v ON_ERROR_STOP=1 -Atc "$1"
}

version() {
  value="$(sql "SELECT version || '.' || minor FROM public.schema_version")"
  printf '%s\n' "$value" | awk 'NR != 1 || $0 !~ /^[0-9]+\.[0-9]+$/ { bad = 1 } END { exit (bad || NR != 1) }' || {
    echo "[schema] missing or malformed schema version" >&2
    exit 1
  }
  printf '%s\n' "$value"
}

check() {
  current="$(version)"
  if [ "$current" = "$expected" ]; then
    echo "[schema] compatible PostgreSQL schema $current"
    return
  fi
  if ! awk -v current="$current" -v expected="$expected" 'BEGIN {
    split(current, c, "."); split(expected, e, ".");
    exit !(c[1] < e[1] || (c[1] == e[1] && c[2] < e[2]))
  }'; then
    echo "[schema] schema $current is newer than required $expected; downgrades are unsupported" >&2
    exit 1
  fi
  if [ "$mode" = init ]; then
    echo "[schema] schema $current requires $expected. A database migration is required before starting Kea." >&2
    echo "[schema] From the project directory, run either:" >&2
    echo "[schema] PowerShell: ./scripts/upgrade-kea.ps1 -BackupDirectory <new-directory>" >&2
    echo "[schema] POSIX shell: sh scripts/upgrade-kea.sh <new-directory>" >&2
    echo "[schema] Choose a new backup directory outside the repository. See docs/kea.md." >&2
    exit 1
  fi
  echo "[schema] upgrade required: $current -> $expected"
}

case "$mode" in
  init)
    exists="$(sql "SELECT to_regclass('public.schema_version') IS NOT NULL")"
    if [ "$exists" = f ]; then
      count="$(sql "SELECT count(*) FROM pg_class WHERE relnamespace = 'public'::regnamespace AND relkind IN ('r','p','v','m','S','f')")"
      if [ "$count" != 0 ]; then
        echo "[schema] nonempty database has no schema_version; refusing initialization" >&2
        exit 1
      fi
      kea-admin db-init pgsql -u "$PGUSER" -n "$PGDATABASE" -h "$PGHOST"
    fi
    check
    ;;
  check) check ;;
  backup)
    # Keep binary dumps out of PowerShell pipelines and protect container copies.
    umask 077
    mkdir /tmp/kea-upgrade-backup
    pg_dump --exclude-schema=cron --format=custom --file=/tmp/kea-upgrade-backup/database.dump
    pg_restore --list /tmp/kea-upgrade-backup/database.dump >/dev/null
    pg_dumpall -U postgres --globals-only --file=/tmp/kea-upgrade-backup/globals.sql
    version > /tmp/kea-upgrade-backup/schema-version.txt
    ;;
  upgrade)
    check
    if [ "$current" != "$expected" ]; then
      kea-admin db-upgrade pgsql -u "$PGUSER" -n "$PGDATABASE" -h "$PGHOST"
    fi
    current="$(version)"
    if [ "$current" != "$expected" ]; then
      echo "[schema] migration ended at $current, expected $expected" >&2
      exit 1
    fi
    echo "[schema] migration complete: $current"
    ;;
  *) echo "[schema] unknown operation" >&2; exit 2 ;;
esac
