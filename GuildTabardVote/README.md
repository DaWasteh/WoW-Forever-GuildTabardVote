# GuildTabardVote (Gildenwappen-Abstimmung)

**Live- & mehrtägige Gildenwappen-Abstimmung direkt im Spiel — entwickelt für World of Warcraft: Forever (Interface `16001`) sowie Classic & Retail.**

---

## Features (Deutsch)

- **Designs speichern & laden (Gildenmeister & Mitglieder):** Speichere beliebig viele eigene oder vorgeschlagene Wappen-Designs mit Namen (accountweit gespeichert), sieh sie jederzeit als 2D-Miniaturvorschau, lade sie per Klick in den Designer oder direkt ins offizielle Wappenmeister-Menü und reiche sie direkt in laufende Abstimmungen ein.
- **Zeitlich begrenzte Abstimmungen über X Tage:** Der Gildenmeister kann eine mehrtägige Abstimmung starten (z. B. 1, 3, 7 oder beliebig viele X Tage, plus `1Std` zum Testen). Bis zum Ablauf der Frist synchronisiert sich die Wahl automatisch beim Einloggen über die Gilde — jedes Mitglied kann alle Designs ansehen, eigene Designs einreichen, pro Design mit Daumen hoch/runter abstimmen oder sich enthalten.
- **100 % anonym & Auswertung nur für den Gildenmeister:** Sowohl Gildenmeister als auch alle Gildenmitglieder sehen **alle eingereichten Designs** in 2D & 3D. Die **Stimmenanzahl pro Design** (Daumen hoch / runter / Enthalten) sieht jedoch **ausschließlich der Gildenmeister** — und zwar vollständig **anonym** (ohne Spielernamen, über zufällige anonyme Wahl-Tokens).
- **Live-Modus am Gildenwappenmeister:** Sobald der Gildenmeister beim NPC das Wappenmenü öffnet (oder `/wappen start` nutzt), erhalten online befindliche Gildenmitglieder automatisch die Anfrage **„Mitentscheiden“** oder **„Enthalten“** und sehen alle Änderungen live in 3D & 2D.
- **1-Klick-Übernahme:** Der Gildenmeister kann jedes gespeicherte Design, jeden Live-Vorschlag und das Sieger-Design einer Zeit-Abstimmung per Klick auf **„Übernehmen“** direkt auf das offizielle Wappenmeister-Fenster laden!
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
| `/wappen help` | Hilfe im Chat anzeigen |
