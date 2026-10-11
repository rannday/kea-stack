#!/bin/sh
# Disposable stable project image only; scripts/sh/tests mounted at /tests.
set -eu
service="${1:?database or dhcp}"
case "$service" in
  database) role=shared; database=kea_db; user=kea ;;
  dhcp) role=lease; database=kea_leases; user=kea_lease ;;
  *) exit 2 ;;
esac
export PGHOST=/var/run/postgresql PGUSER=postgres
awk '/^# Main entrypoint/ { exit } { print }' /usr/local/bin/entrypoint.sh > /tmp/functions.sh
. /tmp/functions.sh
start_postgres
wait_postgres
setup_postgres_db
tool=/usr/local/bin/kea-schema.sh
sh "$tool" init "$role" >/tmp/init.log
sh "$tool" init "$role"
test "$(psql -XAt -U "$user" -d "$database" -c "SELECT version || '.' || minor FROM schema_version")" = 34.0

# Reconstruct the actual 33.0 schema from the packaged creation script.
psql -X -v ON_ERROR_STOP=1 -U "$user" -d "$database" -c 'DROP SCHEMA public CASCADE; CREATE SCHEMA public;' >/dev/null 2>&1
awk '/This line starts the schema upgrade to version 34.0/ { exit } { print }' /usr/share/kea/scripts/pgsql/dhcpdb_create.pgsql > /tmp/schema33.sql
printf '\nCOMMIT;\n' >> /tmp/schema33.sql
psql -X -v ON_ERROR_STOP=1 -U "$user" -d "$database" -f /tmp/schema33.sql >/dev/null 2>&1
test "$(psql -XAt -U "$user" -d "$database" -c "SELECT version || '.' || minor FROM schema_version")" = 33.0
psql -X -v ON_ERROR_STOP=1 -U "$user" -d "$database" -c "CREATE TABLE migration_fixture(value text); INSERT INTO migration_fixture VALUES ('preserved');" >/dev/null
if sh "$tool" init "$role" >/tmp/reject.log 2>&1; then echo "Old schema accepted at startup"; exit 1; fi
grep -q 'schema 33.0 requires 34.0' /tmp/reject.log
grep -q 'upgrade-kea.ps1 -BackupDirectory' /tmp/reject.log
grep -q 'sh scripts/sh/upgrade-kea.sh' /tmp/reject.log
grep -q 'See docs/kea.md' /tmp/reject.log
sh "$tool" check "$role"
sh "$tool" backup "$role"
sh "$tool" upgrade "$role"
sh "$tool" upgrade "$role"
test "$(psql -XAt -U "$user" -d "$database" -c 'SELECT value FROM migration_fixture')" = preserved

# Restore the pre-upgrade archive to a separate, empty database.
createdb -U postgres -O "$user" fixture_restore
pg_restore --exit-on-error -U "$user" -d fixture_restore /tmp/kea-upgrade-backup/database.dump
test "$(psql -XAt -U "$user" -d fixture_restore -c "SELECT version || '.' || minor FROM schema_version")" = 33.0
test "$(psql -XAt -U "$user" -d fixture_restore -c 'SELECT value FROM migration_fixture')" = preserved
test "$(stat -c %a /tmp/kea-upgrade-backup/database.dump)" = 600
test -s /tmp/kea-upgrade-backup/globals.sql

psql -X -v ON_ERROR_STOP=1 -U "$user" -d "$database" -c 'UPDATE schema_version SET version = 99;' >/dev/null
for operation in init check upgrade; do
    if sh "$tool" "$operation" "$role" >/tmp/reject.log 2>&1; then echo "Newer schema accepted"; exit 1; fi
    grep -q 'downgrades are unsupported' /tmp/reject.log
done
psql -X -v ON_ERROR_STOP=1 -U "$user" -d "$database" -c 'DROP TABLE schema_version;' >/dev/null
if sh "$tool" init "$role" >/tmp/reject.log 2>&1; then echo "Damaged schema initialized"; exit 1; fi
grep -q 'refusing initialization' /tmp/reject.log
echo "PASS: $service fresh/repeat initialization, old/new/damaged rejection, 33-to-34 upgrade, repeat upgrade, backup and restore"
