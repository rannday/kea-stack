#!/bin/sh
# Test host orchestration without a Docker daemon or real deployment data.
set -eu
repo_root=$(CDPATH= cd -P -- "$(dirname -- "$0")/../../.." && pwd)
fixture=$(mktemp -d "${TMPDIR:-/tmp}/kea-upgrade-test.XXXXXXXXXX")
trap 'rm -rf -- "$fixture"' 0
trap 'exit 130' INT
trap 'exit 143' TERM
mkdir "$fixture/bin"
cat > "$fixture/bin/docker" <<'MOCK'
#!/bin/sh
set -eu
printf '%s\n' "$*" >> "$MOCK_LOG"
case "$*" in
  'info'|'compose version') exit 0 ;;
  'compose ps --all --quiet database') echo database-container ;;
  'compose ps --all --quiet dhcp') echo dhcp-container ;;
  inspect*) printf 'sha256:%064d\n' 1 ;;
  'compose build database dhcp') [ "$MOCK_FAIL" != build ] ;;
  cp*) [ "$MOCK_FAIL" != copy ] ;;
  *'kea-schema.sh upgrade shared') [ "$MOCK_FAIL" != upgrade ] ;;
  'compose up '*) [ "$MOCK_FAIL" != restart ] ;;
esac
MOCK
chmod 755 "$fixture/bin/docker"
PATH="$fixture/bin:$PATH"
export PATH MOCK_LOG MOCK_FAIL

for scenario in success build copy upgrade restart; do
  MOCK_FAIL=$scenario
  MOCK_LOG="$fixture/$scenario.log"
  backup="$fixture/backup $scenario"
  if sh "$repo_root/scripts/sh/upgrade-kea.sh" "$backup" > "$fixture/$scenario.out" 2>&1; then
    [ "$scenario" = success ] || { echo "Unexpected success: $scenario"; exit 1; }
  else
    [ "$scenario" != success ] || { cat "$fixture/$scenario.out"; exit 1; }
  fi
  case "$scenario" in
    success)
      awk '/^cp / { copies++ } /kea-schema.sh upgrade/ { if (copies != 2) exit 1; upgrades++ } END { if (upgrades != 2) exit 1 }' "$MOCK_LOG"
      grep -q '^compose up .*--wait' "$MOCK_LOG"
      [ "$(grep -c '^compose stop ' "$MOCK_LOG")" -eq 1 ]
      ;;
    build) ! grep -Eq '^compose stop|^compose run' "$MOCK_LOG" ;;
    copy)
      ! grep -Eq 'kea-schema.sh upgrade|^compose up ' "$MOCK_LOG"
      grep -q '^rm kea-stack-upgrade-' "$MOCK_LOG"
      ;;
    upgrade)
      ! grep -q '^compose up ' "$MOCK_LOG"
      [ "$(grep -c '^rm kea-stack-upgrade-' "$MOCK_LOG")" -eq 2 ]
      ;;
  esac
  if [ "$scenario" != success ] && [ "$scenario" != build ]; then
    [ "$(tail -n 1 "$MOCK_LOG")" = 'compose stop backups stork dhcp database' ]
    grep -q 'Upgrade incomplete' "$fixture/$scenario.out"
  fi
  [ -f "$backup/previous-images.json" ]
done

# Reject repository destinations and existing paths before calling Docker.
MOCK_LOG="$fixture/rejected.log"
MOCK_FAIL=success
if sh "$repo_root/scripts/sh/upgrade-kea.sh" "$repo_root/forbidden-backup" >/dev/null 2>&1; then exit 1; fi
if sh "$repo_root/scripts/sh/upgrade-kea.sh" "$fixture" >/dev/null 2>&1; then exit 1; fi
[ ! -e "$MOCK_LOG" ]
echo 'PASS: shell upgrade ordering, build/copy/migration/restart failures, cleanup, quoted paths, and destination guards'
