# Stork deployment

Stork server and agents use ISC's stable 2.4.2 packages. The server is built in `stork/Dockerfile`; agents in `stork/agent.Dockerfile`. Update both package pins together.

These are the only custom images in the stack. Compose uses local names `kea-stack-stork` and `kea-stack-stork-agent` with `pull_policy: build`; no registry image is expected under those names. The one-shot `kea-init` service reuses the agent image for matching Kea schema tools.

`stork-db` runs official PostgreSQL 18.6 independently of the Stork server. Stork initializes its schema on startup. Agents `agent4`, `agent6`, and optional `agent-ddns` share their Kea daemon's PID and network namespaces, allowing process discovery and direct access to its control API. Rendered configuration and API authentication files are shared read-only through each daemon's runtime volume. Each agent has its own persistent identity volume.

Start with `docker compose up -d --build`. Sign in to http://localhost:8080 with `admin` / `admin` and change the password. Add or approve each agent through Stork's Machines page. Each agent uses port 8080 on its daemon's internal address. These agent ports are internal; only the Stork server is published.

Check `docker compose logs stork agent4 agent6` and optional `agent-ddns`. Prometheus scrapes DHCP exporter endpoints at `dhcp4:9547` and `dhcp6:9547`, using the agents' shared network namespaces. The agent image includes matching Kea binaries because Stork executes them with `-v` during discovery. Stork 2.4.2 skips some new Kea 3.2 statistics with warnings; supported metrics remain available. Review [backup planning](backups.md) for the separate Stork database.

With DNS enabled, authorize all three agents and check that DHCPv4, DHCPv6, and DDNS appear under Stork services. Prometheus also scrapes the Stork server and optional BIND exporter; it has no separate DDNS scrape target. Agent registration and healthy metrics do not establish that client leasing or DDNS updates work.
