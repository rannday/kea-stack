$ErrorActionPreference = "Stop"

function Stop-DockerScript {
    param(
        [Parameter(Mandatory)]
        [string]$Message
    )

    [Console]::Error.WriteLine("ERROR: $Message")
    exit 1
}

function Assert-DockerEngine {
    if (-not (Get-Command docker -ErrorAction SilentlyContinue)) {
        Stop-DockerScript "Docker CLI not found on PATH."
    }

    $null = & docker info --format '{{.ServerVersion}}' 2>$null
    if ($LASTEXITCODE -ne 0) {
        Stop-DockerScript "Docker engine is unavailable. Start Docker Desktop and retry."
    }
}

function Invoke-Docker {
    # Use PowerShell's automatic $args array so native Docker arguments such
    # as `compose` are forwarded without function parameter-binding ambiguity.
    $DockerArguments = @($args)

    if ($DockerArguments.Count -eq 0) {
        Stop-DockerScript "Invoke-Docker requires a Docker command."
    }

    & docker @DockerArguments
    $dockerExitCode = $LASTEXITCODE
    if ($dockerExitCode -ne 0) {
        $commandText = $DockerArguments -join ' '
        Stop-DockerScript "Docker command failed (exit code $dockerExitCode): docker $commandText"
    }
}
