#!/bin/sh
set -eu

kea-admin db-version pgsql \
  -u "${SHARED_DB_USER:-kea}" \
  -p "${SHARED_DB_PASS:-}" \
  -n "${SHARED_DB_NAME:-kea_db}" \
  -h 127.0.0.1 \
  -4 >/dev/null 2>&1

kea-admin db-version pgsql \
  -u "${SHARED_DB_USER:-kea}" \
  -p "${SHARED_DB_PASS:-}" \
  -n "${SHARED_DB_NAME:-kea_db}" \
  -h 127.0.0.1 \
  -6 >/dev/null 2>&1
