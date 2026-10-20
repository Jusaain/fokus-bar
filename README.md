<div align="center">

# FokusBar für Mac

**Dein Deep-Work-Timer, Natur- & Spotify-Shuffle-Player sowie App- & Webseiten-Blocker direkt in der Menüleiste.**

### [↓ FokusBar als DMG herunterladen (macOS 14+ · Apple Silicon & Intel)](https://github.com/Jusaain/fokus-bar/releases/latest/download/FokusBar-1.0.0.dmg)

`macOS 14+` · `Universal Binary (Apple Silicon & Intel)` · `100 % lokal auf deinem Mac` · `Keine Cloud / Telemetrie`

*(Auf der Suche nach der Windows-Version? → [Hier geht's zu FokusBar für Windows](https://github.com/Jusaain/fokus-bar-windows))*

</div>

---

## Automatische Installation über Claude Code / Codex / Cursor

Gib einfach diesen Satz in Claude Code, Codex oder Cursor ein:
> **„Installier und starte mir bitte diese App auf meinem Mac: https://github.com/Jusaain/fokus-bar“**

---

## Manuelle Installation in 30 Sekunden (Fertige App per DMG)

1. **[`FokusBar-1.0.0.dmg` herunterladen](https://github.com/Jusaain/fokus-bar/releases/latest/download/FokusBar-1.0.0.dmg)** und doppelt anklicken.
2. **`FokusBar.app` auf „Programme“ ziehen** und anschließend aus *Programme* starten.
3. **Falls macOS beim ersten Öffnen fragt:** *Systemeinstellungen → Datenschutz & Sicherheit* öffnen und `FokusBar` über **„Dennoch öffnen“** freigeben (oder einmalig im Terminal `xattr -cr /Applications/FokusBar.app` ausführen).
4. **Beim ersten Start mit Spotify oder Web-Blocker:** Wenn macOS fragt *„FokusBar möchte Spotify / Safari / Chrome steuern“*, auf **Erlauben** klicken.

### Alternativ: 1-Befehl-Installation aus dem Quellcode
```bash
git clone https://github.com/Jusaain/fokus-bar.git
cd fokus-bar
./install.sh
```

---

## Highlights (1:1 Out-of-the-Box auf jedem Mac)

### 1. Integrierte Natur-Klänge & Spotify-Playlists (Jazz House, Courten & Deep Work)
Beim Start einer Fokus-Sitzung startet automatisch dein gewählter Sound – mit stufenlosem **Lautstärkeregler** direkt im Menüleisten-Popover, auf der laufenden Timer-Karte und auf dem schwebenden LED-Timer:
- **7 echte Natur- & Ambient-Studioaufnahmen (direkt in der App enthalten, offline nutzbar):**
  - *Sanfter Sommerregen* (`rain-gentle.m4a`)
  - *Waldruhe & Vögel* (`forest-nature.m4a`)
  - *Waldbach & Blätterwind* (`forest-stream.m4a`)
  - *Regen am Fenster* (`rain-window.m4a`)
  - *Meereswellen · Küste* (`ocean-waves.m4a`)
  - *Kaminfeuer & Regen* (`fireplace-cozy.m4a`)
  - *Entspanntes Café* (`cafe-lounge.m4a`)
- **6 kuratierte Spotify Jazz-House- & Jazz-Lounge-Playlists:**
  - *Jazz House & Soft Lounge*, *Smooth Jazz Beats*, *Jazz Vibes · Chill Beats*, *Coffee Table Jazz*, *Jazz in the Background*, *Lo-Fi Jazz Café*
- **7 kuratierte Spotify Courten- & Deep-Work-Playlists:**
  - *Courten Radio*, *This Is Courten*, *Courten · Penthouse Radio*, *Deep Focus*, *Focus Flow*, *House Focus*, *Beats to Think To*
- **Echter Zufalls-Shuffle ab dem 1. Song & Hintergrund-Steuerung:**
  - Wenn `Spotify.app` installiert ist, startet FokusBar Spotify automatisch im Hintergrund (ohne das Spotify-Fenster in den Vordergrund zu holen), aktiviert **Shuffle + Repeat** und springt sofort auf einen **zufälligen Track** der Playlist (statt immer mit Lied #1 zu starten).
  - Ist `Spotify.app` auf einem Mac nicht installiert, öffnet FokusBar die gewählte Playlist automatisch im Spotify Web-Player im Browser.

### 2. Automatische Programm- & Browser-Erkennung + App- & Webseiten-Blocker
- **Automatische App-Erkennung auf jedem Mac:**
  - FokusBar scannt beim Öffnen automatisch die laufenden Programme, die macOS LaunchServices-Datenbank sowie `/Applications`, `~/Applications` und `/System/Applications` (inkl. Unterordnern wie Setapp und Safari/Chrome Dock-Web-Apps).
  - Installierte Ablenkungs-Apps (z. B. *WhatsApp*, *Discord*, *Telegram*, *Signal*, *Slack*, *Nachrichten*, *Mail*, *Steam*, *TV*, *Podcasts*) werden automatisch mit ihren echten macOS-App-Icons als **1-Klick-Chips** direkt im Start-Bereich vorgeschlagen.
  - Sobald der Fokus startet, werden blockierte Apps automatisch geschlossen und können während der Fokus-Sitzung nicht geöffnet werden.
- **Webseiten-Blocker mit automatischer Browser-Erkennung:**
  - 1-Klick-Sperre für **Instagram** (`instagram.com`), **YouTube** (`youtube.com` / `youtu.be`), **X.com / Twitter** (`x.com` / `twitter.com`), **TikTok** (`tiktok.com`), **Reddit** (`reddit.com`), **Netflix** (`netflix.com`), **Facebook**, **Twitch**, **LinkedIn** sowie beliebige eigene Domains.
  - Erkennt automatisch installierte Browser (*Safari*, *Google Chrome*, *Arc*, *Brave*, *Microsoft Edge*, *Vivaldi*, *Opera*, *Orion*) und schließt gesperrte Tabs während des Fokus laufend im Hintergrund.

### 3. Fokus-Schutz (Durchatmen-Hürde gegen vorzeitiges Pausieren & Abbrechen)
- Wer während einer laufenden Fokus-Sitzung auf **Pause**, **Stoppen** oder **Blocker ausschalten** klickt, muss zuerst eine **30–90 Sekunden lange geführte Atem-Übung** (*4 Sek. Einatmen · 4 Sek. Halten · 4 Sek. Ausatmen*) absolvieren.
- Alle 10 Sekunden muss ein aktiver Atem-Impuls per Klick bestätigt werden (Anti-AFK), und zusätzlich muss der Satz `Ich unterbreche meinen Fokus bewusst` von Hand abgetippt werden (Copy & Paste ist gesperrt).

### 4. Frei einstellbare Fokus-Dauer & verschiebbarer LED-Timer
- Fokus-Dauer frei wählbar zwischen **1 und 240 Minuten** (Presets `15` / `25` / `45` / `60` / `90 Min.`, `−5` / `+5`-Buttons oder direkte Minuteneingabe) – auch live während einer laufenden Sitzung (`−5m` / `+5m`).
- Frei per Maus verschiebbares **schwebendes LED-Timer-Fenster** (merkt sich die Position dauerhaft) mit eigenem Musik-Lautstärkeregler, Mute-Button und Zeit-Anpassung.

---

## Entwicklung & Befehle

- `make check` – Kompiliert mit `-warnings-as-errors` und führt alle 31 XCTests (`FocusCoreTests`) aus.
- `make package` – Baut das signierte App-Bundle unter `build/FokusBar.app`.
- `make dmg` – Baut ein Universal-Binary (`arm64` + `x86_64`) und erstellt `build/FokusBar-1.0.0.dmg`.
- `make install` – Baut, installiert und startet `FokusBar.app`.
- `build/FokusBar.app/Contents/MacOS/FokusBar --self-test` – Isolierter End-to-End-Selbsttest im Arbeitsspeicher.

Ausführliche Bedienungsanleitung: [`Docs/ANLEITUNG.md`](Docs/ANLEITUNG.md) · [Alle Releases](https://github.com/Jusaain/fokus-bar/releases).
