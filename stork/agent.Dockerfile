FROM postgres:18.6-bookworm

ENV DEBIAN_FRONTEND=noninteractive
# Keep server and agent on the same tested stable release.
ARG STORK_AGENT_PACKAGE_VERSION=2.4.2.261002134402
ARG KEA_PACKAGE_VERSION=3.2.1-isc20260928103142

RUN apt-get update && apt-get install -y \
  ca-certificates curl gnupg debian-keyring debian-archive-keyring \
  apt-transport-https procps jq \
  && rm -rf /var/lib/apt/lists/*

RUN curl -1sLf 'https://dl.cloudsmith.io/public/isc/stork/gpg.key' \
  | gpg --dearmor -o /usr/share/keyrings/isc-stork-archive-keyring.gpg \
  && curl -1sLf 'https://dl.cloudsmith.io/public/isc/stork/config.deb.txt?distro=debian&codename=bookworm&component=main' \
  > /etc/apt/sources.list.d/isc-stork.list \
  && chmod 644 /usr/share/keyrings/isc-stork-archive-keyring.gpg /etc/apt/sources.list.d/isc-stork.list \
  && apt-get update && apt-get install -y isc-stork-agent="${STORK_AGENT_PACKAGE_VERSION}" \
  && rm -rf /var/lib/apt/lists/*

RUN mkdir -p /var/lib/stork-agent /usr/lib/stork-agent/hooks && rm -rf /var/lib/stork && ln -s /var/lib/stork-agent /var/lib/stork
# Stork executes each discovered daemon with -v in its own filesystem.
# These matching binaries support discovery; only the official containers run Kea.
RUN curl -1sLf 'https://dl.cloudsmith.io/public/isc/kea-3-2/gpg.key' \
  | gpg --dearmor -o /usr/share/keyrings/isc-kea-3-2-archive-keyring.gpg \
  && curl -1sLf 'https://dl.cloudsmith.io/public/isc/kea-3-2/config.deb.txt?distro=debian&codename=bookworm&component=main' \
  > /etc/apt/sources.list.d/isc-kea-3-2.list \
  && chmod 644 /usr/share/keyrings/isc-kea-3-2-archive-keyring.gpg /etc/apt/sources.list.d/isc-kea-3-2.list \
  && apt-get update && apt-get install -y \
    isc-kea-dhcp4="${KEA_PACKAGE_VERSION}" isc-kea-dhcp6="${KEA_PACKAGE_VERSION}" \
    isc-kea-dhcp-ddns="${KEA_PACKAGE_VERSION}" isc-kea-admin="${KEA_PACKAGE_VERSION}" \
  && rm -rf /var/lib/apt/lists/*
COPY --chmod=755 agent-entrypoint.sh /usr/local/bin/entrypoint.sh
ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]
