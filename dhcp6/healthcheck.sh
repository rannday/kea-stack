#!/bin/sh
set -eu
port=8001
user="$DHCP6_API_USER"
password="$DHCP6_API_PASSWORD"
address="$(getent ahostsv4 "$(hostname)" | awk 'NR == 1 { print $1 }')"
auth="$(printf '%s' "$user:$password" | base64 | tr -d '\n')"
wget -q -O - --header "Authorization: Basic $auth" --header 'Content-Type: application/json' --post-data '{"command":"status-get"}' "http://$address:$port/" | grep -Eq '"result"[[:space:]]*:[[:space:]]*0'
