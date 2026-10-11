$ErrorActionPreference = "Stop"

. (Join-Path $PSScriptRoot 'lib\docker.ps1')
Assert-DockerEngine

$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '../..')).Path
Push-Location $repoRoot
try {
    Invoke-Docker compose down
}
finally {
    Pop-Location
}
