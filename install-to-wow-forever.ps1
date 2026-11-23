param(
    [string]$WowAddOnsDir = "K:\World of Warcraft\_forever_\Interface\AddOns"
)

$ErrorActionPreference = "Stop"
$root = Split-Path -Parent $MyInvocation.MyCommand.Path
$src = Join-Path $root "GuildTabardVote"
$dst = Join-Path $WowAddOnsDir "GuildTabardVote"

if (-not (Test-Path $WowAddOnsDir)) {
    throw "WoW Forever AddOns directory not found: $WowAddOnsDir"
}

if (Test-Path $dst) {
    Remove-Item $dst -Recurse -Force
}
Copy-Item -Path $src -Destination $dst -Recurse -Force
Write-Host "Installed GuildTabardVote to: $dst" -ForegroundColor Green
Write-Host "Start WoW: Forever (or run /reload) and try /wappen test!" -ForegroundColor Cyan
