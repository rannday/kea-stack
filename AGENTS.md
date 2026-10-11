# Repository guidance

## Scope

This repository defines one Kea DHCP server with DHCPv4 and DHCPv6. DNS is optional. Do not add an HA peer or second DNS server here; those belong in the separate HA stack.

Keep service configuration in Compose, Docker build contexts, and mounted configuration files. Keep user-facing setup instructions in `README.md`; operational backup, cleanup, and Windows firewall details belong in `docs/`.

## Service layout

- `dhcp4`, `dhcp6`, `ddns`: separate official Kea images; DDNS uses the `dns` profile.
- `lease-db`: PostgreSQL for leases; `kea-init` initializes and checks Kea schemas.
- `shared-db`: official PostgreSQL for shared reservations and legal logging.
- `stork`, `stork-db`: separate Stork server and database.
- `agent4`, `agent6`, `agent-ddns`: agents sharing their daemon's PID and network namespaces.
- `bind-exporter`: optional DNS metrics sidecar.
- `prometheus`, `grafana`: separate monitoring services.
- `db-backups`: scheduled dumps of the Kea lease, shared, and Stork databases into a Docker volume.
- `dns`: optional BIND server, enabled by the Compose `dns` profile.

The DHCP services use a dedicated lease database. The separate shared database stores reservations and legal logging and remains shared by a future HA pair. Do not merge these database roles.

## Image ownership

Use upstream images directly for Kea, PostgreSQL, BIND, Prometheus, Grafana, and the BIND exporter. Keep their configuration and startup scripts mounted rather than adding Dockerfiles. `db-backups` uses PostgreSQL client tools, not a running database server.

Only Stork server and agent images are built locally from `stork/`. Preserve `pull_policy: build` and the shared agent build definition for `kea-init`, `agent4`, `agent6`, and `agent-ddns`, so Compose does not pull local image names from a registry. Use explicit release tags; update Kea daemon tags, the agent image's Kea admin packages, and the expected schema together.

## DNS profile behavior

The `dns` profile enables `dns`, `ddns`, `agent-ddns`, and `bind-exporter`. DNS is disabled by default; users opt in by setting `COMPOSE_PROFILES=dns`.

The DHCP entrypoint removes DNS/DDNS integration when the profile is absent while preserving user-configured DHCP `option-data`. Prometheus omits the BIND scrape target, and Grafana omits the BIND dashboard. Keep those runtime behaviors aligned when changing DNS configuration.

## Configuration and persistence

- DHCP user configuration: `dhcp4/`, `dhcp6/`, and `ddns/`; mounted read-only into the containers. Each directory owns its entrypoint, renderer, and daemon-specific healthcheck. Schema initialization scripts live in `kea-init/`. Advertised DNS resolver options belong in the DHCP configuration, not `.env`.
- BIND configuration and initial zone seeds: `dns/`; mounted read-only into the container. Writable zones and journals live in the `dns` named volume and are preserved on startup.
- PostgreSQL application-role initialization: `shared-db/init-app.sh`, mounted into all three database services. It runs only on empty database volumes; recreating containers does not rerun initialization.
- Backup scripts: `db-backups/`. Stork build inputs: `stork/`; copied scripts require an image rebuild, while mounted scripts require container recreation.
- Secrets and host-specific values come from `.env`; never commit a real `.env`.
- `.env.example` is an editable public template. Keep its variable names aligned with Compose, use only example values, and document which values users must replace. Real `.env` files and secret-bearing variants remain protected.
- Named volumes hold database and application state. Backups are files in the backups volume, not a database service.
- Volume names need not match service names: `dhcp` stores `lease-db` data, `database` stores `shared-db` data, `stork_db` stores `stork-db` data, and `backups` stores dumps from `db-backups`. Keep these roles distinct from the per-daemon runtime and agent identity volumes.
- Published host addresses use DHCP4_BIND_ADDRESS (default 0.0.0.0), DHCP6_BIND_ADDRESS (default ::), DHCP4_CTRL_BIND_ADDRESS, DHCP6_CTRL_BIND_ADDRESS, DDNS_CTRL_BIND_ADDRESS, BIND9_BIND_ADDRESS, STORK_BIND_ADDRESS, PROMETHEUS_BIND_ADDRESS, and GRAFANA_BIND_ADDRESS (the latter seven default to 0.0.0.0). BIND9_BIND_PORT selects the optional DNS host port and defaults to 53.

## Network and published ports

The stack uses a user-defined dual-stack bridge network. Docker allocates the network subnets and container addresses; services use Compose DNS names internally. Do not hardcode container IPs or configure the stack's Docker subnet in `.env`.

Host ports: UDP 67 and 547 for DHCP relays; TCP 8100–8102 for Kea control APIs; TCP 8080 for Stork; TCP 9090 for Prometheus; TCP 3000 for Grafana. Optional DNS maps host TCP and UDP port BIND9_BIND_PORT (default 53) to container port 53. Details and Windows firewall commands are in `docs/windows-firewall.md`.

Publishing DHCP ports does not forward raw client broadcasts or link-local DHCPv6 multicast into the bridge network. Use DHCP relays for this deployment.

## Validation

Check Compose with DNS disabled and enabled, using the public `.env.example` rather than reading deployment secrets. `kea-init` must exit successfully before Kea starts. Verify daemon health, Stork agent discovery/authorization, and Prometheus targets separately from client leasing, renewal, and DDNS behavior. Do not claim functional DHCP/DDNS validation from healthy containers or dashboards alone.

## Development scripts

PowerShell helpers live in `scripts/ps/` with tests in `scripts/ps/tests/`; POSIX shell scripts live in `scripts/sh/` with tests in `scripts/sh/tests/`. The official-image test Compose override lives beside its PowerShell runner in `scripts/ps/tests/compose.official.yaml`.

- `scripts/ps/up.ps1`: start the stack with Compose.
- `scripts/ps/down.ps1`: remove containers and the project network while retaining named volumes.
- `scripts/ps/full-down.ps1`: remove this Compose project's containers, images, network, and volumes, plus local logs. Buildx build history and cache are preserved.
- `scripts/ps/cleanup.ps1`: Docker-wide destructive cleanup, including all build history and cache for the selected Buildx builder. Builder cleanup includes other projects using that builder. It requires confirmation by typing uppercase `Y`.

Do not run destructive cleanup or remove volumes unless the user explicitly requests it.
