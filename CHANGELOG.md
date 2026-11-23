# Changelog

## v0.4 (2026-11-23)

### Dedicated Guild Master Results Menu & Reliable Throttled Sync
- **New Dedicated Guild Master Zusatzmenü (`UI_GMMenu.lua` — „GM-Auswertung“):**
  - Prominent gold **„GM-Auswertung (N)“** button right in the top bar of `/wappen` (and `/wappen gm` slash command, plus **„Auswertung“** button in the Leader Panel), visible **strictly to the Guild Master** (and in `/wappen test`).
  - Opens a full-size ranked anonymous leaderboard of ALL submitted guild designs (`#1`, `#2`, `#3`...) with 2D thumbnails, big green/red split vote bars per design, clear `Hoch / Runter / Score / Gesamt` counts, overall KPI strip (`Designs / Wähler / Enthalten`), **„3D ansehen“**, **„Übernehmen“**, **„Merken“**, **„Stimmen leeren“**, and **„Sieger melden“**.
  - When the Guild Master runs `/wappen` and designs already exist, the dedicated GM Results overview opens automatically alongside the main window.
- **Fixed Dropped Votes Under WoW Addon Message Throttling (`Protocol.lua`):**
  - Replaced unthrottled fire-and-forget `C_ChatInfo.SendAddonMessage` bursts (which silently dropped `GB_BALLOT` votes when Blizzard returned `AddonMessageThrottle` / `ChannelThrottle`!) with a **reliable priority send queue** that checks `SendAddonMessageResult` and automatically retries throttled messages with backoff.
  - Prioritized sending anonymous ballots (`GB_BALLOT`) BEFORE deletion tombstones (`GB_DEL`) during snapshots.
  - Added 1-click **„Stimmen abrufen“ (`GB_SYNC_REQ`)** button in the GM Results menu so the Guild Master can immediately pull every online guild member's anonymous ballot (1 tiny packet per member) with a live response counter!
- **Stopped Accidental Live Invite Spam:** Opening the standalone Leader Panel no longer auto-broadcasts a Live Session invite until the GM actually clicks **„Live starten“**.
- **Diagnostics Command (`/wappen status`):** Prints addon version, guild name, rank, `IsGuildLeader` detection, registered prefix, active scope, design/voter counts, and send queue length for instant troubleshooting.

## v0.3 (2026-11-23)

- Cross-realm canonical `"BOARD"` scope, checksum-based peer sync, atomic `GB_BALLOT` replication, and test-mode cleanup.

## v0.2 (2026-11-23)

- Always-open persistent Guild Design Board, native clickable vote buttons, inline toast feedback, and `/wappen update` + `update.ps1`.

## v0.1 (2026-11-23)

- Initial release for World of Warcraft: Forever (`16001`).
