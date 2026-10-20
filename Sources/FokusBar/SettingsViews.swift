import SwiftUI
import AppKit
import FocusCore

struct SettingsScreen: View {
    @ObservedObject var store: FocusStore
    @State private var showsAppBlockerPopover = false

    private let sounds = ["Glass", "Ping", "Pop", "Hero", "Submarine"]

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Einstellungen")
                    .font(.system(size: 28, weight: .bold))
                Text("Änderungen werden sofort übernommen.")
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 32)
            .padding(.top, 26)

            Form {
                timerSection
                focusMusicSection
                appBlockerSection
                goalSection
                soundSection
                notificationSection
                appearanceSection
                systemSection
                dataSection
                quitSection
            }
            .formStyle(.grouped)
            .scrollContentBackground(.hidden)
            .padding(.horizontal, 12)
        }
        .frame(maxWidth: 780, alignment: .leading)
        .frame(maxWidth: .infinity)
    }

    // MARK: Sections

    private var timerSection: some View {
        Section {
            LabeledContent("Fokus") {
                MinutesField(value: pref(\.focusMinutes), range: 1...240, label: "Fokus in Minuten")
            }
            LabeledContent("Kurze Pause") {
                MinutesField(value: pref(\.breakMinutes), range: 1...120, label: "Kurze Pause in Minuten")
            }
            LabeledContent("Lange Pause") {
                MinutesField(value: pref(\.longBreakMinutes), range: 1...120, label: "Lange Pause in Minuten")
            }
        } header: {
            Text("Timer")
        } footer: {
            Text("Nach jeder vierten Fokus-Sitzung wird die lange Pause vorgeschlagen. Aufgaben werden nie automatisch abgehakt.")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.leading)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var focusMusicSection: some View {
        let selected = store.selectedFocusSound
        let isPreviewing = store.isPreviewingFocusSound && selected != .off

        return Section {
            HStack {
                Picker("Klang / Radio", selection: Binding(
                    get: { store.selectedFocusSound },
                    set: { store.selectFocusSound($0) }
                )) {
                    Text("Aus (Stumm)").tag(FocusSound.off)
                    ForEach(FocusSoundCategory.allCases) { category in
                        Section(category.title) {
                            ForEach(category.items) { item in
                                Text(item.title).tag(item)
                            }
                        }
                    }
                }
                Button {
                    store.toggleFocusSoundPreview()
                } label: {
                    Label(isPreviewing ? "Stoppen" : "Probehören", systemImage: isPreviewing ? "stop.fill" : "play.fill")
                }
                .help(isPreviewing ? "Vorschau beenden" : "Ausgewählten Fokus-Sound oder Courten Radio anhören")
            }

            if selected != .off {
                LabeledContent("Beschreibung") {
                    Text(store.spotifyNowPlaying.map { "Läuft auf Spotify: \($0)" } ?? selected.subtitle)
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.trailing)
                }
            }

            LabeledContent("Lautstärke") {
                HStack(spacing: 10) {
                    Slider(
                        value: Binding(
                            get: { store.preferences.effectiveFocusSoundVolume },
                            set: { store.setFocusSoundVolume($0) }
                        ),
                        in: 0.05...1.0
                    )
                    .frame(width: 180)
                    Text("\(Int((store.preferences.effectiveFocusSoundVolume * 100).rounded())) %")
                        .font(.system(size: 12.5))
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                        .frame(width: 42, alignment: .trailing)
                }
            }
            .disabled(selected == .off)

            Toggle("Auch bei Countdown und Stoppuhr abspielen", isOn: Binding(
                get: { store.preferences.playsFocusSoundInAllWorkModes },
                set: { enabled in
                    var draft = store.preferences
                    draft.focusSoundAllWorkModes = enabled
                    store.savePreferences(draft)
                }
            ))

            if selected.isSpotify {
                LabeledContent("Spotify-Steuerung") {
                    HStack(spacing: 8) {
                        Button("Nächster Track") { store.skipSpotifyTrack() }
                        Button("In Spotify öffnen") { store.openActiveSoundInSpotify() }
                    }
                }
            }
        } header: {
            Text("Fokus-Musik, Natur-Klänge & Spotify")
        } footer: {
            Text("Startet automatisch beim Beginn einer Fokus-Sitzung und pausiert in Pausen oder beim Anhalten. Die 7 Natur-Klänge (Sanfter Sommerregen, Waldruhe & Vögel, Waldbach, Regen am Fenster, Meereswellen, Kaminfeuer, Café) laufen als echte, nahtlose Studio-Aufnahmen direkt in FokusBar. Die Spotify-Playlists für Courten, Deep Work, Jazz House und Jazz Lounge steuern automatisch deine Spotify-App.")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.leading)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var appBlockerSection: some View {
        let blockedApps = store.blockedApps
        let blockedSites = store.blockedWebsites

        return Section {
            Toggle("Ausgewählte Apps & Webseiten während Fokus-Sitzungen blockieren", isOn: Binding(
                get: { store.preferences.isAppBlockerEnabled },
                set: { store.setAppBlockerEnabled($0) }
            ))

            LabeledContent("Webseiten & Apps (\(store.totalBlockedItemsCount))") {
                HStack(spacing: 8) {
                    Button {
                        showsAppBlockerPopover = true
                    } label: {
                        Label("Webseiten & Apps auswählen …", systemImage: "lock.shield")
                    }
                    .popover(isPresented: $showsAppBlockerPopover, arrowEdge: .bottom) {
                        BlockedAppSelectorPopover(store: store)
                    }

                    Button {
                        store.pickBlockedAppFromFinder()
                    } label: {
                        Label("Aus Programme-Ordner …", systemImage: "folder.badge.plus")
                    }
                }
            }

            LabeledContent("Schnellauswahl Webseiten") {
                HStack(spacing: 6) {
                    ForEach(BlockedWebsite.presets.prefix(5)) { preset in
                        let isSelected = store.isWebsiteBlocked(preset.domain)
                        Button {
                            store.toggleBlockedWebsite(preset.domain)
                        } label: {
                            HStack(spacing: 4) {
                                Image(systemName: isSelected ? "checkmark.circle.fill" : preset.icon)
                                    .font(.system(size: 10, weight: .semibold))
                                Text(preset.title.replacingOccurrences(of: " (Twitter)", with: ""))
                                    .font(.system(size: 11.5, weight: .medium))
                            }
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .foregroundStyle(isSelected ? Color.white : Color.primary)
                            .background(
                                Capsule()
                                    .fill(isSelected ? FokusTheme.accent : FokusTheme.track)
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }
            }

            if !blockedSites.isEmpty {
                VStack(alignment: .leading, spacing: 5) {
                    Text("Blockierte Webseiten (\(blockedSites.count))")
                        .font(.system(size: 11.5, weight: .semibold))
                        .foregroundStyle(.secondary)
                    ForEach(blockedSites, id: \.self) { domain in
                        HStack(spacing: 8) {
                            Image(systemName: BlockedWebsite.icon(for: domain))
                                .font(.system(size: 13))
                                .foregroundStyle(FokusTheme.accent)
                                .frame(width: 18)
                            Text(BlockedWebsite.displayName(for: domain))
                                .font(.system(size: 13, weight: .medium))
                            Text(domain)
                                .font(.system(size: 11))
                                .foregroundStyle(.tertiary)
                            Spacer()
                            Button {
                                store.removeBlockedWebsite(domain)
                            } label: {
                                Image(systemName: "trash")
                                    .font(.system(size: 12))
                                    .foregroundStyle(.secondary)
                            }
                            .buttonStyle(.borderless)
                        }
                    }
                }
                .padding(.vertical, 2)
            }

            if !blockedApps.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Blockierte Apps (\(blockedApps.count))")
                        .font(.system(size: 11.5, weight: .semibold))
                        .foregroundStyle(.secondary)
                    ForEach(blockedApps) { app in
                        HStack(spacing: 8) {
                            BlockedAppIconView(app: app, size: 18)
                            Text(app.name)
                                .font(.system(size: 13, weight: .medium))
                            Text(app.bundleIdentifier)
                                .font(.system(size: 11))
                                .foregroundStyle(.tertiary)
                                .lineLimit(1)
                            Spacer()
                            Button {
                                store.removeBlockedApp(app)
                            } label: {
                                Image(systemName: "trash")
                                    .font(.system(size: 12))
                                    .foregroundStyle(.secondary)
                            }
                            .buttonStyle(.borderless)
                            .help("\(app.name) aus der Blockierliste entfernen")
                        }
                    }
                }
                .padding(.vertical, 2)
            }

            Toggle("Pausieren & Abbrechen durch Atem-Übung erschweren (Fokus-Schutz)", isOn: Binding(
                get: { store.preferences.isFocusGuardEnabled },
                set: { store.setFocusGuardEnabled($0) }
            ))

            if store.preferences.isFocusGuardEnabled {
                Picker("Dauer der Durchatmen-Hürde", selection: Binding(
                    get: { store.preferences.effectiveFocusGuardSeconds },
                    set: { store.setFocusGuardSeconds($0) }
                )) {
                    Text("30 Sekunden Durchatmen").tag(30)
                    Text("45 Sekunden Durchatmen").tag(45)
                    Text("1 Minute (60 Sek.) Durchatmen").tag(60)
                    Text("90 Sekunden Durchatmen").tag(90)
                }
            }

            Toggle("Auch bei Countdown und Stoppuhr blockieren & schützen", isOn: Binding(
                get: { store.preferences.blocksAppsInAllWorkModes },
                set: { enabled in
                    var draft = store.preferences
                    draft.blockAppsInAllWorkModes = enabled
                    store.savePreferences(draft)
                }
            ))
        } header: {
            Text("App- & Web-Blocker + Fokus-Schutz")
        } footer: {
            Text("Sobald du eine Fokus-Sitzung startest, werden ausgewählte Apps (z. B. WhatsApp, Discord) und Webseiten (z. B. Instagram, YouTube, X.com) automatisch geschlossen. Willst du den Fokus vorzeitig pausieren oder abbrechen, musst du erst die 30–60 Sekunden lange Durchatmen-Übung und den Bestätigungssatz absolvieren.")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.leading)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var goalSection: some View {
        Section {
            Toggle("Tagesziel anzeigen", isOn: goalEnabled)
            if store.preferences.dailyGoal > 0 {
                LabeledContent("Arbeitszeit pro Tag") {
                    HStack(spacing: 10) {
                        Text(FokusFormat.hours(store.preferences.dailyGoal))
                            .foregroundStyle(.secondary)
                        MinutesField(value: goalMinutes, range: 15...960, label: "Tagesziel in Minuten", step: 15)
                    }
                }
            }
        } header: {
            Text("Tagesziel")
        } footer: {
            Text("Zählt Fokus, Countdown und Stoppuhr, keine Pausen. Den Fortschritt siehst du im Menü, in der Heute-Ansicht und in der Zeitübersicht.")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.leading)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var goalEnabled: Binding<Bool> {
        Binding(
            get: { store.preferences.dailyGoal > 0 },
            set: { enabled in
                var draft = store.preferences
                draft.dailyGoalMinutes = enabled ? Preferences.defaultDailyGoalMinutes : 0
                store.savePreferences(draft)
            }
        )
    }

    private var goalMinutes: Binding<Int> {
        Binding(
            get: { store.preferences.dailyGoalMinutes ?? Preferences.defaultDailyGoalMinutes },
            set: { value in
                var draft = store.preferences
                draft.dailyGoalMinutes = value
                store.savePreferences(draft)
            }
        )
    }

    private var soundSection: some View {
        Section("Signalton am Timer-Ende") {
            Toggle("Signaltöne für Timer und Erinnerungen", isOn: pref(\.soundEnabled))
            HStack {
                Picker("Signalton", selection: soundBinding) {
                    ForEach(sounds, id: \.self) { Text($0).tag($0) }
                }
                Button {
                    store.previewSound()
                } label: {
                    Label("Anhören", systemImage: "speaker.wave.2")
                }
                .help("Signalton abspielen")
            }
            .disabled(!store.preferences.soundEnabled)
        }
    }

    private var notificationSection: some View {
        let status = notificationState
        return Section {
            Toggle("Mitteilungen anzeigen", isOn: pref(\.notificationsEnabled))
            LabeledContent(store.usesLocalAlerts ? "Zustellung" : "Systemberechtigung") {
                HStack(spacing: 6) {
                    Circle()
                        .fill(status.color)
                        .frame(width: 8, height: 8)
                        .accessibilityHidden(true)
                    Text(status.text)
                }
            }
            HStack(alignment: .firstTextBaseline) {
                Text(store.usesLocalAlerts
                     ? "Erinnerungen erscheinen als eigenes Fenster mit Ton. FokusBar muss dafür laufen. Ein geschlossener Mac wird nicht geweckt."
                     : status.granted ? "FokusBar darf Mitteilungen senden."
                     : "Ohne Berechtigung erscheinen keine macOS-Mitteilungen. Das Timer-Ende bleibt in FokusBar sichtbar. Abgelehnte Berechtigungen lassen sich in Systemeinstellungen > Mitteilungen ändern.")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer()
                Button(store.usesLocalAlerts ? "Test-Erinnerung" : "Berechtigung anfragen") { store.requestNotifications() }
                    .disabled(status.granted && !store.usesLocalAlerts)
            }
        } header: {
            Text("Mitteilungen")
        }
    }

    private var appearanceSection: some View {
        Section {
            Picker("Erscheinungsbild", selection: pref(\.appearance)) {
                Text("System").tag("system")
                Text("Hell").tag("light")
                Text("Dunkel").tag("dark")
            }
            .pickerStyle(.segmented)
            Toggle("Laufende Zeit in der Menüleiste anzeigen", isOn: pref(\.showMenuTime))
            Toggle("LED-Timeruhr oben rechts einblenden", isOn: Binding(
                get: { store.preferences.showFloatingTimer },
                set: { enabled in
                    var draft = store.preferences
                    draft.floatingTimer = enabled
                    store.savePreferences(draft)
                }
            ))
            if store.preferences.showFloatingTimer {
                HStack(spacing: 10) {
                    Text("Größe der LED-Timeruhr")
                    Spacer()
                    ForEach([0.65, 0.80, 1.00, 1.15], id: \.self) { preset in
                        let pct = Int((preset * 100).rounded())
                        let isSelected = abs(Double(FloatingTimerSizing.shared.scale) - preset) < 0.04
                        Button("\(pct)%") {
                            FloatingTimerSizing.shared.setScale(CGFloat(preset))
                        }
                        .buttonStyle(.bordered)
                        .tint(isSelected ? FokusTheme.accent : nil)
                        .controlSize(.small)
                    }
                }
            }
        } header: {
            Text("Darstellung")
        } footer: {
            Text("Sobald ein Fokus, Countdown, eine Stoppuhr oder Pause läuft, erscheint auf dem Bildschirm die schwebende LED-Timeruhr. Du kannst sie frei verschieben und an den unteren Ecken (oder per Trackpad-Pinch) stufenlos kleiner oder größer ziehen.")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.leading)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var systemSection: some View {
        Section {
            Toggle("Bei der Anmeldung automatisch starten", isOn: Binding(
                get: { store.launchAtLogin },
                set: { store.setLaunchAtLogin($0) }
            ))
            Toggle("Schnelleingabe mit \(GlobalHotKey.displayName)", isOn: Binding(
                get: { store.preferences.quickEntryEnabled },
                set: { enabled in
                    var draft = store.preferences
                    draft.quickEntryHotKey = enabled
                    store.savePreferences(draft)
                }
            ))
        } header: {
            Text("System")
        } footer: {
            Text(store.preferences.quickEntryEnabled && !store.quickEntryHotKeyAvailable
                 ? "\(GlobalHotKey.displayName) ist bereits von einer anderen App belegt. Gib das Kürzel dort frei und schalte die Schnelleingabe einmal aus und wieder ein."
                 : "Die Schnelleingabe öffnet aus jeder App ein kleines Eingabefeld für eine neue Aufgabe. FokusBar muss dafür laufen.")
                .font(.system(size: 12))
                .foregroundStyle(store.preferences.quickEntryEnabled && !store.quickEntryHotKeyAvailable ? Color.orange : Color.secondary)
                .multilineTextAlignment(.leading)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var dataSection: some View {
        Section {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: "lock.shield")
                    .font(.system(size: 18))
                    .foregroundStyle(FokusTheme.accent)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 3) {
                    Text("Alles bleibt auf diesem Mac")
                        .font(.system(size: 13, weight: .semibold))
                    Text("Aufgaben, Zeiten und Einstellungen werden ausschließlich lokal gespeichert. FokusBar braucht kein Konto und überträgt keine Daten.")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(.vertical, 2)

            if store.storageBlocked {
                Label("Speichern ist gerade gesperrt, damit vorhandene Daten nicht überschrieben werden. Eine Sicherung wiederherzustellen kann helfen.", systemImage: "exclamationmark.triangle.fill")
                    .font(.system(size: 12))
                    .foregroundStyle(.orange)
                    .fixedSize(horizontal: false, vertical: true)
            }

            LabeledContent {
                Button("Exportieren…") { store.exportBackup() }
            } label: {
                Text("Sicherung exportieren")
                Text("Vollständige Kopie aller Daten als Datei")
            }
            LabeledContent {
                Button("Wiederherstellen…") { store.importBackup() }
            } label: {
                Text("Sicherung wiederherstellen")
                Text("Ersetzt die aktuellen Daten. Vorher wird automatisch eine Sicherung angelegt.")
            }
            LabeledContent {
                Button("CSV exportieren…") { store.exportCSV() }
            } label: {
                Text("Zeiten als CSV")
                Text("Für Tabellenkalkulation und Abrechnung")
            }
        } header: {
            Text("Daten")
        }
    }

    private var quitSection: some View {
        Section {
            LabeledContent {
                Button("Beenden") { store.quit() }
            } label: {
                Text("FokusBar beenden")
                Text("Schließt die App und entfernt das Symbol aus der Menüleiste.")
            }
        }
    }

    // MARK: Bindings

    private func pref<Value>(_ keyPath: WritableKeyPath<Preferences, Value>) -> Binding<Value> {
        Binding(
            get: { store.preferences[keyPath: keyPath] },
            set: { value in
                var draft = store.preferences
                draft[keyPath: keyPath] = value
                store.savePreferences(draft)
            }
        )
    }

    private var soundBinding: Binding<String> {
        Binding(
            get: { store.preferences.sound },
            set: { value in
                var draft = store.preferences
                draft.sound = value
                store.savePreferences(draft)
                store.previewSound()
            }
        )
    }

    private var notificationState: (text: String, color: Color, granted: Bool) {
        let raw = store.notificationStatus
        switch raw.fokusTrimmed.lowercased() {
        case "authorized", "granted", "erlaubt", "aktiv":
            return ("Erlaubt", FokusTheme.accent, true)
        case "provisional", "ephemeral":
            return ("Vorläufig erlaubt", FokusTheme.accent, true)
        case "denied", "abgelehnt", "nicht erlaubt":
            return ("Abgelehnt", Color.red, false)
        case "notdetermined", "not determined", "unknown", "", "nicht angefragt", "noch nicht angefragt":
            return ("Noch nicht angefragt", Color.orange, false)
        default:
            return (raw, Color.secondary, false)
        }
    }
}
