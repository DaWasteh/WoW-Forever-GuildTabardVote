# Changelog

## v0.3 (2026-11-23)

### Guild Master Vote Visibility & Edge-Case Bugfixes
- **Fixed Guild Master Missing Vote Counts per Design (Cross-Realm & Scope Fix):**
  - Replaced realm-specific `"<Guild-Realm>_board"` scope IDs with a canonical cross-realm-safe `"BOARD"` scope (with automatic migration of legacy v0.2 votes), fixing cases where connected-realm members' votes were stored under a different scope than the Guild Master's.
  - Carrying over existing board votes automatically when the Guild Master starts a Timed Poll with *"Bisherige Gilden-Designs behalten"* checked (and mirroring in-flight `"BOARD"` votes cleanly).
  - Hardened `GTV:IsGuildLeader()` with `C_GuildInfo.GuildRoster()` and `C_GuildInfo.GetGuildRankOrder` fallback so GM detection works reliably right after login.
- **Crystal-Clear Anonymous GM Vote Display:**
  - Every design row now shows a clear anonymous GM vote badge (`+Up / -Down (Total)`) with hover tooltip in BOTH the **Leader Panel** and the **Member Window** (strictly hidden from regular members!).
  - Added an anonymous GM summary header (`GM (anonym): Wähler: X | Enthalten: Y`) above the Guild Designs list for the Guild Master.
- **Checksum-Based Peer Sync & Atomic Ballot Replication (`GB_BALLOT`):**
  - Replaced count-only `GB_HELLO` checks (which missed votes whenever two peers happened to have the same voter count or voted on multiple designs) with a deterministic content checksum over all designs, deletions, and individual votes.
  - Packed per-voter ballots (`GB_BALLOT` with monotonic revision) now sync vote additions, switches (`UP <-> DOWN`), removals (`NONE`), abstentions, and design deletions (`GB_DEL` tombstones) cleanly across offline/online sessions.
- **Fixed Lingering Solo Test Mode Edge Case:** Closing `/wappen test` or opening `/wappen` / `/wappen start` / Guild Registrar now cleanly exits test mode so real guild sync and GM vote counts resume immediately without requiring `/reload`.
- **Fixed Delayed Login Guild Sync:** Guild sync now waits until `GetGuildInfo("player")` is actually populated (`GUILD_ROSTER_UPDATE` / `PLAYER_GUILD_UPDATE`) rather than marking synced prematurely.

## v0.2 (2026-11-23)

- Always-open persistent Guild Design Board so every guild member can submit designs and view all guild designs anytime.
- Native clickable `Button` widgets for Thumbs Up / Thumbs Down, inline visual toast feedback, and 3D `EnsureReady` tab-switch reset fix.
- `/wappen update` command + `update.ps1` 1-click GitHub updater + automatic in-game version check.

## v0.1 (2026-11-23)

- Initial release of **GuildTabardVote** for **World of Warcraft: Forever** (`16001`).
