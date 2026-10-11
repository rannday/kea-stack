#!/bin/sh
set -eu

case ",${DNS_ENABLED:-}," in
  *,dns,*) dns_enabled=true ;;
  *) dns_enabled=false ;;
esac

mkdir -p /var/lib/grafana/dashboards /var/lib/grafana/plugins
cp /usr/local/share/grafana/dashboards/kea-stork-overview.json /var/lib/grafana/dashboards/
if [ "${dns_enabled}" = true ]; then
  cp /usr/local/share/grafana/dashboards/bind-overview.json /var/lib/grafana/dashboards/
else
  rm -f /var/lib/grafana/dashboards/bind-overview.json
fi
exec /run.sh
