#!/bin/sh
set -eu

# Let BIND resolve includes and zone types rather than parsing named.conf.
configured_zones="$(named-checkconf -l /etc/bind/named.conf)"
primary_zones="$(printf '%s\n' "${configured_zones}" |
  awk '$2 == "IN" && ($4 == "primary" || $4 == "master") { print $1 }')"
if [ -z "${primary_zones}" ]; then
  echo "[healthcheck] no primary IN zones configured" >&2
  exit 1
fi

while IFS= read -r zone; do
  answer="$(dig @127.0.0.1 "${zone}" SOA +norecurse +time=1 +tries=1 \
    +noall +comments +answer)"
  if ! printf '%s\n' "${answer}" | awk -v zone="${zone}" '
    BEGIN {
      zone = tolower(zone)
      if (zone !~ /\.$/) zone = zone "."
    }
    /^;; ->>HEADER<<-/ && /status: NOERROR,/ { success = 1 }
    /^;; flags:/ && /[ ;]aa[ ;]/ { authoritative = 1 }
    tolower($1) == zone && $3 == "IN" && $4 == "SOA" { soa = 1 }
    END { exit !(success && authoritative && soa) }
  '; then
    echo "[healthcheck] missing authoritative SOA answer for ${zone}" >&2
    exit 1
  fi
done <<EOF
${primary_zones}
EOF
