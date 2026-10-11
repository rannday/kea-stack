#!/bin/sh
set -eu

service="$1"
cp -R /source /tmp/source
awk '/^write_tsig_key\(\) \{/ { copy = 1 } copy { print } copy && /^\}/ { exit }' "/tmp/source/$service/entrypoint.sh" > /tmp/tsig-functions.sh
. /tmp/tsig-functions.sh
mkdir -p /run/kea /var/run/named
DNS_ENABLED=true
unset DDNS_TSIG_KEY
if (write_tsig_key) >/dev/null 2>&1; then
  echo "Missing key was accepted" >&2
  exit 1
fi
DDNS_TSIG_KEY='invalid"; injected'
if (write_tsig_key) >/dev/null 2>&1; then
  echo "Malformed key was accepted" >&2
  exit 1
fi
DDNS_TSIG_KEY="$(head -c 32 /dev/urandom | base64)"
export DDNS_TSIG_KEY
write_tsig_key

if [ "$service" = dhcp ]; then
  test "$(cat /run/kea/kea-ddns.key)" = "$DDNS_TSIG_KEY"
  test "$(stat -c %a /run/kea/kea-ddns.key)" = 600
  printf 'test-user\n' > /etc/kea/ddns-api-user
  printf 'test-password\n' > /etc/kea/ddns-api-password
  jq 'walk(if . == "__KEA_CONTROL_ADDRESS__" or . == "__DNS_ADDRESS__" then "127.0.0.1" else . end)' /tmp/source/ddns/kea-dhcp-ddns.conf > /tmp/ddns.conf
  if ! kea-dhcp-ddns -t /tmp/ddns.conf >/tmp/kea-validation.log 2>&1; then
    cat /tmp/kea-validation.log >&2
    exit 1
  fi
  DNS_ENABLED=false
  unset DDNS_TSIG_KEY
  write_tsig_key
else
  test "$(stat -c %a /var/run/named/kea-ddns.key)" = 600
  test "$(stat -c %U /var/run/named/kea-ddns.key)" = bind
  mkdir -p /usr/local/share/kea/zone-seeds
  cp /tmp/source/dns/zones/db.* /usr/local/share/kea/zone-seeds/
  chmod 755 /usr/local/share/kea/zone-seeds
  chmod 644 /usr/local/share/kea/zone-seeds/db.*
  awk '/^prepare_zone_files\(\) \{/ { copy = 1 } copy { print } copy && /^\}/ { exit }' /tmp/source/dns/entrypoint.sh > /tmp/zone-functions.sh
  . /tmp/zone-functions.sh
  prepare_zone_files
  cp /tmp/source/dns/named.conf /tmp/named.conf
  named-checkconf /tmp/named.conf
  named -n 1 -U 1 -u bind -c /tmp/named.conf -g >/tmp/named.log 2>&1 &
  named_pid=$!
  trap 'result=$?; if [ "$result" -ne 0 ]; then tail -n 30 /tmp/named.log >&2; fi; kill "$named_pid" 2>/dev/null || true; wait "$named_pid" 2>/dev/null || true; exit "$result"' EXIT
  count=0
  until dig @127.0.0.1 example.com SOA +short +tries=1 +time=1 2>/dev/null | grep -Eq "^ns[0-9]*[.]example[.]com[.] "; do
    count=$((count + 1))
    test "$count" -lt 20
    sleep 1
  done
  # Signed reverse updates for addresses inside both sample DHCP pools.
  for family in 4 6; do
    if [ "$family" = 4 ]; then
      address=192.0.2.100
      reverse_zone=2.0.192.in-addr.arpa.
      owner="100.$reverse_zone"
    else
      address=2001:db8:1::1000
      reverse_zone=0.0.0.0.1.0.0.0.8.b.d.0.1.0.0.2.ip6.arpa.
      owner="0.0.0.1.0.0.0.0.0.0.0.0.0.0.0.0.$reverse_zone"
    fi
    printf 'server 127.0.0.1\nzone %s\nupdate add %s 60 PTR tsig-test.example.com.\nsend\n' "$reverse_zone" "$owner" > /tmp/update
    nsupdate -k /var/run/named/kea-ddns.key /tmp/update
    test "$(dig @127.0.0.1 -x "$address" +short)" = tsig-test.example.com.
    printf 'server 127.0.0.1\nzone %s\nupdate delete %s PTR\nsend\n' "$reverse_zone" "$owner" > /tmp/delete
    nsupdate -k /var/run/named/kea-ddns.key /tmp/delete
    test -z "$(dig @127.0.0.1 -x "$address" +short)"
  done
  printf 'server 127.0.0.1\nzone example.com.\nupdate add tsig-test.example.com. 60 A 192.0.2.99\nsend\n' > /tmp/update
  # The publicly shipped key must no longer authorize updates.
  nsupdate -y hmac-sha256:kea-ddns-key:J7eVnYH4rY8gYz4j5A9LxK2pQm7nS3tVw2yB6cD9fG0= /tmp/update >/tmp/old-key.log 2>&1 && exit 1
  nsupdate -k /var/run/named/kea-ddns.key /tmp/update
  test "$(dig @127.0.0.1 tsig-test.example.com A +short)" = 192.0.2.99
  test -s /var/cache/bind/primary/db.example.com.jnl
  rndc sync example.com
  count=0
  until grep -q tsig-test /var/cache/bind/primary/db.example.com; do
    count=$((count + 1))
    test "$count" -lt 20
    sleep 1
  done
  kill "$named_pid"
  wait "$named_pid"
  # Reinitialization must preserve updated zones and any remaining journals.
  prepare_zone_files
  named -n 1 -U 1 -u bind -c /tmp/named.conf -g >/tmp/named.log 2>&1 &
  named_pid=$!
  count=0
  until [ "$(dig @127.0.0.1 tsig-test.example.com A +short +tries=1 +time=1 2>/dev/null)" = 192.0.2.99 ]; do
    count=$((count + 1))
    test "$count" -lt 20
    sleep 1
  done
  grep -q tsig-test /var/cache/bind/primary/db.example.com
  test "$(stat -c %U /var/cache/bind/primary)" = bind
  printf 'server 127.0.0.1\nzone example.com.\nupdate delete tsig-test.example.com. A\nsend\n' > /tmp/delete
  nsupdate -k /var/run/named/kea-ddns.key /tmp/delete
  test -z "$(dig @127.0.0.1 tsig-test.example.com A +short)"
fi
echo "$service TSIG tests passed"
