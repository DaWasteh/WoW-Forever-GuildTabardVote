param(
    [string]$Version = "v0.1"
)

$ErrorActionPreference = "Stop"
$root = Split-Path -Parent $MyInvocation.MyCommand.Path
$addonDir = Join-Path $root "GuildTabardVote"
$distDir = Join-Path $root "dist"
$zipPath = Join-Path $distDir ("GuildTabardVote-" + $Version + ".zip")

if (-not (Test-Path $addonDir)) {
    throw "AddOn directory not found: $addonDir"
}

Copy-Item (Join-Path $root "README.md") (Join-Path $addonDir "README.md") -Force
Copy-Item (Join-Path $root "CHANGELOG.md") (Join-Path $addonDir "CHANGELOG.md") -Force

New-Item -ItemType Directory -Path $distDir -Force | Out-Null
if (Test-Path $zipPath) {
    Remove-Item $zipPath -Force
}

Compress-Archive -Path $addonDir -DestinationPath $zipPath -CompressionLevel Optimal
Write-Host "Built CurseForge-ready package: $zipPath" -ForegroundColor Green
