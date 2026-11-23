# Changelog

## v0.2 (2026-11-23)

### Bugfixes & Major UX Improvements
- **Always-Open Persistent Guild Design Board:** Any guild member can now submit designs to their guild at ANY time (no longer blocked when the Guild Master hasn't started a live/timed session yet!). Every guild member automatically sees ALL submitted guild designs in the right-hand **Gilden-Designs** panel, persisted in `SavedVariables` and synced automatically peer-to-peer on login/open.
- **Fixed Non-Responsive Buttons:**
  - Replaced `Frame`-based vote boxes with native clickable `Button` widgets (`OnClick`) for **Daumen hoch** & **Daumen runter**.
  - Big **Daumen hoch / Daumen runter** buttons now work on BOTH active Live Leader sessions AND any selected Guild Design from the list!
  - **An Gilde senden** (Submit to Guild) and **Lokal speichern** (Save Locally) now work reliably at all times with clear inline visual toast feedback inside the window.
- **Fixed Tab Switching & 3D Load Reset:** `TabardModel:EnsureReady()` no longer calls `SetUnit("player")` repeatedly on tab switches or before `SeekModel()`, preventing loaded/previewed designs from being reset.
- **Design Management:** Authors and Guild Masters can delete submitted designs (`X`) with synced tombstones (`GB_DEL`). Added a 1-click **Leiter-Panel** shortcut button in the header for Guild Masters.
- **1-Click GitHub Updater (`/wappen update` + `update.ps1`):** Automatic in-game guild version check notifies when a newer version is available, and `/wappen update` opens a copy-ready PowerShell 1-liner (`irm https://raw.githubusercontent.com/DaWasteh/WoW-Forever-GuildTabardVote/main/update.ps1 | iex`) that auto-detects WoW: Forever and installs the latest GitHub release.

## v0.1 (2026-11-23)

First public release of **GuildTabardVote** for **World of Warcraft: Forever** (Interface `16001`).
