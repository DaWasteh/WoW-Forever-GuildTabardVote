<#
.SYNOPSIS
    Downloads and installs the latest GuildTabardVote release from GitHub into WoW: Forever.
.EXAMPLE
    irm https://raw.githubusercontent.com/DaWasteh/WoW-Forever-GuildTabardVote/main/update.ps1 | iex
#>
$ErrorActionPreference = "Stop"

$repo = "DaWasteh/WoW-Forever-GuildTabardVote"
Write-Host "=== GuildTabardVote Auto-Updater ===" -ForegroundColor Yellow

# 1. Auto-detect World of Warcraft\_forever_\Interface\AddOns across all local drives
$candidates = @()
Get-PSDrive -PSProvider FileSystem | ForEach-Object {
    $root = $_.Root
    @(
        "World of Warcraft\_forever_",
        "Program Files (x86)\World of Warcraft\_forever_",
        "Program Files\World of Warcraft\_forever_",
        "Games\World of Warcraft\_forever_",
        "Battle.net\World of Warcraft\_forever_"
    ) | ForEach-Object {
        $p = Join-Path $root $_
        if (Test-Path $p) {
            $candidates += $p
        }
    }
}

$foreverDir = $candidates | Select-Object -First 1
if (-not $foreverDir) {
    Write-Host "WoW: Forever wurde nicht automatisch gefunden." -ForegroundColor Red
    $foreverDir = Read-Host "Bitte Pfad zum '_forever_' Ordner eingeben (z.B. C:\Program Files (x86)\World of Warcraft\_forever_)"
}

if (-not (Test-Path $foreverDir)) {
    throw "Ordner nicht gefunden: $foreverDir"
}

$addonsDir = Join-Path $foreverDir "Interface\AddOns"
New-Item -ItemType Directory -Path $addonsDir -Force | Out-Null
Write-Host "Zielordner: $addonsDir" -ForegroundColor Cyan

# 2. Fetch latest release info from GitHub
Write-Host "Pruefe neuestes Release auf GitHub ($repo)..." -ForegroundColor Cyan
$release = Invoke-RestMethod -Uri "https://api.github.com/repos/$repo/releases/latest" -Headers @{ "User-Agent" = "GuildTabardVote-Updater" }
$asset = $release.assets | Where-Object { $_.name -like "GuildTabardVote*.zip" } | Select-Object -First 1
if (-not $asset) {
    throw "Kein GuildTabardVote ZIP-Asset im Release $($release.tag_name) gefunden."
}

$tmpZip = Join-Path $env:TEMP $asset.name
$tmpExtract = Join-Path $env:TEMP ("GuildTabardVote_Update_" + [guid]::NewGuid().ToString("N"))

try {
    Write-Host "Lade $($asset.name) ($($release.tag_name)) herunter..." -ForegroundColor Cyan
    Invoke-WebRequest -Uri $asset.browser_download_url -OutFile $tmpZip -UseBasicParsing

    Expand-Archive -Path $tmpZip -DestinationPath $tmpExtract -Force
    $extractedAddon = Join-Path $tmpExtract "GuildTabardVote"
    if (-not (Test-Path $extractedAddon)) {
        throw "Ungueltiges ZIP-Archiv: Ordner 'GuildTabardVote' fehlt."
    }

    $targetAddon = Join-Path $addonsDir "GuildTabardVote"
    if (Test-Path $targetAddon) {
        Remove-Item -Path $targetAddon -Recurse -Force
    }
    Copy-Item -Path $extractedAddon -Destination $targetAddon -Recurse -Force

    Write-Host ""
    Write-Host "ERFOLG! GuildTabardVote $($release.tag_name) wurde installiert!" -ForegroundColor Green
    Write-Host "Wechsle jetzt in WoW: Forever und tippe /reload (oder starte WoW neu)." -ForegroundColor Yellow
} finally {
    if (Test-Path $tmpZip) { Remove-Item $tmpZip -Force -ErrorAction SilentlyContinue }
    if (Test-Path $tmpExtract) { Remove-Item $tmpExtract -Recurse -Force -ErrorAction SilentlyContinue }
}
