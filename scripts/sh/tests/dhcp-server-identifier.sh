#!/bin/sh
# Run only in a disposable DHCP image with dhcp4/ mounted read-only at /source.
set -eu
awk '/^# Main entrypoint/ { exit } { print }' /source/entrypoint.sh > /tmp/functions.sh
. /tmp/functions.sh
DHCP4_API_USER=fixture
DHCP4_API_PASSWORD=fixture-password
DHCP4_SOURCE_FILE=/tmp/dhcp4-source.conf
DHCP6_SOURCE_FILE=/source/kea-dhcp6.conf
DDNS_SOURCE_FILE=/source/kea-dhcp-ddns.conf
# A user-edited identifier must survive runtime rendering unchanged.
jq '(.Dhcp4."option-data"[] | select(.name == "dhcp-server-identifier").data) = "192.168.1.20"' /source/kea-dhcp4.conf > "$DHCP4_SOURCE_FILE"
getent() { printf '127.0.0.1 STREAM fixture\n'; }
for DNS_ENABLED in false true; do
  DDNS_TSIG_KEY="$(head -c 32 /dev/urandom | base64)"
  render_configs
  jq -e '.Dhcp4."option-data" | [.[] | select(.name == "dhcp-server-identifier" or .code == 54)] | length == 1 and .[0].data == "192.168.1.20"' "$DHCP4_FILE" >/dev/null
  jq -e --slurpfile original "$DHCP4_SOURCE_FILE" '.Dhcp4."option-data" == $original[0].Dhcp4."option-data"' "$DHCP4_FILE" >/dev/null
  jq -e --slurpfile original /source/kea-dhcp6.conf '.Dhcp6."option-data" == $original[0].Dhcp6."option-data"' "$DHCP6_FILE" >/dev/null
  if ! kea-dhcp4 -t "$DHCP4_FILE" >/tmp/validation.log 2>&1; then
    cat /tmp/validation.log >&2
    exit 1
  fi
done
echo 'User-configured DHCPv4 server identifier preserved and parsed in both DNS modes'
