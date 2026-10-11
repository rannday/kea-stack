#!/bin/sh
set -eu

prepare_zone_files() {
  echo "[entrypoint] preparing BIND runtime directories"
  mkdir -p /var/cache/bind/primary /var/run/named
  chown bind:bind /var/cache/bind /var/run/named
  chmod 750 /var/cache/bind/primary
  for seed in /usr/local/share/kea/zone-seeds/db.*; do
    case "$seed" in *.jnl) continue ;; esac
    [ -f "$seed" ] || continue
    zone="/var/cache/bind/primary/${seed##*/}"
    if [ ! -e "$zone" ]; then
      cp "$seed" "$zone"
      if [ -f "$seed.jnl" ] && [ ! -e "$zone.jnl" ]; then
        cp "$seed.jnl" "$zone.jnl"
      fi
    fi
  done
  chown -R bind:bind /var/cache/bind/primary
  find /var/cache/bind/primary -type f -exec chmod 640 {} \;
}

write_tsig_key() {
  if ! printf '%s\n' "${DDNS_TSIG_KEY:-}" | grep -Eq '^[A-Za-z0-9+/]{43}=$'; then
    echo "[entrypoint] DDNS_TSIG_KEY must be a base64-encoded 32-byte HMAC-SHA256 key" >&2
    exit 1
  fi
  (umask 077
    printf 'key "kea-ddns-key" {\n  algorithm hmac-sha256;\n  secret "%s";\n};\n' "${DDNS_TSIG_KEY}" > /var/run/named/kea-ddns.key
  )
  chown bind:bind /var/run/named/kea-ddns.key
}

validate_config() {
  echo "[entrypoint] validating named configuration"
  named-checkconf -z /etc/bind/named.conf
}

prepare_zone_files
write_tsig_key
validate_config
exec named -u bind -c /etc/bind/named.conf -g
