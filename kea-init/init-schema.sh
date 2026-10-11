#!/bin/sh
set -eu
if [ "$#" -gt 0 ]; then exec "$@"; fi
sh /usr/local/bin/kea-schema.sh init lease
sh /usr/local/bin/kea-schema.sh init shared
