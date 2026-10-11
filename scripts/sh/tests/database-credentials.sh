#!/bin/sh
# Run only in a disposable project-image container, with source mounted at /source.
set -eu
service="$1"
case "$service" in shared-db|dhcp|stork) ;; *) exit 2 ;; esac

# Stage the bind-mounted fixtures on the container filesystem.
cp -R /source /tmp/source

awk '/^# Main entrypoint/ || /^start_postgres$/ || /^echo .*starting shared PostgreSQL setup/ { exit } { print }' \
  "/tmp/source/$service/entrypoint.sh" > /tmp/entrypoint-functions.sh
. /tmp/entrypoint-functions.sh
password=$(cat <<'VALUE'
quote' double" slash/ amp& back\ dollar$ $(touch /tmp/credential-injection); space
second line
VALUE
)
password="$password$(printf '\140backtick\140')"
user='fixture"role'
database='fixture database'
case "$service" in
  shared-db)
    SHARED_DB_USER="$user"
    SHARED_DB_PASS="$password"
    SHARED_DB_NAME="$database"
    PGUSER="$user"
    PGPASSWORD="$password"
    PGDATABASE="$database"
    PG_TEMPLATE_DIR=/tmp/source/shared-db
    ;;
  dhcp)
    LEASE_DB_USER="$user"
    LEASE_DB_PASS="$password"
    LEASE_DB_NAME="$database"
    SHARED_DB_USER=old_fixture
    SHARED_DB_NAME=shared_fixture
    SHARED_DB_PASS="shared:$password"
    PGUSER="$user"
    PGPASSWORD="$password"
    PG_TEMPLATE_DIR=/tmp/source/dhcp
    ;;
  stork)
    STORK_DB_USER="$user"
    STORK_DB_PASSWORD="$password"
    STORK_DB_NAME="$database"
    ;;
esac
export PGPASSWORD
KEA_SCHEMA_TOOL="/tmp/source/$service/kea-schema.sh"
export KEA_SCHEMA_TOOL
start_postgres
wait_postgres
case "$service" in
  stork) setup_stork_database; setup_stork_database; data="$STORK_DB_DATA" ;;
  *) setup_postgres_db; setup_postgres_db; data="$PGDATA" ;;
esac

# Force password authentication for the proof; only this disposable cluster changes.
printf 'local all all trust\nhost all all 127.0.0.1/32 scram-sha-256\n' > "$data/pg_hba.conf"
su -s /bin/sh postgres -c "$PGBIN/pg_ctl -D '$data' reload >/dev/null"
PGPASSWORD="$password" psql -X -v ON_ERROR_STOP=1 -h 127.0.0.1 -U "$user" -d "$database" -tAc 'SELECT 1' | grep -qx 1
test ! -e /tmp/credential-injection

if [ "$service" = shared-db ]; then
  init_pgsql_v4
  init_pgsql_v6
  export SHARED_DB_USER SHARED_DB_PASS SHARED_DB_NAME
  sh /tmp/source/shared-db/healthcheck.sh
fi

if [ "$service" = dhcp ]; then
  DHCP4_SOURCE_FILE=/tmp/source/dhcp4/kea-dhcp4.conf
  DHCP6_SOURCE_FILE=/tmp/source/dhcp6/kea-dhcp6.conf
  DDNS_SOURCE_FILE=/tmp/source/ddns/kea-dhcp-ddns.conf
  # Supply deterministic addresses in this network-disabled test container.
  getent() { printf '127.0.0.1 STREAM fixture\n'; }
  DNS_ENABLED=false
  render_configs
  for file in "$DHCP4_FILE" "$DHCP6_FILE"; do
    jq -e '
      .[] | .["lease-database"].password == env.LEASE_DB_PASS
      and .["hosts-database"].password == env.SHARED_DB_PASS
      and .["lease-database"].name == env.LEASE_DB_NAME
      and .["hosts-database"].name == env.SHARED_DB_NAME
    ' "$file" >/dev/null
    jq -e '[.. | strings | select(test("^__(LEASE|SHARED)_DB_"))] | length == 0' "$file" >/dev/null
    jq -e '.[] | .["hooks-libraries"][] | select(.library | endswith("libdhcp_legal_log.so")) | .parameters.password == env.SHARED_DB_PASS' "$file" >/dev/null
    jq -e '.[] | has("dhcp-ddns") | not' "$file" >/dev/null
    jq -e --slurpfile original "/tmp/source/dhcp$(test "$file" = "$DHCP4_FILE" && printf 4 || printf 6)/kea-dhcp$(test "$file" = "$DHCP4_FILE" && printf 4 || printf 6).conf" \
      '.[keys[0]]["option-data"] == $original[0][keys[0]]["option-data"]' "$file" >/dev/null
  done
  DNS_ENABLED=true
  DDNS_TSIG_KEY="$(head -c 32 /dev/urandom | base64)"
  render_configs
  for file in "$DHCP4_FILE" "$DHCP6_FILE"; do
    jq -e '.[] | .["dhcp-ddns"]."enable-updates" == true' "$file" >/dev/null
  done
fi
echo "$service: SQL initialization, repeat setup, password authentication and injection checks passed"
