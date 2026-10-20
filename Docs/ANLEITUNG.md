# FokusBar

Deine Aufgaben und deine Arbeitszeit, lokal auf deinem Mac.

## Schnell starten

Klicke oben in der Menüleiste auf das Häkchen. Trage eine Aufgabe ein und starte ihre Zeiterfassung über den Startknopf. Über die große Übersicht verwaltest du Details, Erinnerungen, Projekte und wiederkehrende Aufgaben. Das Schließen eines Fensters beendet die App und einen laufenden Timer nicht. Ein Rechtsklick auf das Menüleistensymbol bietet Öffnen, Einstellungen und Beenden. In der aktiven App öffnet auch ⌘⇧M das Menüleistenfenster.

## Schnelleingabe und Tastenkürzel

Im Eingabefeld für neue Aufgaben verstehst du mit kurzen Kürzeln mehr als nur den Titel. Unter dem Feld siehst du vor dem Anlegen, was erkannt wurde.

- `#Projekt` ordnet ein Projekt zu, zum Beispiel `#Website`. Ein Unterstrich wird zum Leerzeichen (`#Neue_Seite`). Vorhandene Projekte werden unabhängig von Groß- und Kleinschreibung wiedererkannt.
- `@heute`, `@morgen`, `@übermorgen` setzen die Fälligkeit. `@mo` bis `@so` (oder `@montag` …) wählen den nächsten passenden Wochentag, heute eingeschlossen. `@24.12.` oder `@24.12.2026` setzen ein Datum.
- `!` oder `!hoch` setzt hohe Priorität, `!niedrig` niedrige.

Normale Wörter wie „morgen“ ohne `@` bleiben Teil des Titels. Ist im Dashboard ein Projektfilter aktiv, erhält eine neue Aufgabe ohne `#Projekt` automatisch dieses Projekt.

Mit ⌃⌥Leertaste (Control, Option, Leertaste) öffnest du die Schnelleingabe aus jeder App heraus: Ein kleines Feld erscheint oben in der Bildschirmmitte. Du tippst die Aufgabe mit denselben Kürzeln ein, die Eingabetaste legt sie an und das Feld schließt sich. Esc schließt es und verwirft den Text, ein Klick daneben schließt es und behält den Text für das nächste Öffnen. Ein Rechtsklick auf das Menüleistensymbol bietet denselben Weg über „Neue Aufgabe …“. Das Kürzel lässt sich unter Einstellungen → System abschalten; ist es von einer anderen App belegt, steht dort ein Hinweis.

Im Dashboard springst du mit ⌘1 bis ⌘7 direkt zu Heute, Geplant, Alle Aufgaben, Erledigt, Archiv, Zeitübersicht und Einstellungen. ⌘N öffnet eine neue Aufgabe mit allen Details.

## Timer

- Stoppuhr: erfasst die Arbeitszeit ohne Zeitlimit.
- Countdown: frei gewählte Dauer von 1 bis 1.440 Minuten (inklusive Schnellwahl-Buttons für 15, 25, 45, 60 und 90 Minuten).
- Fokus: frei wählbare Arbeitsphase von 1 bis 240 Minuten direkt im Startformular (Schnellwahl 15, 25, 45, 60, 90 Min. oder eigenes Minutenfeld); danach kannst du eine Pause starten. Auch während der Timer läuft, lässt sich die Zeit jederzeit per `-5m` / `+5m` anpassen.
- Pause: Erholung ohne Arbeitszeiterfassung. Nach jeder vierten abgeschlossenen Fokusphase wird die längere Pause angeboten.

Es läuft immer nur ein Timer. Sobald ein Timer aktiv ist – egal ob Fokus, Countdown, Stoppuhr oder Pause –, erscheint auf dem Bildschirm automatisch eine kleine, LED-animierte Timeruhr. Sie zeigt die Zeit in einer leuchtenden 7-Segment-LED-Anzeige samt animierter LED-Fortschrittsleiste, stiehlt keinen Tastaturfokus, lässt sich jederzeit frei mit der Maus an jede gewünschte Bildschirmposition verschieben (Position wird gespeichert) und bietet direkte Bedienelemente für Fokus-Musik, einen integrierten LED-Lautstärkeregler, `-5`/`+5` Minuten, Pausieren, Fortsetzen und Stoppen. Unter Einstellungen → Darstellung kannst du die LED-Timeruhr bei Bedarf ein- oder ausblenden. Beim Aufgabenwechsel wird die alte Sitzung gespeichert. Pausen zählen nicht zur Arbeitszeit. Beim Ablauf stoppt die Sitzung exakt am Zielzeitpunkt. Die Aufgabe wird dadurch nicht automatisch erledigt. Sounds und Benachrichtigungen kannst du separat einstellen.

