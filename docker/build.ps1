param(
    [string]$Mode   = "prod",
    [string]$Action = "up"
)
$ErrorActionPreference = "Stop"
$ScriptDir   = Split-Path -Parent $MyInvocation.MyCommand.Path
$EnvFile     = Join-Path $ScriptDir ".env"
$ComposeFile = Join-Path $ScriptDir "docker-compose.yml"
if ($Mode -eq "dev") { $ComposeFile = Join-Path $ScriptDir "docker-compose.dev.yml" }

# .env チェック
if (-not (Test-Path $EnvFile)) {
    Write-Error "[ERROR] .env が存在しません。.env.example をコピーして設定してください。`n  Copy-Item docker\.env.example docker\.env"
    exit 1
}

Write-Host "[RustPVC] mode=$Mode action=$Action compose=$ComposeFile"

switch ($Action) {
    "up" {
        docker compose -f $ComposeFile --env-file $EnvFile up -d --build
        docker compose -f $ComposeFile ps
    }
    "down"  { docker compose -f $ComposeFile down }
    "build" { docker compose -f $ComposeFile --env-file $EnvFile build --no-cache }
    "logs"  { docker compose -f $ComposeFile logs -f }
    default {
        Write-Host "Usage: build.ps1 [-Mode prod|dev] [-Action up|down|build|logs]"
        exit 1
    }
}
