# Docker commands

Run commands from the repository root so Compose uses this project's `compose.yaml` and `.env`.

## Routine start and stop

Start services, pulling upstream images when absent and building the local Stork images:

```powershell
docker compose up -d --build
```

Stop and remove containers and this Compose project's network while keeping named volumes and images:

```powershell
docker compose down
```

The development shortcuts do the same:

- `scripts/ps/up.ps1`: `docker compose up -d`
- `scripts/ps/down.ps1`: `docker compose down`

Only `stork/Dockerfile` and `stork/agent.Dockerfile` are built locally. `kea-init` and the three agents share the agent image. Their `pull_policy: build` also makes ordinary `docker compose up -d` check the local builds. All other services use published images directly, with release tags in `compose.yaml`.

`kea-init` exiting with code 0 is normal: it prepares and checks the Kea schemas before the daemons start. Inspect service status with `docker compose ps -a`.

## Refresh service configuration

Kea, BIND, Prometheus, Grafana, and backup configuration or startup scripts are bind-mounted from the repository. After editing them, recreate the containers so each service reads the current files:

```powershell
docker compose up -d --force-recreate
```

This keeps named volumes and their data. BIND's `dns/zones/` directory is mounted read-only at `/usr/local/share/kea/zone-seeds`. Startup copies missing seeds into `/var/cache/bind/primary` in the persistent `dns` volume. Editing a seed does not replace an active zone or its journal. Do not use `--volumes` to refresh configuration.

Changes to the Stork Dockerfiles or their copied scripts require rebuilding and recreation with `docker compose up -d --build --force-recreate`.

All three PostgreSQL services mount `shared-db/init-app.sh` into their initialization directory. It runs only on an empty data volume. Changes to this script or database initialization credentials do not modify an already initialized database through container recreation.

The `dns` profile includes BIND, DDNS, its agent, and the BIND exporter. After clearing `COMPOSE_PROFILES` to disable DNS, use `docker compose up -d --remove-orphans --force-recreate` to remove those containers and refresh dependent configuration.

## Remove this stack's data and images

`docker compose down` preserves named volumes. To remove the containers, project network, volumes, and images for all services, including the optional DNS service, run:

```powershell
docker compose --profile dns down --volumes --rmi all --remove-orphans
```

The `scripts/ps/full-down.ps1` script runs that Compose cleanup from the repository root and removes this repository's `.logs/` directory. It preserves Buildx build history and build cache.

Both full-down operations permanently delete database and application data in the removed volumes. Copy backups out of the volume first if you need to keep them; see [backups](backups.md).

## Docker-wide cleanup

`scripts/ps/cleanup.ps1` is intentionally broader than this stack. After confirmation by typing uppercase `Y`, it removes all Docker containers and images, deletes all build history for the selected Buildx builder, prunes that builder's cache, removes unused volumes, and removes unused networks. Build history and cache cleanup include other projects using that builder. Do not run it unless you intend to clean up Docker resources beyond this repository.

The equivalent commands are:

```powershell
docker ps -aq | ForEach-Object { docker rm -f $_ }
docker image ls -aq | Sort-Object -Unique | ForEach-Object { docker image rm -f $_ }
docker buildx history rm --all
docker buildx prune --all --force
docker volume prune --all --force
docker network prune --force
```

Docker Desktop's **Builds** history is distinct from images and cache. `full-down.ps1` leaves build history intact. `cleanup.ps1` removes all history records, including build logs, for the selected Buildx builder; it does not filter records by repository.