### Fokus-Musik, Natur-Klänge & Spotify (Courten, Deep Work & Jazz)

Sobald du eine Fokus-Sitzung startest, begleitet dich auf Wunsch automatisch ein entspannter Natur-Klang oder eine fokussierte Spotify-Playlist:

- **Natur & Entspannte Klänge (Direkt in FokusBar)**: *Sanfter Sommerregen*, *Waldruhe & Vögel*, *Waldbach & Blätterwind*, *Regen am Fenster*, *Meereswellen · Küste*, *Kaminfeuer & Regen* und *Entspanntes Café* – echte, warme und nahtlos geloopte Studio-Feldaufnahmen direkt in FokusBar (ohne künstliche Synthesizer-Frequenzen).
- **Spotify · Courten & Deep Work**: *Courten Radio*, *This Is Courten*, *Courten · Penthouse Radio*, *Deep Focus · Deep Work*, *Focus Flow · Lock-In*, *House Focus · Deep Work* und *Beats to Think To*. FokusBar steuert dafür direkt deine installierte Spotify-App, zeigt den aktuell laufenden Song an und bietet einen Knopf für den nächsten Track.
- **Spotify · Jazz House & Jazz Lounge**: *Jazz House & Soft Lounge*, *Smooth Jazz Beats*, *Jazz Vibes · Chill Beats*, *Coffee Table Jazz*, *Jazz in the Background* und *Lo-Fi Jazz Café*.

Du kannst den Klang und die **Lautstärke über den direkten Lautstärkeregler** sowohl vor dem Start (inklusive „Anhören“-Vorschau) als auch während des laufenden Timers im Menü, in der Dashboard-Sidebar, direkt im schwebenden LED-Timer oder unter Einstellungen → Fokus-Musik, Natur-Klänge & Spotify stufenlos anpassen oder stummschalten. In Pausen und beim Pausieren oder Beenden des Timers stoppt die Musik automatisch.

### App- & Webseiten-Blocker im Fokus

Direkt im Timer-Startformular (unter „App- & Web-Blocker“), während einer laufenden Fokus-Sitzung oder unter Einstellungen → App- & Web-Blocker + Fokus-Schutz kannst du sowohl Webseiten als auch macOS-Apps auswählen, die dich während des Fokus nicht ablenken sollen:

- **Webseiten blockieren (z. B. Instagram, YouTube, X.com, TikTok, Reddit, Netflix)**: Über die 1-Klick-Auswahl oder das Eingabefeld für eigene Domains kannst du ablenkende Webseiten hinterlegen. Sobald der Fokus läuft, schließt FokusBar offene und neu geöffnete Tabs dieser Seiten in Safari, Google Chrome, Arc, Brave und Edge automatisch im Hintergrund.
- **Apps automatisch schließen & sperren**: Sobald du den Fokus startest, werden alle ausgewählten macOS-Apps (z. B. WhatsApp, Discord, Telegram, Mail, Nachrichten) sofort ausgeblendet und beendet. Versucht eine blockierte App sich während des laufenden Fokus wieder zu öffnen, fängt FokusBar den Start sofort ab und schließt sie wieder.
- **Jederzeit erweiterbar**: Über „Auswählen / Bearbeiten“ kannst du Webseiten und Apps jederzeit ergänzen. Sobald die Pause beginnt oder der Timer regulär endet, sind alle Apps und Webseiten sofort wieder frei nutzbar.

### Fokus-Schutz (Durchatmen-Hürde gegen vorzeitiges Pausieren & Abbrechen)

Damit du deine Fokus-Sitzung nicht aus einem kurzen Ablenkungs-Impuls heraus abbrichst oder pausierst, schützt FokusBar laufende Fokus-Sitzungen mit einer interaktiven **Durchatmen-Hürde**:

- **30 bis 90 Sekunden bewusstes Durchatmen**: Klickst du während einer laufenden Fokus-Sitzung auf „Pausieren“, „Stoppen“ oder versuchst den Blocker auszuschalten, läuft der Fokus weiter und es öffnet sich der Fokus-Schutz mit einem geführten Atem-Rhythmus (*4 Sek. tief einatmen · 4 Sek. halten · 4 Sek. langsam ausatmen*).
- **Aktive Bestätigung statt Wegschauen**: Alle 10 Sekunden bestätigst du aktiv deinen Atem-Impuls per Klick und tippst abschließend den Reflexionssatz *„Ich unterbreche meinen Fokus bewusst“* ein (ohne Copy & Paste).
- **Schnell zurück in den Flow**: Mit einem Klick auf *„Weiter fokussieren (Im Flow bleiben)“* brichst du den Unterbrechungsversuch sofort ab und arbeitest fokussiert weiter. Unter Einstellungen kannst du die Dauer der Atem-Hürde zwischen 30, 45, 60 und 90 Sekunden wählen.

