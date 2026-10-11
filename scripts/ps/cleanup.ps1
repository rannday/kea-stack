param()

$ErrorActionPreference = "Stop"

. (Join-Path $PSScriptRoot 'lib\docker.ps1')
Assert-DockerEngine

Write-Warning @"
GLOBAL DOCKER CLEANUP
This removes every Docker container (including container logs), image, and
Buildx build record (including build logs) on this machine; all Docker build
cache; all unused Docker volumes; and all unused Docker networks. This cannot
be undone.
"@

$confirmation = Read-Host "Type Y to continue"
if ($confirmation -cne "Y") {
    Write-Host "Cleanup cancelled."
    exit 0
}

$containerIds = @(Invoke-Docker ps -aq)
foreach ($containerId in $containerIds) {
    Invoke-Docker rm -f $containerId
}

$imageIds = @(Invoke-Docker image ls -aq | Sort-Object -Unique)
foreach ($imageId in $imageIds) {
    Invoke-Docker image rm -f $imageId
}

Invoke-Docker buildx history rm --all
Invoke-Docker buildx prune --all --force

Invoke-Docker volume prune --all --force
Invoke-Docker network prune --force

Write-Host "Global Docker cleanup completed."
