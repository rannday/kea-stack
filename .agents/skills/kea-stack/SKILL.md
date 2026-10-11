---
name: kea-stack
description: Change or troubleshoot this repository's Kea DHCP Compose deployment, optional DNS, databases, monitoring, and backups.
---

# Kea Stack

Use this skill when changing or troubleshooting this repository's Compose deployment.

## Architecture

This is one Kea DHCP server with DHCPv4 and DHCPv6. DNS is optional. The HA pair and second BIND server belong in a separate stack.

- `dhcp4`, `dhcp6`, optional `ddns`: separate ISC Cloudsmith Kea images.
- `lease-db`: official PostgreSQL for leases; `kea-init` initializes and checks Kea schemas before daemons start.
- `shared-db`: official PostgreSQL for host reservations and legal logging.
- `stork`, `stork-db`: separate Stork server and official PostgreSQL database.
- `agent4`, `agent6`, optional `agent-ddns`: Stork agents sharing their daemon's PID and network namespaces, with read-only runtime configuration and separate persistent identities.
- `prometheus` and `grafana`: separate monitoring containers.
- `db-backups`: official PostgreSQL client tools running mounted backup and legal-log retention scripts; dumps live under `/var/lib/kea-backups` in the `backups` volume. No database server runs here.
- `dns`, `bind-exporter`: optional ISC BIND and Prometheus community exporter under the `dns` Compose profile.

Keep leases separate from reservations and legal logging. A future HA pair shares the reservations/logging database while synchronizing leases through Kea's HA functionality.

## Images and schema tools

Use published upstream images directly with mounted configuration and scripts. Only Stork server and agent images need custom builds, in `stork/Dockerfile` and `stork/agent.Dockerfile`. Preserve `pull_policy: build` and the shared agent build definition for `kea-init` and all agents; their local image names must not be pulled from a registry.

Use explicit release tags in `compose.yaml`. Update Kea daemon tags, the agent image's Kea admin packages, and the expected schema in `kea-init/kea-schema.sh` together. `kea-init` is a one-shot service: exiting with code 0 is expected. Stork initializes its own schema against `stork-db`.

## DNS is profile-controlled

DNS is disabled by default. Set `COMPOSE_PROFILES=dns` to enable `dns`, `ddns`, `agent-ddns`, and `bind-exporter`. The same profile selection controls the DHCP DDNS hooks and options, Prometheus BIND scrape target, and Grafana BIND dashboard. When DNS is disabled, preserve user-configured DHCP `option-data` while removing DNS/DDNS integration. Preserve this coordinated behavior when editing entrypoints or configuration templates.

## Configuration paths

- Kea configuration: `dhcp4/kea-dhcp4.conf`, `dhcp6/kea-dhcp6.conf`, and `ddns/kea-dhcp-ddns.conf`. Each daemon directory owns its renderer, entrypoint, and healthcheck; schema scripts live in `kea-init/`. Advertised resolver options belong in the DHCP files, not `.env`. Edit source templates, not generated `/run/kea/` files.
- BIND configuration and initial zone seeds: `dns/named.conf` and `dns/zones/`. Seeds are mounted read-only and copied only when absent into BIND-owned `/var/cache/bind/primary` in the `dns` volume. Existing zones and journals survive startup; seed edits do not replace existing zones.
- PostgreSQL application-role initialization: `shared-db/init-app.sh`, mounted into all three database services. Initialization scripts run only when the data volume is empty; container recreation does not rerun them.
- Backup scripts: `db-backups/`. Stork build inputs: `stork/`.
- Monitoring configuration: `prometheus/prometheus.yml` and Grafana files under `grafana/`.
- Credentials and host values come from `.env`. Never read or edit real `.env` files, secret-bearing variants, or PEM files. The public `.env.example` may be read and edited with example values only; request a redacted example when needed.

After editing mounted configuration or startup scripts, use `docker compose up -d --force-recreate`; named volumes persist. Do not add `--volumes` for a configuration refresh. Stork Dockerfile changes or changes to scripts copied into its images need `docker compose up -d --build --force-recreate`. When disabling DNS, clear `COMPOSE_PROFILES` and include `--remove-orphans` to remove profile services. Read service logs using `docker compose logs -f <service>`.

## Networking

Use Compose service names for internal traffic. Docker allocates network subnets and container addresses; do not hardcode these or expose them as user configuration. Published host addresses use DHCP4_BIND_ADDRESS (default 0.0.0.0), DHCP6_BIND_ADDRESS (default ::), DHCP4_CTRL_BIND_ADDRESS, DHCP6_CTRL_BIND_ADDRESS, DDNS_CTRL_BIND_ADDRESS, BIND9_BIND_ADDRESS, STORK_BIND_ADDRESS, PROMETHEUS_BIND_ADDRESS, and GRAFANA_BIND_ADDRESS (the latter seven default to 0.0.0.0). BIND9_BIND_PORT selects the optional DNS host port and defaults to 53.

Published host ports are DHCP relay UDP 67/547, Kea API TCP 8100–8102, Stork TCP 8080, Prometheus TCP 9090, Grafana TCP 3000, and optional DNS TCP/UDP on host port `BIND9_BIND_PORT` (default 53), mapped to container port 53. Refer to `docs/windows-firewall.md` for Windows firewall examples.

Docker bridge port publishing does not forward raw Layer 2 DHCP broadcasts or link-local DHCPv6 multicast. Use DHCP relays for this deployment. Stork agents, exporters, and PostgreSQL ports remain internal; do not add host publications for discovery or monitoring.

## Data and cleanup

Named volumes contain persistent databases and application state. Backup files are written to the backups volume; users must copy them elsewhere for independent protection. See `docs/backups.md`.

Database volume names differ from service names: `dhcp` stores lease data, `database` stores shared reservation/legal-log data, and `stork_db` stores Stork data. `dhcp_state` preserves the DHCPv6 DUID. Keep daemon runtime and agent identity volumes separate.

Use `docker compose down` for routine shutdown while preserving volumes. Full cleanup removes data; explain that clearly before recommending it. See `docs/docker.md`.

## Validation

Validate Compose with DNS disabled and enabled, using the public `.env.example` and example values. Check successful `kea-init` completion, daemon health, and authorization of `agent4`, `agent6`, and optional `agent-ddns` in Stork. Prometheus scrapes DHCPv4, DHCPv6, Stork, and optional BIND metrics; there is no separate DDNS scrape target.

Healthy containers, dashboards, and metrics prove startup and monitoring only. Report client leasing, renewal, and DHCP-driven DNS updates separately; do not claim those tests ran when they were deferred. Keep changes within the requested scope and never run destructive cleanup without explicit authorization.
## Host scripts

PowerShell helpers live in `scripts/ps/`: `up.ps1` starts the stack, `down.ps1` retains volumes, and `full-up.ps1` rebuilds and recreates containers. Destructive cleanup helpers are documented in `docs/docker.md`. POSIX shell scripts live in `scripts/sh/`. Keep tests under each language directory's `tests/` subdirectory; the official-image test Compose override lives in `scripts/ps/tests/compose.official.yaml`.
