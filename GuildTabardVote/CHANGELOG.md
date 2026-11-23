# Changelog

## v0.1 (2026-11-23)

First public release of **GuildTabardVote** for **World of Warcraft: Forever** (Interface `16001`, plus Classic & Retail multi-version TOC support `11509`, `20506`, `120105`).

### Features
- **Live Guild Tabard Sync & Voting:** Automatically invites online guild members (*Mitentscheiden* / *Enthalten*) when the Guild Master opens the Guild Tabard Registrar (`TabardFrame`) or runs `/wappen start`, streaming emblem, border, and background changes live to participating members' 3D character models and 2D previews.
- **Timed Multi-Day Guild Votes (X Days):** Guild Masters can create timed guild votes lasting X days (or quick presets `1h`, `1d`, `3d`, `7d`) with a live countdown, automatic login sync across the guild, peer relay for offline votes, and winner announcement.
- **Strictly Anonymous & Guild-Master-Only Vote Results:** All guild members and the Guild Master see **all** submitted designs in 3D & 2D, submit their own designs, and vote Thumbs Up / Thumbs Down or Abstain — while vote counts per design are strictly **anonymous** (random per-poll voter tokens, never player names) and visible **only to the Guild Master**.
- **Save & Load Designs:** Account-wide design library (`SavedVariables`) for both Guild Masters and Guild Members — save any design with a custom name, load it back into the 3D/2D designer or directly onto the Guild Registrar with 1 click, or submit saved designs into an active vote.
- **Interactive 3D Tabard Viewer:** Centered, enlarged `TabardModel` with unified left-drag rotate, right-drag pan, mouse-wheel zoom, and camera reset.
- **Solo Test Mode (`/wappen test`):** Test Live Mode, X-Day Timed Votes, anonymous GM counts, and Saved Designs solo.
- **Full Localization:** German (`deDE`) and English (`enUS`).
