# Kea Stack

A single-server Kea DHCPv4 and DHCPv6 stack with PostgreSQL, Stork, Prometheus, and Grafana. BIND DNS is optional.

## Start the stack

1. Install Docker Desktop with Docker Compose.
2. Copy `.env.example` to `.env`.
3. Edit `.env`: replace the example passwords. Published ports bind to all host interfaces by default; set a service-specific `*_BIND_ADDRESS` value to bind a service to a specific host address. Docker assigns the containers' internal addresses.
4. Review [Kea deployment notes](docs/kea.md) before starting.
5. Start the services:

   ```powershell
   docker compose up -d --build
   ```

6. Sign in to Stork at http://localhost:8080 using `admin` / `admin` and immediately change the default password as your first action.

DNS is disabled by default. To enable it, set `COMPOSE_PROFILES=dns`.

Check service status with `docker compose ps` and logs with `docker compose logs -f`.

`kea-init` is a one-shot schema initializer; exiting successfully is expected. Authorize the DHCP agents in Stork as described in [Stork deployment](docs/stork.md).

## Images and services

Compose runs ISC's Cloudsmith Kea 3.2.1, PostgreSQL 18.6, Grafana 13.2.3, Prometheus 3.15.0, and ISC BIND 9.20 images directly. Configuration, startup scripts, and data volumes are mounted. BIND metrics use the published Prometheus community exporter.

Only Stork server and agents need custom images, using ISC's stable 2.4.2 packages. The agent image also supplies the one-shot Kea schema initializer. `shared-db` holds reservations and legal logs; `db-backups` schedules database dumps and log retention without requiring a PostgreSQL extension.

| Services | Image source | Configuration / scripts |
| --- | --- | --- |
| `dhcp4`, `dhcp6`, optional `ddns` | ISC Cloudsmith Kea | `dhcp4/`, `dhcp6/`, `ddns/` |
| `lease-db`, `shared-db`, `stork-db` | Official PostgreSQL | Initialization script in `shared-db/` |
| `stork`, `agent4`, `agent6`, optional `agent-ddns`, `kea-init` | Local Stork builds | `stork/`; schema scripts in `kea-init/` |
| Optional `dns`, `bind-exporter` | ISC BIND / Prometheus community exporter | `dns/` |
| `prometheus`, `grafana` | Upstream published images | `prometheus/`, `grafana/` |
| `db-backups` | Official PostgreSQL client tools | `db-backups/` |

The local Stork images use `pull_policy: build`; Compose builds them locally instead of trying to pull their project-specific image names from a registry. Release tags are defined in `compose.yaml`.

Use explicit release tags to control when releases change. Update tags deliberately and test the stack together.

## Edit service configuration

Compose mounts configuration and startup scripts from this repository. Recreate containers to apply changes to these inputs:

- Kea configuration, entrypoints, renderers, and healthchecks in `dhcp4/`, `dhcp6/`, and `ddns/`; schema initialization in `kea-init/`
- BIND configuration in `dns/named.conf`; `dns/zones/` supplies initial zone seeds
- Shared PostgreSQL initialization in `shared-db/`
- Database backup scripts in `db-backups/`
- Prometheus configuration in `prometheus/prometheus.yml`
- Grafana configuration, provisioning, and dashboards in `grafana/`

After editing, recreate the stack to load the changes:

```powershell
docker compose up -d --force-recreate
```

This preserves named volumes, including database contents and application state. Do not add `--volumes` when refreshing configuration.

PostgreSQL initialization scripts run only when a database volume is empty; recreating an initialized database does not rerun them. Changes to Stork Dockerfiles or scripts copied into its images require `docker compose up -d --build --force-recreate`. See [Docker commands](docs/docker.md).

View service logs with `docker compose logs -f <service>`.

## Use DNS (optional)

Set `COMPOSE_PROFILES=dns` in `.env` to enable BIND. Edit BIND configuration in `dns/named.conf`, then use the service configuration refresh steps above to load changes.

Zone files in `dns/zones/` are read-only seeds. Startup copies missing zone files into BIND-owned storage at `/var/cache/bind/primary` in the `dns` named volume. Existing zones and DDNS journals survive restarts and container recreation; editing a seed does not overwrite an existing zone. Configure seeds before first startup and use authenticated DNS updates for records in existing zones. Preserve the `dns` volume.

BIND9 uses host TCP and UDP port 53 by default. If another service already uses port 53, set `BIND9_BIND_PORT` to an available host port such as 5353 or 1053 for testing. DNS clients normally expect port 53.

Set `DDNS_TSIG_KEY` in `.env` before enabling DNS:

```dotenv
# Replace this example with your own base64-encoded 32 random bytes for HMAC-SHA256.
DDNS_TSIG_KEY="IV9IaFqx+/uZi6CfHvTRudMRM22lVrO3QjAjsYrOkhw="
```

