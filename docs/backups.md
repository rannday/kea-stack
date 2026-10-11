# Database backups

The `db-backups` service writes PostgreSQL custom-format dumps to the
`kea-stack_backups` Docker volume (prefixed by the Compose project name).

It runs the official PostgreSQL image's client tools with mounted scripts from `db-backups/`; it does not start a PostgreSQL server. Database servers run separately as `lease-db`, `shared-db`, and `stork-db`.

It dumps the three databases independently:

| Database | Volume directory | Default schedule | Default retention |
| --- | --- | --- | --- |
| Kea leases | `leases/` | Every 3 hours | 1 day |
| Kea reservations and legal logging | `shared/` | Every 3 hours | 1 day |
| Stork | `stork/` | Every 24 hours | 3 days |

The same service deletes up to 10,000 legal-log rows older than two years each
hour and vacuums that table daily after 03:10 UTC. It uses the application's
database role; no PostgreSQL extension or custom database image is needed.

The service takes an initial backup when it starts. Set these options in
`.env` to change the schedules or retention periods:

| Option | Default | Applies to |
| --- | ---: | --- |
| `SHARED_DB_BACKUP_INTERVAL_SECONDS` | `10800` | Interval for both lease and shared database dumps |
| `SHARED_DB_BACKUP_RETENTION_DAYS` | `1` | Retention for both Kea database dumps |
| `STORK_DB_BACKUP_INTERVAL_SECONDS` | `86400` | Stork backup interval |
| `STORK_DB_BACKUP_RETENTION_DAYS` | `3` | Retention for Stork dumps |

Intervals must be at least 60 seconds. Retention must be at least one day.
Each schedule runs independently. Check status and list dumps with:

```sh
docker compose logs db-backups
docker compose exec db-backups sh -c 'find /var/lib/kea-backups -maxdepth 2 -type f -print'
```

## Copy the dumps out of Docker

The named volume is convenient for this development setup, but it is stored by
Docker on the same host. It does not protect against removing the volume,
resetting Docker Desktop, losing the host, or running `docker compose down -v`.
Copy dumps to storage outside Docker regularly if you need protection from those
events.

Only files ending in `.dump` are published backups. Each dump is written to a
hidden temporary file with owner-only permissions and renamed in the same
directory after `pg_dump` succeeds and the file is nonempty. Failed dumps are
removed; startup clears temporary files left by an interrupted run. The backups
service must be the sole writer of these directories.

For example, from the project directory, copy the volume contents to a local
folder:

```sh
docker compose cp db-backups:/var/lib/kea-backups ./kea-stack-backups
```

An export while backups are running can include hidden `.dump.tmp.*` files.
Ignore those files when selecting archives to inspect, retain, or restore; they
are unfinished and may be truncated. A published `.dump` file is complete even
when another dump is in progress.

You can also inspect the volume name with `docker volume inspect
kea-stack_backups`. Keep copied dumps somewhere that is not managed by this
Compose project.

## Restore planning

Each `.dump` file is a PostgreSQL custom-format archive. You can inspect its
contents without restoring it:

```sh
docker compose run --rm --no-deps --entrypoint sh db-backups -c 'pg_restore --list "/var/lib/kea-backups/leases/<dump-file>"'
```

Restore with the corresponding PostgreSQL service running: `lease-db`, `shared-db`, or `stork-db`. Stop application writers and `db-backups` during restoration. The project does not yet provide an automated restore procedure. Rehearse restoration against a disposable database before relying on backups.
