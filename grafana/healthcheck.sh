#!/bin/sh
set -eu
curl -fsL http://127.0.0.1:3000/api/health >/dev/null
