#!/bin/sh
set -eu

BACKUP_ROOT=/var/lib/kea-backups

check_group() {
  label="$1"
  marker="$2"
  interval="$3"
  shift 3

  case "${interval}" in
    ''|*[!0-9]*) echo "invalid ${label} backup interval"; exit 1 ;;
  esac
  if [ "${interval}" -lt 60 ]; then
    echo "${label} backup interval is below 60 seconds"
    exit 1
  fi
  if [ ! -s "${marker}" ]; then
    echo "no successful ${label} backup has completed yet"
    exit 1
  fi

  last_success=$(cat "${marker}")
  case "${last_success}" in
    ''|*[!0-9]*) echo "invalid ${label} backup success marker"; exit 1 ;;
  esac
  now=$(date +%s)
  age=$((now - last_success))
  max_age=$((interval + 3600))
  if [ "${age}" -lt 0 ] || [ "${age}" -gt "${max_age}" ]; then
    echo "last successful ${label} backup is overdue"
    exit 1
  fi

  for directory in "$@"; do
    if ! find "${BACKUP_ROOT}/${directory}" -maxdepth 1 -type f -name '*.dump' -print -quit | grep -q .; then
      echo "no ${directory} database dump found"
      exit 1
    fi
  done
}

check_group Kea "${BACKUP_ROOT}/last-success-kea" "${SHARED_DB_BACKUP_INTERVAL_SECONDS:-10800}" leases shared
check_group Stork "${BACKUP_ROOT}/last-success-stork" "${STORK_DB_BACKUP_INTERVAL_SECONDS:-86400}" stork

echo "latest database dumps are present"
