$ErrorActionPreference = "Stop"

. (Join-Path $PSScriptRoot 'lib\docker.ps1')
Assert-DockerEngine

$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '../..')).Path
$logPath = Join-Path $repoRoot '.logs\dhcp'

Push-Location $repoRoot
try {
    New-Item -ItemType Directory -Force -Path $logPath | Out-Null

    Invoke-Docker compose up -d --build --force-recreate
}
finally {
    Pop-Location
}
