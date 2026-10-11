#!/bin/sh
set -eu
umask 077
resolve() {
  attempts=0
  while :; do
    address="$(getent ahostsv4 "$1" | awk 'NR == 1 { print $1 }')"
    [ -z "$address" ] || { printf '%s\n' "$address"; return; }
    attempts=$((attempts + 1))
    [ "$attempts" -lt 60 ] || { echo "Cannot resolve $1" >&2; return 1; }
    sleep 1
  done
}
KEA_CONTROL_ADDRESS="$(resolve "$(hostname)")"
export KEA_CONTROL_ADDRESS
DNS_ACTIVE=false
case ",${DNS_ENABLED:-}," in *,dns,*) DNS_ACTIVE=true ;; esac
mkdir -p /run/kea /var/log/kea /var/lib/kea

# Stork discovers this daemon's authentication files beside its configuration.
printf '%s\n' "${DDNS_API_USER:-}" > /run/kea/ddns-api-user
printf '%s\n' "${DDNS_API_PASSWORD:-}" > /run/kea/ddns-api-password
DNS_ADDRESS=""
if [ "$DNS_ACTIVE" = true ]; then
  DNS_ADDRESS="$(resolve dns)"
  printf '%s\n' "${DDNS_TSIG_KEY:-}" | grep -Eq '^[A-Za-z0-9+/]{43}=$' || { echo "Invalid DDNS_TSIG_KEY" >&2; exit 1; }
  printf '%s\n' "$DDNS_TSIG_KEY" > /run/kea/kea-ddns.key
fi
export DNS_ADDRESS DNS_ACTIVE
awk -f /config/render.awk /etc/kea/kea-dhcp-ddns.conf > /run/kea/kea-dhcp-ddns.conf
kea-dhcp-ddns -t /run/kea/kea-dhcp-ddns.conf
exec kea-dhcp-ddns -c /run/kea/kea-dhcp-ddns.conf
