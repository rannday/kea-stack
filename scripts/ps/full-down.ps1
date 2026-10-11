$ErrorActionPreference = "Stop"

. (Join-Path $PSScriptRoot 'lib\docker.ps1')
Assert-DockerEngine

$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '../..')).Path
$logPath = Join-Path $repoRoot '.logs'

Push-Location $repoRoot
try {
    Invoke-Docker compose --profile dns down --volumes --rmi all --remove-orphans

    if (Test-Path -LiteralPath $logPath) {
        Remove-Item -LiteralPath $logPath -Recurse -Force
    }
}
finally {
    Pop-Location
}
