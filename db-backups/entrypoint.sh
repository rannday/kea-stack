#!/bin/sh
set -eu
umask 077

dump_temp=''
cleanup_dump() {
  if [ -n "${dump_temp}" ]; then
    rm -f "${dump_temp}"
  fi
}
trap cleanup_dump 0
trap 'exit 130' INT
trap 'exit 143' TERM

BACKUP_ROOT=/var/lib/kea-backups
KEA_RETENTION_DAYS="${SHARED_DB_BACKUP_RETENTION_DAYS:-1}"
KEA_INTERVAL_SECONDS="${SHARED_DB_BACKUP_INTERVAL_SECONDS:-10800}"
STORK_RETENTION_DAYS="${STORK_DB_BACKUP_RETENTION_DAYS:-3}"
STORK_INTERVAL_SECONDS="${STORK_DB_BACKUP_INTERVAL_SECONDS:-86400}"

validate_positive_integer() {
  label="$1"
  value="$2"
  minimum="$3"
  case "${value}" in
    ''|*[!0-9]*) echo "[backups] ${label} must be a positive integer" >&2; exit 1 ;;
  esac
  if [ "${value}" -lt "${minimum}" ]; then
    echo "[backups] ${label} must be at least ${minimum}" >&2
    exit 1
  fi
}

validate_positive_integer "Kea retention days" "${KEA_RETENTION_DAYS}" 1
validate_positive_integer "Kea interval seconds" "${KEA_INTERVAL_SECONDS}" 60
validate_positive_integer "Stork retention days" "${STORK_RETENTION_DAYS}" 1
validate_positive_integer "Stork interval seconds" "${STORK_INTERVAL_SECONDS}" 60

mkdir -p "${BACKUP_ROOT}/leases" "${BACKUP_ROOT}/shared" "${BACKUP_ROOT}/stork"
# Only this service writes these directories. Remove unpublished files left by
# an interrupted previous run, including one stopped with SIGKILL.
for label in leases shared stork; do
  find "${BACKUP_ROOT}/${label}" -maxdepth 1 -type f \
    -name ".${label}_*.dump.tmp.*" -delete
done

dump_database() {
  label="$1"
  host="$2"
  database="$3"
  user="$4"
  password="$5"
  directory="$6"
  exclude_schema="${7:-}"
  file="${directory}/${label}_$(date -u +%Y%m%dT%H%M%SZ).dump"
  dump_temp=$(mktemp "${directory}/.${file##*/}.tmp.XXXXXX") || return 1

  echo "[backups] dumping ${label} database ${database} from ${host}"
  set -- \
    --host="${host}" --port=5432 --username="${user}" --dbname="${database}" \
    --format=custom --compress=6 --no-password --file="${dump_temp}"
  if [ -n "${exclude_schema}" ]; then
    set -- "$@" --exclude-schema="${exclude_schema}"
  fi
  if ! PGPASSWORD="${password}" PGCONNECT_TIMEOUT=10 pg_dump "$@"; then
    cleanup_dump
    dump_temp=''
    echo "[backups] dump failed for ${label}" >&2
    return 1
  fi
  if [ ! -s "${dump_temp}" ]; then
    cleanup_dump
    dump_temp=''
    echo "[backups] empty dump for ${label}" >&2
    return 1
  fi
  if ! mv "${dump_temp}" "${file}"; then
    cleanup_dump
    dump_temp=''
    echo "[backups] could not publish dump for ${label}" >&2
    return 1
  fi
  dump_temp=''
  echo "[backups] wrote ${file}"
}

prune_directory() {
  directory="$1"
  retention_days="$2"
  find "${directory}" -maxdepth 1 -type f -name '*.dump' \
    -mmin "+$((retention_days * 1440))" -delete
}

run_kea_backup() {
  dump_database leases lease-db "${LEASE_DB_NAME}" "${LEASE_DB_USER}" "${LEASE_DB_PASS}" "${BACKUP_ROOT}/leases" || return 1
  dump_database shared shared-db "${SHARED_DB_NAME}" "${SHARED_DB_USER}" "${SHARED_DB_PASS}" "${BACKUP_ROOT}/shared" || return 1
  prune_directory "${BACKUP_ROOT}/leases" "${KEA_RETENTION_DAYS}" || return 1
  prune_directory "${BACKUP_ROOT}/shared" "${KEA_RETENTION_DAYS}" || return 1
  date +%s > "${BACKUP_ROOT}/last-success-kea.tmp"
  mv "${BACKUP_ROOT}/last-success-kea.tmp" "${BACKUP_ROOT}/last-success-kea"
  echo "[backups] Kea database dumps completed"
}

run_stork_backup() {
  dump_database stork stork-db "${STORK_DB_NAME}" "${STORK_DB_USER}" "${STORK_DB_PASS}" "${BACKUP_ROOT}/stork" || return 1
  prune_directory "${BACKUP_ROOT}/stork" "${STORK_RETENTION_DAYS}" || return 1
  date +%s > "${BACKUP_ROOT}/last-success-stork.tmp"
  mv "${BACKUP_ROOT}/last-success-stork.tmp" "${BACKUP_ROOT}/last-success-stork"
  echo "[backups] Stork database dump completed"
}

next_log_purge=0
last_log_vacuum=''
next_kea_backup=0
next_stork_backup=0
while :; do
  now=$(date +%s)
  if [ "${now}" -ge "${next_log_purge}" ]; then
    PGPASSWORD="$SHARED_DB_PASS" PGCONNECT_TIMEOUT=10 psql -X -v ON_ERROR_STOP=1 \
      -h shared-db -U "$SHARED_DB_USER" -d "$SHARED_DB_NAME" -c \
      'DELETE FROM public.logs WHERE ctid IN (SELECT ctid FROM public.logs WHERE "timestamp" < now() - interval '\''2 years'\'' ORDER BY "timestamp" LIMIT 10000);'
    next_log_purge=$((now + 3600))
  fi
  today=$(date -u +%F)
  if [ "$(date -u +%H%M)" -ge 310 ] && [ "$last_log_vacuum" != "$today" ]; then
    PGPASSWORD="$SHARED_DB_PASS" PGCONNECT_TIMEOUT=10 psql -X -v ON_ERROR_STOP=1 \
      -h shared-db -U "$SHARED_DB_USER" -d "$SHARED_DB_NAME" -c 'VACUUM (ANALYZE) public.logs;'
    last_log_vacuum="$today"
  fi
  if [ "${now}" -ge "${next_kea_backup}" ]; then
    run_kea_backup || exit 1
    next_kea_backup=$(($(date +%s) + KEA_INTERVAL_SECONDS))
  fi
  now=$(date +%s)
  if [ "${now}" -ge "${next_stork_backup}" ]; then
    run_stork_backup || exit 1
    next_stork_backup=$(($(date +%s) + STORK_INTERVAL_SECONDS))
  fi
  sleep 60
done
