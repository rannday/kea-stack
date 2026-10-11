#!/bin/sh
set -eu
# The bootstrap postgres account remains separate from ordinary application roles.
psql -X -v ON_ERROR_STOP=1 --username "$POSTGRES_USER" --dbname postgres <<'SQL'
\getenv app_user APP_DB_USER
\getenv app_password APP_DB_PASSWORD
\getenv app_database APP_DB_NAME
CREATE ROLE :"app_user" LOGIN PASSWORD :'app_password';
CREATE DATABASE :"app_database" OWNER :"app_user";
SQL
if [ "${APP_DB_NAME}" = stork ]; then
  psql -X -v ON_ERROR_STOP=1 --username "$POSTGRES_USER" --dbname "$APP_DB_NAME" -c 'CREATE EXTENSION IF NOT EXISTS pgcrypto;'
fi
