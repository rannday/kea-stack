FROM debian:bookworm

ENV DEBIAN_FRONTEND=noninteractive
# Keep server and agent on the same tested stable release.
ARG STORK_SERVER_PACKAGE_VERSION=2.4.2.261002134447

RUN apt-get update && apt-get install -y \
  ca-certificates curl gnupg debian-keyring debian-archive-keyring \
  apt-transport-https procps \
  && rm -rf /var/lib/apt/lists/*

RUN curl -1sLf 'https://dl.cloudsmith.io/public/isc/stork/gpg.key' \
  | gpg --dearmor -o /usr/share/keyrings/isc-stork-archive-keyring.gpg \
  && curl -1sLf 'https://dl.cloudsmith.io/public/isc/stork/config.deb.txt?distro=debian&codename=bookworm&component=main' \
  > /etc/apt/sources.list.d/isc-stork.list \
  && chmod 644 /usr/share/keyrings/isc-stork-archive-keyring.gpg /etc/apt/sources.list.d/isc-stork.list \
  && apt-get update && apt-get install -y isc-stork-server="${STORK_SERVER_PACKAGE_VERSION}" \
  && rm -rf /var/lib/apt/lists/*

RUN mkdir -p /etc/stork /var/lib/stork /var/lib/postgresql /var/log/stork /var/run/postgresql
COPY --chmod=755 healthcheck.sh /usr/local/bin/healthcheck.sh
COPY --chmod=755 entrypoint.sh /usr/local/bin/entrypoint.sh
ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]
