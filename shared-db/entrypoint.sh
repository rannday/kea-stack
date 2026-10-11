#!/bin/sh
set -eu

PGHOST="127.0.0.1"
PG_LISTEN_ADDRESSES="0.0.0.0"
PGPORT="5432"
PGDATA="/var/lib/postgresql/data"
SHARED_DB_USER="${SHARED_DB_USER:-kea}"
SHARED_DB_PASS="${SHARED_DB_PASS:-}"
SHARED_DB_NAME="${SHARED_DB_NAME:-kea_db}"
PGUSER="${SHARED_DB_USER}"
PGPASSWORD="${SHARED_DB_PASS}"
PGDATABASE="${SHARED_DB_NAME}"
PG_TEMPLATE_DIR="/usr/local/share/kea"

export PGPASSWORD

find_postgres_bin() {
  if command -v postgres >/dev/null 2>&1; then
    dirname "$(command -v postgres)"
    return 0
  fi

  for dir in /usr/lib/postgresql/*/bin; do
    if [ -x "${dir}/postgres" ]; then
      echo "${dir}"
      return 0
    fi
  done

  echo "[entrypoint] could not find postgres binary" >&2
  exit 1
}

PGBIN="$(find_postgres_bin)"

cleanup() {
  su -s /bin/sh postgres -c "${PGBIN}/pg_ctl -D '${PGDATA}' -m fast stop >/dev/null" 2>/dev/null || true
}
trap cleanup EXIT
trap 'exit 0' INT TERM

start_postgres() {
  echo "[entrypoint] preparing PostgreSQL shared DB"

  mkdir -p "${PGDATA}" /var/run/postgresql
  chown -R postgres:postgres /var/lib/postgresql /var/run/postgresql
  chmod 2775 /var/run/postgresql

  if [ ! -s "${PGDATA}/PG_VERSION" ]; then
    echo "[entrypoint] initializing PostgreSQL shared cluster"
    su -s /bin/sh postgres -c "${PGBIN}/initdb -D '${PGDATA}' >/dev/null"
  fi

  cp "${PG_TEMPLATE_DIR}/postgresql.conf" "${PGDATA}/postgresql.conf"
  if [ "${1:-}" = --database-only ]; then
    echo "cron.launch_active_jobs = off" >> "${PGDATA}/postgresql.conf"
  fi
  export PGDATABASE
  awk 'BEGIN {
    value = ENVIRON["PGDATABASE"]
    if (value == "" || value ~ /[\r\n]/) exit 1
    result = ""
    for (i = 1; i <= length(value); i++) {
      character = substr(value, i, 1)
      result = result (character == "\047" || character == "\\" ? character character : character)
    }
    print "cron.database_name = \047" result "\047"
  }' /dev/null >> "${PGDATA}/postgresql.conf"
  export SHARED_DB_USER
  awk '
    function quote(value, result, i, character) {
      if (value == "" || value ~ /[\r\n]/) exit 1
      result = "\""
      for (i = 1; i <= length(value); i++) {
        character = substr(value, i, 1)
        result = result (character == "\"" ? "\"\"" : character)
      }
      return result "\""
    }
    function substitute(line, token, value, position, result) {
      result = ""
      while ((position = index(line, token)) != 0) {
        result = result substr(line, 1, position - 1) value
        line = substr(line, position + length(token))
      }
      return result line
    }
    {
      $0 = substitute($0, "__SHARED_DB_USER__", quote(ENVIRON["SHARED_DB_USER"]))
      print
    }
  ' "${PG_TEMPLATE_DIR}/pg_hba.conf" > "${PGDATA}/pg_hba.conf"
  chown postgres:postgres "${PGDATA}/postgresql.conf" "${PGDATA}/pg_hba.conf"

  echo "[entrypoint] starting PostgreSQL shared DB"
  su -s /bin/sh postgres -c "${PGBIN}/pg_ctl -D '${PGDATA}' -o '-c listen_addresses=${PG_LISTEN_ADDRESSES} -c shared_preload_libraries=pg_cron -p ${PGPORT}' -w start >/dev/null"
}

wait_postgres() {
  echo "[entrypoint] waiting for PostgreSQL shared DB"
  until pg_isready -h "${PGHOST}" -p "${PGPORT}" >/dev/null 2>&1; do
    sleep 1
  done
}

pg_sql() {
  su -m -s /bin/sh postgres -c 'exec psql -X -v ON_ERROR_STOP=1 -h "$PGHOST" -p "$PGPORT" -U postgres -d "$DB_SETUP_TARGET"'
}

setup_postgres_db() {
  echo "[entrypoint] ensuring shared PostgreSQL role and database exist"

  DB_SETUP_USER="${PGUSER}"
  DB_SETUP_PASSWORD="${PGPASSWORD}"
  DB_SETUP_NAME="${PGDATABASE}"
  DB_SETUP_TARGET=postgres
  export PGHOST PGPORT DB_SETUP_USER DB_SETUP_PASSWORD DB_SETUP_NAME DB_SETUP_TARGET
  pg_sql <<'SQL'
\getenv db_user DB_SETUP_USER
\getenv db_password DB_SETUP_PASSWORD
\getenv db_name DB_SETUP_NAME
SELECT format('CREATE ROLE %I LOGIN', :'db_user')
WHERE NOT EXISTS (SELECT FROM pg_roles WHERE rolname = :'db_user')
\gexec
SELECT format('ALTER ROLE %I WITH LOGIN PASSWORD %L', :'db_user', :'db_password')
\gexec
SELECT format('CREATE DATABASE %I OWNER %I', :'db_name', :'db_user')
WHERE NOT EXISTS (SELECT FROM pg_database WHERE datname = :'db_name')
\gexec
SQL
}

init_pgsql_v4() {
  sh "${KEA_SCHEMA_TOOL:-/usr/local/bin/kea-schema.sh}" init shared
}

# DHCPv4 and DHCPv6 share one PostgreSQL schema.
init_pgsql_v6() {
  init_pgsql_v4
}

configure_pg_cron() {
  echo "[entrypoint] ensuring shared DB pg_cron cleanup jobs exist"

  DB_SETUP_TARGET="${PGDATABASE}"
  pg_sql <<'SQL'
CREATE EXTENSION IF NOT EXISTS pg_cron;

SELECT cron.unschedule(jobid)
FROM cron.job
WHERE jobname IN ('kea_logs_purge_batch', 'kea_logs_vacuum');

SELECT cron.schedule(
  'kea_logs_purge_batch',
  '0 * * * *',
  $sql$
    DELETE FROM public.logs
    WHERE ctid IN (
      SELECT ctid
      FROM public.logs
      WHERE "timestamp" < now() - interval '2 years'
      ORDER BY "timestamp"
      LIMIT 10000
    );
  $sql$
);

SELECT cron.schedule(
  'kea_logs_vacuum',
  '10 3 * * *',
  'VACUUM (ANALYZE) public.logs;'
);
SQL
}

main_loop() {
  while :; do
    if ! pg_isready -h "${PGHOST}" -p "${PGPORT}" -U "${PGUSER}" -d "${PGDATABASE}" >/dev/null 2>&1; then
      echo "[entrypoint] shared PostgreSQL health check failed"
      return 1
    fi

    sleep 5
  done
}

# Main entrypoint
echo "[entrypoint] starting shared PostgreSQL setup"
case "${1:-}" in
  ""|--database-only) ;;
  *) echo "[entrypoint] unsupported command" >&2; exit 2 ;;
esac
start_postgres "${1:-}"
wait_postgres
if [ "${1:-}" = --database-only ]; then
  echo "[entrypoint] database-only maintenance mode; cron jobs are disabled"
  main_loop
  exit 1
fi
setup_postgres_db
init_pgsql_v4
init_pgsql_v6
configure_pg_cron

echo "[entrypoint] shared PostgreSQL is up"
main_loop
