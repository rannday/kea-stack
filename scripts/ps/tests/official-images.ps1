param(
    [string]$Compose = 'docker',
    [string]$Project = 'kea-official-test',
    [switch]$Dns
)
$ErrorActionPreference = 'Stop'
$prefix = if ($Compose -eq 'docker') { @('compose') } else { @() }
$prefix += @('--env-file', '.env.example', '-p', $Project, '-f', 'compose.yaml', '-f', 'scripts/ps/tests/compose.official.yaml')
function Invoke-TestCompose {
    $result = & $Compose @prefix @args
    if ($LASTEXITCODE -ne 0) { throw "Compose check failed: $($args[0])" }
    return $result
}
foreach ($service in @('lease-db', 'shared-db', 'stork-db')) {
    $version = Invoke-TestCompose exec -T $service postgres --version
    if ($version -notmatch '18\.6') { throw "$service uses an unexpected PostgreSQL version" }
}
for ($attempt = 0; $attempt -lt 15; $attempt++) {
    $targets = (Invoke-TestCompose exec -T prometheus wget -qO- 'http://localhost:9090/api/v1/targets' | ConvertFrom-Json).data.activeTargets
    if (!($targets | Where-Object { $_.health -ne 'up' })) { break }
    Start-Sleep -Seconds 2
}
foreach ($name in @('dhcp4:9547', 'dhcp6:9547')) {
    $target = $targets | Where-Object { $_.labels.instance -eq $name }
    if (!$target -or $target.health -ne 'up') { throw "Prometheus target $name is not healthy" }
}
foreach ($service in @('dhcp4', 'dhcp6')) {
    $number = $service.Substring(4)
    $section = "Dhcp$number"
    $rendered = (Invoke-TestCompose exec -T $service cat "/run/kea/kea-$service.conf" | ConvertFrom-Json).$section
    $original = (Invoke-TestCompose exec -T $service cat "/etc/kea/kea-$service.conf" | ConvertFrom-Json).$section
    if ([bool]$rendered.'dhcp-ddns' -ne [bool]$Dns) { throw "$service DNS mode is wrong" }
    if (($rendered.'option-data' | ConvertTo-Json -Compress) -ne ($original.'option-data' | ConvertTo-Json -Compress)) {
        throw "$service option-data changed"
    }
}
$dnsTarget = $targets | Where-Object { $_.labels.instance -eq 'dns:9119' }
if ([bool]$dnsTarget -ne [bool]$Dns) { throw 'BIND scrape target does not match DNS profile' }
if ($Dns -and $dnsTarget.health -ne 'up') { throw 'BIND exporter is unhealthy' }
Invoke-TestCompose exec -T db-backups sh -c 'for role in leases shared stork; do archive=$(find /var/lib/kea-backups/$role -name "*.dump" | head -n 1); test -n "$archive" && pg_restore --list "$archive" >/dev/null || exit 1; done'
Write-Output 'Official image smoke checks passed.'