Beim Sperren des Macs wird eine Arbeitsphase pausiert. Beim Ruhezustand wird keine Arbeitszeit mitgezählt. Ein Countdown kann währenddessen ablaufen; der Abschluss wird nach dem Aufwachen angezeigt. Ein noch nicht abgelaufener Timer bleibt nach dem Aufwachen pausiert. Auf einem ausgeschalteten oder schlafenden Mac kann kein pünktlicher Alarmton garantiert werden.

Beenden pausiert den Timer. Nach einem unerwarteten Abbruch wird nur bis zum letzten Speicherpunkt gezählt, höchstens 15 Sekunden davor. Nach einem Neustart entscheidest du selbst, wann du fortsetzt.

## Aufgaben und Erinnerungen

Fälligkeit und Erinnerungszeit sind unabhängig. Diese lokale Installation verwendet eigene Erinnerungsfenster, da macOS seine System-Mitteilungen für diese Signatur abweist. FokusBar muss dafür laufen; ein geschlossenes Dashboard genügt, solange das Menüleistensymbol vorhanden ist. Das Erinnerungsfenster stiehlt nicht den Tastaturfokus und bietet „In 10 Minuten“ und „Erledigen“. Überfällige, noch nicht bestätigte Erinnerungen werden nach einem Neustart nachgeholt. Geschlossene Erinnerungen bleiben auch nach einem Neustart bestätigt. Unter Einstellungen kannst du eine Test-Erinnerung auslösen oder die Fenster ausschalten.

Timer-Ende erscheint ebenfalls als lokales Fenster. Sounds sind separat einstellbar. Systemlautstärke beziehungsweise stummgeschaltete Lautsprecher wirken sich auf die Hörbarkeit aus.

Eine tägliche, werktägliche, wöchentliche oder monatliche Aufgabe erzeugt beim Erledigen genau eine nächste Aufgabe. Versäumte Wiederholungen werden übersprungen. Erneutes Öffnen und Erledigen erzeugt keine Duplikate. Mehrere fällige Erinnerungen werden nacheinander angezeigt. Bei beendeter App findet keine Hintergrundzustellung durch macOS statt.

## Tagesziel

Das Tagesziel zeigt, wie viel Arbeitszeit du heute schon geschafft hast. Gezählt werden Fokus, Countdown und Stoppuhr, Pausen nicht. Voreingestellt sind 4 Stunden.

- Im Menü steht neben der heutigen Zeit ein kleiner Ring, der sich bis zum Ziel füllt. Ist das Ziel erreicht, erscheint ein Haken.
- In der Heute-Ansicht steht der Fortschritt rechts neben „x von y erledigt“, in der Sidebar unter dem Timer.
- In der Zeitübersicht markiert eine gestrichelte Linie das Ziel. Tage, an denen du es erreicht hast, sind kräftiger blau.

Unter Einstellungen → Tagesziel stellst du die Arbeitszeit pro Tag in 15-Minuten-Schritten ein (15 Minuten bis 16 Stunden) oder schaltest das Ziel ganz aus.

## Zeitübersicht

Die Wochenübersicht beginnt montags und zeigt gespeicherte Arbeitssitzungen. Die heutige Live-Summe berücksichtigt zusätzlich den laufenden Timer. Sitzungen über Mitternacht werden auf die jeweiligen Tage verteilt, auch an Wochengrenzen. Du kannst Sitzungen nachtragen, bearbeiten und mit Bestätigung entfernen. Überschneidungen sind nicht erlaubt. Das Archivieren einer Aufgabe erhält ihre bisherigen Zeiten. Unter Archiv kannst du die Aufgabe wiederherstellen.

## Daten und Sicherung

Es gibt keinen Server, kein Konto und keine Telemetrie. Aufgaben, Zeiten und Einstellungen liegen unter:

`~/Library/Application Support/FokusBar/state.json`

`previous-good.json` enthält den vorherigen erfolgreich gespeicherten Stand. Speichern erfolgt atomar. Unlesbare Daten werden nicht automatisch überschrieben. Unter Einstellungen kannst du eine vollständige JSON-Sicherung exportieren und wiederherstellen sowie gespeicherte Zeiteinträge als CSV exportieren. Wiederherstellen verlangt eine Bestätigung und sichert die bisherige Datei zusätzlich als `before-restore-….json` im Datenordner. Die CSV ist für Tabellenprogramme gegen Formelausführung abgesichert.

Autostart ist optional unter Einstellungen aktivierbar. Die App ist lokal signiert und für diesen Mac gebaut; eine öffentliche Veröffentlichung oder Apple-Notarisierung ist nicht Bestandteil dieser Installation.
