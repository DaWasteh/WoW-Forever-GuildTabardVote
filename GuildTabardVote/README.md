# GuildTabardVote (Gildenwappen-Abstimmung)

**Live- & mehrtägige Gildenwappen-Abstimmung direkt im Spiel — entwickelt für World of Warcraft: Forever (Interface `16001`) sowie Classic & Retail.**

---

## Installation (Deutsch)

### Option 1: 1-Klick-Updater via PowerShell (am schnellsten!)
Kopiere diese eine Zeile in PowerShell (oder tippe im Spiel `/wappen update`):
```powershell
irm https://raw.githubusercontent.com/DaWasteh/WoW-Forever-GuildTabardVote/main/update.ps1 | iex
```
Das Skript findet deinen `WoW: Forever`-Ordner automatisch, lädt das neueste GitHub-Release herunter und installiert es direkt in `Interface\AddOns\GuildTabardVote`. Danach in WoW einfach `/reload`!

### Option 2: Direkt per ZIP (manuell)
1. Öffne die [aktuelle Release-Seite](https://github.com/DaWasteh/WoW-Forever-GuildTabardVote/releases/latest).
2. Lade unten bei **Assets** die Datei **`GuildTabardVote-vX.X.zip`** herunter.
3. Entpacke die ZIP-Datei und kopiere den Ordner **`GuildTabardVote`** direkt in deinen WoW: Forever AddOn-Ordner:
   - Standardpfad Windows: `C:\Program Files (x86)\World of Warcraft\_forever_\Interface\AddOns\GuildTabardVote`
   - *(Falls du WoW auf einer anderen Festplatte installiert hast, entsprechend in `...\World of Warcraft\_forever_\Interface\AddOns\GuildTabardVote`.)*
4. Stelle sicher, dass im Ordner `GuildTabardVote` direkt die Datei `GuildTabardVote.toc` liegt (nicht doppelt verschachtelt wie `GuildTabardVote\GuildTabardVote\`).
5. Starte **WoW: Forever** neu — fertig! Im Spiel kannst du sofort mit `/wappen test` prüfen, ob alles läuft.

> **Hinweis zur CurseForge-App:** Manuell in `Interface\AddOns\` entpackte Addons werden von der CurseForge-App nicht überschrieben und funktionieren ganz normal im Spiel. Sobald das Addon auch auf CurseForge freigeschaltet ist, kann es dort direkt per Suche installiert und automatisch aktualisiert werden.

### Option 2: Über WowUp (mit Auto-Updates direkt von GitHub)
1. Öffne **WowUp** und wähle **WoW: Forever**.
2. Klicke auf **„Install from URL“** (Aus URL installieren).
3. Füge diese Repository-URL ein:
   `https://github.com/DaWasteh/WoW-Forever-GuildTabardVote`
4. Fertig — WowUp installiert automatisch das neueste GitHub-Release und hält es aktuell.

---

## Installation (English)

### Option 1: Direct ZIP Download (Recommended)
1. Go to the [latest release page](https://github.com/DaWasteh/WoW-Forever-GuildTabardVote/releases/latest).
2. Under **Assets**, download **`GuildTabardVote-vX.X.zip`**.
3. Extract the archive and place the **`GuildTabardVote`** folder inside your WoW: Forever AddOns directory:
   `...\World of Warcraft\_forever_\Interface\AddOns\GuildTabardVote`
4. Restart **WoW: Forever** and run `/wappen test` to try it out.

### Option 2: Via WowUp (Auto-Updates from GitHub)
1. Open **WowUp**, select **WoW: Forever**, and click **Install from URL**.
2. Paste `https://github.com/DaWasteh/WoW-Forever-GuildTabardVote` and confirm.

---

## Features (Deutsch)

- **Designs speichern & laden (Gildenmeister & Mitglieder):** Speichere beliebig viele eigene oder vorgeschlagene Wappen-Designs mit Namen (accountweit gespeichert), sieh sie jederzeit als 2D-Miniaturvorschau, lade sie per Klick in den Designer oder direkt ins offizielle Wappenmeister-Menü und reiche sie direkt in laufende Abstimmungen ein.
- **Zeitlich begrenzte Abstimmungen über X Tage:** Der Gildenmeister kann eine mehrtägige Abstimmung starten (z. B. 1, 3, 7 oder beliebig viele X Tage, plus `1Std` zum Testen). Bis zum Ablauf der Frist synchronisiert sich die Wahl automatisch beim Einloggen über die Gilde — jedes Mitglied kann alle Designs ansehen, eigene Designs einreichen, pro Design mit Daumen hoch/runter abstimmen oder sich enthalten.
- **100 % anonym & Auswertung nur für den Gildenmeister:** Sowohl Gildenmeister als auch alle Gildenmitglieder sehen **alle eingereichten Designs** in 2D & 3D. Die **Stimmenanzahl pro Design** (Daumen hoch / runter / Enthalten) sieht jedoch **ausschließlich der Gildenmeister** — und zwar vollständig **anonym** (ohne Spielernamen, über zufällige anonyme Wahl-Tokens).
- **Live-Modus am Gildenwappenmeister:** Sobald der Gildenmeister beim NPC das Wappenmenü öffnet (oder `/wappen start` nutzt), erhalten online befindliche Gildenmitglieder automatisch die Anfrage **„Mitentscheiden“** oder **„Enthalten“** und sehen alle Änderungen live in 3D & 2D.
- **1-Klick-Übernahme:** Der Gildenmeister kann jedes gespeicherte Design, jeden Live-Vorschlag und das Sieger-Design einer Zeit-Abstimmung per Klick auf **„Übernehmen“** direkt auf das offizielle Wappenmeister-Fenster laden!
- **Interaktive 3D-Vorschau:** Linksklick ziehen zum Drehen, Mausrad zum Zoomen, Rechtsklick ziehen zum Verschieben + Reset-Button.
- **Solo-Testmodus (`/wappen test`):** Teste alle Modi (Live-Wahl, X-Tage-Wahl, anonyme GM-Auswertung & gespeicherte Designs) sofort alleine!

## Features (English)

- **Save & Load Designs:** Save unlimited custom or submitted designs with names, load them into the 3D/2D designer or Guild Registrar with 1 click, or submit them directly to active votes.
- **Timed Multi-Day Polls (X Days):** Guild Masters can launch timed votes lasting X days with automatic guild-wide login sync, countdown timers, member submissions, and winner announcements.
- **Anonymous & GM-Only Vote Counts:** Everyone can view all submitted designs in 3D & 2D, submit their own designs, and vote Thumbs Up / Thumbs Down or Abstain. Vote tallies per design are strictly anonymous (no voter names) and visible exclusively to the Guild Master.
- **Live Tabard Registrar Sync:** Automatically invites online guild members when the Guild Master opens the Guild Tabard Vendor (`TabardFrame`) and streams every change live.

## Befehle / Slash Commands

| Befehl / Command | Funktion |
| --- | --- |
| `/wappen` (oder `/gwa`, `/gtv`) | Fenster öffnen (Live-Ansicht, Zeit-Wahl, Designer & Gespeicherte Designs) |
| `/wappen start` | Leiter-Panel überall öffnen (Live-Wahl, X-Tage-Zeit-Wahl & Gespeichert) |
| `/wappen stop` | Aktive Live-Abstimmung beenden |
| `/wappen test` | Solo-Testmodus (Leiter- & Mitglieder-Ansicht gleichzeitig testen) |
| `/wappen auto` | Auto-Start beim Gildenwappenmeister an-/ausschalten |
| `/wappen update` | 1-Klick-Update-Befehl von GitHub anzeigen |
| `/wappen help` | Hilfe im Chat anzeigen |
