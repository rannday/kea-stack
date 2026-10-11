---
name: kea-stack-test
description: Validate this kea-stack deployment and diagnose Compose, Stork agent, Prometheus, Grafana, and DHCP test failures. Use for test selection and evidence; use kea-stack for deployment implementation and the separate kea-stack-test repo for client test changes.
---

# Kea Stack Validation

Work from the `kea-stack` repository root. Read `AGENTS.md`; use the existing `kea-stack` skill when deployment implementation is required. Keep validation scoped to the requested change. Do not install dependencies, restart the user's stack, remove volumes, or run Docker-wide cleanup without authorization for those actions. Never read real `.env` files, secret-bearing variants, or PEM files; use `.env.example` for static checks and disposable fixtures.

## Select the evidence

- Compose changes: validate `compose.yaml` with DNS disabled and enabled.
- Kea rendering: use the relevant tests under `scripts/sh/tests/` in their documented disposable image environment. The DHCP server identifier test requires the DHCP image and a read-only `/source` mount; it is not a generic host shell test.
- Image integration: use `scripts/ps/tests/compose.official.yaml` with `.env.example` and a distinct project such as `kea-official-test`. The override removes host publications and isolates runtime logs and application volumes. Review merged Compose output before starting it.
- Client leasing, renewal, relay behavior, and DHCP-driven DNS updates: use the separate `../kea-stack-test` harness. Read its current `AGENTS.md` and runner before selecting commands. Do not edit that repository unless requested.

The `upgrade-kea` helpers/tests are retired for this official-image development stack; an intentional retirement error is not a regression. Run PowerShell checks natively. For POSIX checks on Windows, follow the WSL section of `~/.codex/workflow.md` and use explicit Debian and workdir when applicable. Preserve the test's required container environment.

## Compose and image checks

Use an available Compose CLI; substitute `docker-compose` when the `docker compose` plugin is unavailable. In PowerShell, save and restore the process's `COMPOSE_PROFILES` value when checking both modes:

```powershell
$savedProfiles = $env:COMPOSE_PROFILES
try {
    foreach ($profiles in @('', 'dns')) {
        $env:COMPOSE_PROFILES = $profiles
        docker compose --env-file .env.example -f compose.yaml config --quiet
        if ($LASTEXITCODE -ne 0) { throw "Compose validation failed: profiles=$profiles" }
    }
} finally {
    $env:COMPOSE_PROFILES = $savedProfiles
}
```

For authorized disposable integration checks, combine `compose.yaml` and `scripts/ps/tests/compose.official.yaml` with the same project name and profile throughout startup and inspection. `scripts/ps/tests/official-images.ps1` inspects an already-running test project; it does not create one. Pass `-Dns` only when that project has the `dns` profile, and `-Compose docker-compose` when using the standalone CLI. Check `kea-init` exited successfully before evaluating daemons. Follow `docs/kea.md` for schema details and `docs/docker.md` for lifecycle behavior. Request explicit authorization before removing test volumes.

## Diagnose monitoring failures

1. Inspect selected services with `docker compose ps -a dhcp4 dhcp6 agent4 agent6 stork`; include `ddns` and `agent-ddns` when DNS is enabled. Capture only selected state fields: status, exit code, OOM flag, start/finish times, restart count, restart policy, and namespace modes. Avoid unrestricted inspect output and token-bearing logs.
2. Agents share daemon PID/network namespaces. A direct daemon stop or Engine restart can kill the agent; `depends_on.restart: true` handles Compose-controlled operations. Correlate test actions and timestamps before attributing the cause. Exit 137 alone does not establish OOM. Keep official Kea images and agents as separate containers.
3. Check persistent agent identity and stable `KEA_SERVICE` registration. Stork authorization may be needed for a new identity; healthy HTTP responses from Stork do not prove agent discovery or daemon communication. Retain volumes for ordinary down/up checks.
4. Check Prometheus target health separately from exporter samples. DHCP targets are `dhcp4:9547` and `dhcp6:9547`, job `kea`; there is no separate DDNS scrape. Use `up{job="kea",instance=~"dhcp[46]:9547"}` for exporter availability. Grafana availability panels must use matching labels and an appropriate instant query. Green targets do not prove every Kea metric exists.
5. If failures follow client tests, inspect the harness's setup/teardown and Docker lifecycle actions before changing this deployment. Ordinary client test execution should not need to restart the server. Network attachment setup can require a daemon restart; establish whether it actually happened and check the matching agent afterward.

## Finish

Report commands, profile, project name, observed results, and skipped checks. Distinguish static configuration, startup/monitoring, and functional client DHCP/DDNS evidence. Do not claim fresh Serena activation, agent authorization, successful leases, or DNS updates from source checks alone. Stop once the requested acceptance conditions pass.
