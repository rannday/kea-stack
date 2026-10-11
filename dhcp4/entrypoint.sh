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
printf '%s\n' "${DHCP4_API_USER:-}" > /run/kea/dhcp4-api-user
printf '%s\n' "${DHCP4_API_PASSWORD:-}" > /run/kea/dhcp4-api-password
DDNS_ADDRESS=""
if [ "$DNS_ACTIVE" = true ]; then
  DDNS_ADDRESS="$(resolve ddns)"
fi
export DDNS_ADDRESS DNS_ACTIVE
awk -f /config/render.awk /etc/kea/kea-dhcp4.conf > /run/kea/kea-dhcp4.conf
kea-dhcp4 -t /run/kea/kea-dhcp4.conf
exec kea-dhcp4 -c /run/kea/kea-dhcp4.conf