Generate a unique value without installing host tools, using ISC's image:

```powershell
docker run --rm --entrypoint sh docker.cloudsmith.io/isc/docker/kea-dhcp4:3.2.1-20260930 -c "head -c 32 /dev/urandom | base64"
```

Keep the generated value private. BIND and Kea DDNS receive the same key through Compose and write private runtime key files; no deployment key is baked into either image. DNS-disabled startup does not require the key. To rotate it, replace the value and recreate the stack together. Mounted startup-script changes need container recreation; only Stork image changes require rebuilding.

To turn DNS off after it has been enabled, clear `COMPOSE_PROFILES` and recreate the stack so Compose removes the DNS service and refreshes the DNS-dependent configuration:

```powershell
docker compose up -d --remove-orphans --force-recreate
```

## Update DNS records with nsupdate

Use `nsupdate` to change records in an existing dynamic zone. BIND manages its journal and SOA serial; changes persist in the `dns` volume without restarting containers. Editing files in `dns/zones/` after initialization does not change the active zone. Creating a new zone still requires configuration in `dns/named.conf` and an initial zone file.

From a machine outside Docker, enable the DNS profile and use the Docker host address reachable from that machine. `BIND9_BIND_ADDRESS` must listen on that interface, and the firewall must allow the published `BIND9_BIND_PORT` over TCP and UDP. Install BIND client tools containing `nsupdate` and `dig` on that machine if needed.

Create a private file named `kea-ddns.key` outside this checkout:

```text
key "kea-ddns-key" {
  algorithm hmac-sha256;
  secret "REPLACE_WITH_YOUR_DDNS_TSIG_KEY_VALUE";
};
```

Replace the placeholder with the exact deployment value of `DDNS_TSIG_KEY`. Keep the key name and algorithm as shown. Restrict access to your account (`chmod 600 kea-ddns.key` on Linux/macOS; equivalent file permissions on Windows). Never commit or share the key file. This key authorizes updates to all configured dynamic zones. Using `-k` avoids putting the secret in command-line arguments.

Start an interactive session:

```sh
nsupdate -k /path/to/kea-ddns.key
```

Enter the following commands to add a record. Replace `192.0.2.10` with the Docker host address, `53` with `BIND9_BIND_PORT`, and the zone, hostname, and record address with your values. These examples use the supplied `example.com` zone and a TTL of 300 seconds. The `>` character is the prompt; do not type it.

```text
> server 192.0.2.10 53
> zone example.com.
> update add printer.example.com. 300 A 192.0.2.50
> send
```

To replace that hostname’s A records, delete the existing A record set and add its replacement in the same request:

```text
> update delete printer.example.com. A
> update add printer.example.com. 300 A 192.0.2.51
> send
```

To delete only that specific address and finish:

```text
> update delete printer.example.com. A 192.0.2.51
> send
> quit
```

Each `send` submits the preceding changes. Successful updates normally produce no output. Verify additions or replacements by querying BIND directly:

```sh
dig @192.0.2.10 -p 53 printer.example.com. A +short
```

Use `AAAA` for IPv6 address records. Forward records and reverse `PTR` records are separate updates; adding an A or AAAA record does not automatically create a PTR record. Reserve manual records for names and addresses outside Kea-managed allocations so later DHCP updates do not change or remove them.

For failures, check `docker compose logs dns`: `NOTAUTH`/TSIG errors can indicate the wrong key or clock skew, `REFUSED` can indicate update authorization failure, and `NOTZONE` can indicate a name outside the selected zone. Connection timeouts require checking the host address, published port, firewall, and DNS service status. See the [official BIND nsupdate manual](https://bind9.readthedocs.io/en/v9.20.0/manpages.html#nsupdate-dynamic-dns-update-utility) for command details.

## Web interfaces

- Stork: http://localhost:8080
- Grafana: http://localhost:3000
- Prometheus: http://localhost:9090

Stork's initial login is `admin` / `admin`. **Change the default password immediately on your first login, before using Stork.** Use the credentials configured in `.env` for Grafana.

Dashboard access, agent authorization, and healthy Prometheus targets confirm startup and monitoring. They do not prove client leasing, renewal, or DHCP-driven DNS updates; test those separately on a representative network.

## Backups

Database dumps are written to the `backups` Docker volume. Review [backup scheduling and copying backups off the host](docs/backups.md) before relying on the volume as your only copy.

## Stop and remove

Stop and remove the containers and project network while keeping data volumes:

```powershell
docker compose down
```

To remove this stack's containers, images, network, and volumes, see [Docker cleanup](docs/docker.md). Removing volumes permanently deletes the stack's stored data.

For Windows host firewall rules, see [Windows firewall setup](docs/windows-firewall.md).
