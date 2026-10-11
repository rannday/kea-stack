#!/bin/sh
set -eu

SOURCE_CONFIG=/etc/prometheus/prometheus.yml
RUNTIME_CONFIG=/tmp/prometheus.yml
DNS_PROFILES="${DNS_ENABLED:-}"

case ",${DNS_PROFILES}," in
  *,dns,*) cp "${SOURCE_CONFIG}" "${RUNTIME_CONFIG}" ;;
  *)
    # Buffer each scrape item so job_name need not be its first field.
    awk '
      function flush_item() {
        if (!omit_bind) printf "%s", item
        item = ""
        omit_bind = 0
      }
      /^scrape_configs:[[:space:]]*($|#)/ {
        in_scrapes = 1
        item_indent = -1
        print
        next
      }
      in_scrapes && /^[^[:space:]#-]/ {
        flush_item()
        in_scrapes = 0
      }
      in_scrapes && /^[[:space:]]*-[[:space:]]/ {
        match($0, /[^[:space:]]/)
        indent = RSTART - 1
        if (item_indent < 0) item_indent = indent
        if (indent == item_indent) {
          flush_item()
          match($0, /^[[:space:]]*-[[:space:]]+/)
          field_indent = RLENGTH
        }
      }
      in_scrapes && item_indent >= 0 {
        item = item $0 "\n"
        if ($0 ~ /^[[:space:]]*(-[[:space:]]+)?job_name:[[:space:]]*/) {
          match($0, /[^[:space:]]/)
          indent = RSTART - 1
          if (indent != item_indent && indent != field_indent) next
          name = $0
          sub(/^[[:space:]]*(-[[:space:]]+)?job_name:[[:space:]]*/, "", name)
          sub(/[[:space:]]+#.*$/, "", name)
          sub(/[[:space:]]+$/, "", name)
          if (name ~ /^(bind|"bind"|\047bind\047)$/) omit_bind = 1
        }
        next
      }
      { print }
      END { flush_item() }
    ' "${SOURCE_CONFIG}" > "${RUNTIME_CONFIG}"
    ;;
esac

exec /bin/prometheus \
  --config.file="${RUNTIME_CONFIG}" \
  --storage.tsdb.path=/prometheus
