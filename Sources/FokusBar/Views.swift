import SwiftUI
import AppKit
import FocusCore

// MARK: - Menu bar panel

struct MenuPanel: View {
    @ObservedObject var store: FocusStore
    @State private var quickTitle = ""
    @State private var archiveCandidate: FocusTask?
    @AppStorage("fokus.ui.menuShowsCompleted") private var showsCompleted = false

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    if StatusBanners.hasContent(store) {
                        StatusBanners(store: store)
                    }
                    timerSection
                    todaySection
                }
                .padding(16)
            }
            Divider()
            footer
        }
        .frame(width: 420, height: 660)
        .background(FokusTheme.canvas)
        .tint(FokusTheme.accent)
        .archiveConfirmation(candidate: $archiveCandidate, store: store)
    }

    private var header: some View {
        HStack(spacing: 10) {
            AppGlyph(size: 30)
            VStack(alignment: .leading, spacing: 1) {
                Text("FokusBar")
                    .font(.system(size: 14, weight: .semibold))
                Text(FokusFormat.longDate(store.now))
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }
            Spacer()
            let goal = store.preferences.dailyGoal
            HStack(spacing: 9) {
                VStack(alignment: .trailing, spacing: 1) {
                    Text(TimeFormat.short(store.todaySeconds))
                        .font(.system(size: 14, weight: .semibold))
                        .monospacedDigit()
                    Text(goal <= 0 ? "heute erfasst" : store.todaySeconds >= goal ? "Tagesziel erreicht" : "von \(FokusFormat.hours(goal)) Ziel")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
                if goal > 0 {
                    ZStack {
                        ProgressRing(value: store.todaySeconds / goal, color: FokusTheme.accent, track: FokusTheme.track, lineWidth: 3.5)
                        if store.todaySeconds >= goal {
                            Image(systemName: "checkmark")
                                .font(.system(size: 10, weight: .bold))
                                .foregroundStyle(FokusTheme.accent)
                        }
                    }
                    .frame(width: 26, height: 26)
                }
            }
            .accessibilityElement(children: .combine)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    @ViewBuilder private var timerSection: some View {
        if let active = store.active {
            ActiveTimerCard(store: store, active: active)
        } else {
            TimerStartForm(store: store)
        }
    }

    private var todaySection: some View {
        let open = TaskQuery.sorted(store.tasks.filter { TaskQuery.belongsToToday($0, now: store.now) }, now: store.now)
        let done = TaskQuery.completedToday(store.tasks, now: store.now)
        return VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .center) {
                Text("Heute")
                    .font(.system(size: 17, weight: .semibold))
                Spacer()
                if open.isEmpty && done.isEmpty {
                    Text("Nichts offen")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                } else {
                    DayProgress(done: done.count, total: open.count + done.count, width: 110)
                }
            }
            QuickAddField(placeholder: "Neue Aufgabe für heute", text: $quickTitle, projects: store.projects) { title in
                store.addQuickTask(title)
            }

            if open.isEmpty && done.isEmpty {
                emptyToday
            } else {
                if open.isEmpty {
                    allDoneCard
                } else {
                    taskCard(open)
                }
                if !done.isEmpty {
                    completedToggle(count: done.count)
                    if showsCompleted { taskCard(done) }
                }
            }
        }
    }

    private func taskCard(_ tasks: [FocusTask]) -> some View {
        VStack(spacing: 0) {
            ForEach(Array(tasks.enumerated()), id: \.element.id) { index, task in
                if index > 0 { Divider().padding(.leading, 34) }
                TaskRow(store: store, task: task, hidesTodayDate: true, onArchive: { archiveCandidate = task })
            }
        }
        .padding(.horizontal, 12)
        .fokusCard(padding: 0)
    }

    private func completedToggle(count: Int) -> some View {
        Button {
            withAnimation(.easeOut(duration: 0.15)) { showsCompleted.toggle() }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "chevron.right")
                    .font(.system(size: 10, weight: .semibold))
                    .rotationEffect(.degrees(showsCompleted ? 90 : 0))
                Text("Heute erledigt")
                    .font(.system(size: 13, weight: .semibold))
                Text("\(count)")
                    .font(.system(size: 12))
                    .foregroundStyle(.tertiary)
                Spacer()
            }
            .foregroundStyle(.secondary)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .padding(.leading, 4)
        .accessibilityLabel(showsCompleted ? "Erledigte Aufgaben ausblenden" : "Erledigte Aufgaben einblenden")
    }

    private var emptyToday: some View {
        VStack(spacing: 8) {
            Image(systemName: "sun.max")
                .font(.system(size: 26, weight: .light))
                .foregroundStyle(FokusTheme.accent)
            Text(store.tasks.isEmpty ? "Noch keine Aufgaben" : "Für heute ist alles frei")
                .font(.system(size: 14, weight: .semibold))
            Text(store.tasks.isEmpty
                 ? "Gib oben eine Aufgabe ein und drücke die Eingabetaste. Mehr Details kannst du im Dashboard ergänzen."
                 : "Aufgaben ohne Datum und alles, was heute fällig ist, erscheint hier.")
                .font(.system(size: 12.5))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.vertical, 22)
        .padding(.horizontal, 20)
        .frame(maxWidth: .infinity)
        .fokusCard(padding: 0)
    }

    private var allDoneCard: some View {
        HStack(spacing: 10) {
            Image(systemName: "checkmark.seal")
                .font(.system(size: 20))
                .foregroundStyle(FokusTheme.accent)
            VStack(alignment: .leading, spacing: 2) {
                Text("Alles erledigt für heute")
                    .font(.system(size: 14, weight: .semibold))
                Text("Gute Arbeit. Neue Aufgaben kannst du oben jederzeit ergänzen.")
                    .font(.system(size: 12.5))
                    .foregroundStyle(.secondary)
            }
        }
        .fokusCard()
    }

    private var footer: some View {
        HStack(spacing: 8) {
            Button {
                store.openDashboard()
            } label: {
                Label("Dashboard", systemImage: "macwindow")
            }
            .buttonStyle(FokusSoftButtonStyle())
            Button {
                store.openSettings()
            } label: {
                Label("Einstellungen", systemImage: "gearshape")
            }
            .buttonStyle(FokusSoftButtonStyle(color: .secondary))
            Spacer()
            Button {
                store.quit()
            } label: {
                Label("Beenden", systemImage: "power")
            }
            .buttonStyle(.borderless)
            .foregroundStyle(.secondary)
            .help("FokusBar beenden")
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 11)
    }
}

// MARK: - Banners

struct FokusBanner: View {
    enum Kind { case error, warning, info, success }

    let kind: Kind
    let title: String
    var message: String? = nil
    var dismiss: (() -> Void)? = nil

    private var color: Color {
        switch kind {
        case .error: .red
        case .warning: .orange
        case .info: FokusTheme.rest
        case .success: FokusTheme.accent
        }
    }

    private var icon: String {
        switch kind {
        case .error: "exclamationmark.octagon.fill"
        case .warning: "exclamationmark.triangle.fill"
        case .info: "info.circle.fill"
        case .success: "checkmark.circle.fill"
        }
    }

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(color)
                .padding(.top, 1)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.system(size: 13, weight: .semibold))
                    .fixedSize(horizontal: false, vertical: true)
                if let message {
                    Text(message)
                        .font(.system(size: 12.5))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 4)
            if let dismiss {
                Button(action: dismiss) {
                    Image(systemName: "xmark")
                        .font(.system(size: 10, weight: .bold))
                        .frame(width: 18, height: 18)
                }
                .buttonStyle(.borderless)
                .foregroundStyle(.secondary)
                .help("Schließen")
                .accessibilityLabel("Hinweis schließen")
            }
        }
        .fokusCard(padding: 12, tint: color)
    }
}

struct StatusBanners: View {
    @ObservedObject var store: FocusStore

    @MainActor static func hasContent(_ store: FocusStore) -> Bool {
        store.storageBlocked || store.errorMessage != nil || store.notice != nil || store.finishedMode != nil
    }

    var body: some View {
        VStack(spacing: 8) {
            if store.storageBlocked {
                FokusBanner(
                    kind: .warning,
                    title: "Speichern ist vorübergehend gesperrt",
                    message: "Die lokalen Daten konnten nicht sicher gelesen werden. Damit nichts überschrieben wird, speichert FokusBar vorerst keine Änderungen. In den Einstellungen kannst du eine Sicherung wiederherstellen."
                )
            }
            if let error = store.errorMessage {
                FokusBanner(kind: .error, title: error, dismiss: { store.errorMessage = nil })
            }
            if let notice = store.notice {
                FokusBanner(kind: .success, title: notice, dismiss: { store.notice = nil })
                    .task(id: notice) {
                        try? await Task.sleep(for: .seconds(6))
                        if store.notice == notice { store.notice = nil }
                    }
            }
            FinishBanner(store: store)
        }
    }
}

struct FinishBanner: View {
    @ObservedObject var store: FocusStore

    var body: some View {
        if let mode = store.finishedMode {
            content(for: mode)
        }
    }

    private func content(for mode: TimerMode) -> some View {
        let color = FokusTheme.modeColor(mode)
        let longBreak = TimerChoice.longBreakDue(store)
        let prefs = store.preferences
        let title: String
        let message: String
        switch mode {
        case .focus:
            title = "Fokuszeit geschafft"
            message = longBreak
                ? "Vier Sitzungen am Stück. Zeit für eine lange Pause von \(prefs.longBreakMinutes) Min."
                : "Gönn dir eine kurze Pause von \(prefs.breakMinutes) Min., bevor es weitergeht."
        case .rest:
            title = "Pause vorbei"
            message = "Bereit für die nächste Fokus-Sitzung mit \(prefs.focusMinutes) Min.?"
        case .countdown:
            title = "Countdown abgelaufen"
            message = "Die Zeit wurde erfasst. Die Aufgabe bleibt offen, bis du sie abhakst."
        case .stopwatch:
            title = "Timer beendet"
            message = "Die Zeit wurde erfasst."
        }

        return VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: mode == .rest ? "bell.badge" : "checkmark.circle.fill")
                    .font(.system(size: 20))
                    .foregroundStyle(color)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 3) {
                    Text(title)
                        .font(.system(size: 15, weight: .semibold))
                    Text(message)
                        .font(.system(size: 12.5))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
            }
            HStack(spacing: 8) {
                switch mode {
                case .focus:
                    Button {
                        store.startBreak()
                    } label: {
                        Label(longBreak ? "Lange Pause starten" : "Pause starten", systemImage: "cup.and.saucer.fill")
                    }
                    .buttonStyle(FokusFilledButtonStyle(color: FokusTheme.rest))
                    Button("Weiter fokussieren") { store.startNextFocus() }
                        .buttonStyle(FokusSoftButtonStyle())
                case .rest:
                    Button {
                        store.startNextFocus()
                    } label: {
                        Label("Nächsten Fokus starten", systemImage: "play.fill")
                    }
                    .buttonStyle(FokusFilledButtonStyle())
                case .countdown, .stopwatch:
                    EmptyView()
                }
                Spacer(minLength: 0)
                Button("Schließen") { store.finishedMode = nil }
                    .buttonStyle(FokusSoftButtonStyle(color: .secondary))
            }
        }
        .fokusCard(padding: 14, tint: color)
    }
}

// MARK: - Timer

struct ActiveTimerCard: View {
    @ObservedObject var store: FocusStore
    let active: ActiveTimer

    var body: some View {
        let elapsed = active.elapsed(at: store.now)
        let progress = active.target > 0 ? min(1, max(0, elapsed / active.target)) : 0
        let sessions = store.state.completedFocusSessions
        let longBreak = TimerChoice.longBreakDue(store)
        let deep = active.mode.isWork ? FokusTheme.accentDeep : FokusTheme.restDeep

        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 8) {
                Label(active.mode.title, systemImage: FokusTheme.icon(for: active.mode))
                    .font(.system(size: 12, weight: .semibold))
                    .padding(.horizontal, 9)
                    .padding(.vertical, 4)
                    .background(Capsule().fill(Color.white.opacity(0.18)))
                RunStateLabel(isRunning: active.isRunning)
                Spacer()
                if active.mode == .focus || active.mode == .rest {
                    Text(active.mode == .focus ? "Sitzung \(sessions % 4 + 1) von 4" : (longBreak ? "Lange Pause" : "Kurze Pause"))
                        .font(.system(size: 11.5))
                        .foregroundStyle(.white.opacity(0.8))
                    FocusDots(filled: active.mode == .rest && longBreak ? 4 : sessions % 4, color: .white)
                }
            }

            HStack(alignment: .center, spacing: 16) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(active.mode == .rest ? "Zeit zum Durchatmen" : active.title)
                        .font(.system(size: 16, weight: .semibold))
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                    if active.mode == .rest {
                        Text("Pausen zählen nicht als Arbeitszeit.")
                            .font(.system(size: 12.5))
                            .foregroundStyle(.white.opacity(0.75))
                    } else if !active.project.isEmpty {
                        Label(active.project, systemImage: "folder")
                            .font(.system(size: 12.5))
                            .foregroundStyle(.white.opacity(0.75))
                    }
                    Text(store.timerText)
                        .font(.system(size: 46, weight: .light, design: .rounded))
                        .monospacedDigit()
                        .opacity(active.isRunning ? 1 : 0.6)
                        .padding(.top, 2)
                        .accessibilityLabel("\(active.mode == .stopwatch ? "Vergangene" : "Verbleibende") Zeit \(store.timerText)")
                    HStack(spacing: 6) {
                        Text(active.mode == .stopwatch
                             ? "vergangen"
                             : "\(TimeFormat.clock(elapsed)) von \(TimeFormat.short(active.target))")
                            .font(.system(size: 12))
                            .foregroundStyle(.white.opacity(0.75))
                            .monospacedDigit()
                            .lineLimit(1)
                            .fixedSize()

                        if active.mode != .stopwatch {
                            HStack(spacing: 4) {
                                Button("-5m") {
                                    store.adjustActiveTimerMinutes(-5)
                                }
                                .buttonStyle(.plain)
                                .font(.system(size: 10, weight: .semibold, design: .rounded))
                                .padding(.horizontal, 5.5)
                                .padding(.vertical, 2)
                                .foregroundStyle(.white.opacity(0.9))
                                .background(Capsule().fill(Color.white.opacity(0.16)))
                                .help("5 Minuten verkürzen")

                                Button("+5m") {
                                    store.adjustActiveTimerMinutes(5)
                                }
                                .buttonStyle(.plain)
                                .font(.system(size: 10, weight: .semibold, design: .rounded))
                                .padding(.horizontal, 5.5)
                                .padding(.vertical, 2)
                                .foregroundStyle(.white.opacity(0.9))
                                .background(Capsule().fill(Color.white.opacity(0.16)))
                                .help("5 Minuten verlängern")
                            }
                        }
                    }
                }
                Spacer(minLength: 0)
                if active.mode != .stopwatch {
                    ZStack {
                        ProgressRing(value: progress, lineWidth: 7)
                        VStack(spacing: 0) {
                            Text("\(Int(progress * 100)) %")
                                .font(.system(size: 16, weight: .semibold, design: .rounded))
                                .monospacedDigit()
                            Text("geschafft")
                                .font(.system(size: 10.5))
                                .foregroundStyle(.white.opacity(0.75))
                        }
                    }
                    .frame(width: 96, height: 96)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel("Fortschritt")
                    .accessibilityValue("\(Int(progress * 100)) Prozent")
                } else {
                    Image(systemName: "stopwatch")
                        .font(.system(size: 34, weight: .light))
                        .frame(width: 96, height: 96)
                        .background(Circle().fill(Color.white.opacity(0.12)))
                        .accessibilityHidden(true)
                }
            }

            if let intent = store.pendingFocusGuardIntent {
                FocusGuardChallengeCard(store: store, intent: intent)
                    .environment(\.colorScheme, .light)
            } else {
                if active.mode.isWork {
                    ActiveFocusSoundBar(store: store, active: active)
                    if active.mode == .focus || store.preferences.blocksAppsInAllWorkModes || store.totalBlockedItemsCount > 0 {
                        ActiveAppBlockerBar(store: store, active: active)
                    }
                }

                HStack(spacing: 8) {
                    Button {
                        if active.isRunning { store.requestPauseTimer() } else { store.resumeTimer() }
                    } label: {
                        Label(
                            active.isRunning ? (store.isFocusGuardRequired ? "Pausieren 🔒" : "Pausieren") : "Fortsetzen",
                            systemImage: active.isRunning ? "pause.fill" : "play.fill"
                        )
                        .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(FokusFilledButtonStyle(color: .white, large: true, foreground: deep))
                    .help(active.isRunning && store.isFocusGuardRequired ? "Pausieren erfordert \(store.preferences.effectiveFocusGuardSeconds) Sek. Durchatmen-Übung" : "")

                    Button {
                        store.requestStopTimer()
                    } label: {
                        Label(
                            active.mode == .rest ? "Pause beenden" : (store.isFocusGuardRequired ? "Stoppen 🔒" : "Stoppen"),
                            systemImage: "stop.fill"
                        )
                        .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(FokusSoftButtonStyle(large: true, onHero: true))
                    .help(active.isRunning && store.isFocusGuardRequired ? "Beenden erfordert \(store.preferences.effectiveFocusGuardSeconds) Sek. Durchatmen-Übung" : "")
                }
            }
        }
        .fokusHero(active.mode, padding: 18)
    }
}

struct ActiveFocusSoundBar: View {
    @ObservedObject var store: FocusStore
    let active: ActiveTimer

    var body: some View {
        let sound = store.selectedFocusSound
        let isMuted = sound == .off
        let isPlaying = store.isFocusSoundPlaying
        let subtitle: String = if isMuted {
            "Tippe links zum Einschalten oder wähle Natur-Sound / Spotify"
        } else if let track = store.spotifyNowPlaying, sound.isSpotify {
            "Läuft: \(track)"
        } else {
            sound.subtitle
        }

        VStack(alignment: .leading, spacing: 7) {
            HStack(spacing: 10) {
                Button {
                    store.toggleFocusSoundMute()
                } label: {
                    Image(systemName: isMuted ? "speaker.slash.fill" : sound.icon)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(isMuted ? Color.white.opacity(0.65) : Color.white)
                        .frame(width: 30, height: 30)
                        .background(
                            Circle()
                                .fill(Color.white.opacity(isMuted ? 0.12 : 0.24))
                        )
                }
                .buttonStyle(.plain)
                .help(isMuted ? "Fokus-Musik einschalten" : "Fokus-Musik stummschalten")
                .accessibilityLabel(isMuted ? "Fokus-Musik einschalten" : "Fokus-Musik stummschalten")

                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Menu {
                            FocusSoundMenuItems(store: store)
                        } label: {
                            Text(isMuted ? "Fokus-Musik: Aus" : sound.shortTitle)
                                .font(.system(size: 12.5, weight: .semibold))
                                .foregroundStyle(.white)
                                .lineLimit(1)
                        }
                        .menuStyle(.borderlessButton)
                        .menuIndicator(.visible)
                        .tint(.white)
                        .fixedSize()

                        Text(sound.badge)
                            .font(.system(size: 9.5, weight: .bold, design: .rounded))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 1.5)
                            .background(Capsule().fill(Color.white.opacity(isPlaying ? 0.22 : 0.14)))
                            .foregroundStyle(.white.opacity(0.95))
                            .fixedSize()

                        Spacer(minLength: 0)
                    }

                    Text(subtitle)
                        .font(.system(size: 11))
                        .foregroundStyle(.white.opacity(0.78))
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                if sound.isSpotify && !isMuted {
                    Button {
                        store.skipSpotifyTrack()
                    } label: {
                        Image(systemName: "forward.end.fill")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(.white.opacity(0.92))
                            .frame(width: 26, height: 26)
                            .background(Circle().fill(Color.white.opacity(0.18)))
                    }
                    .buttonStyle(.plain)
                    .help("Nächster Track in Spotify")
                    .accessibilityLabel("Nächster Track in Spotify")
                }
            }

            Divider()
                .overlay(Color.white.opacity(0.14))

            FocusVolumeSlider(store: store, onHero: true)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 11, style: .continuous)
                .fill(Color.white.opacity(0.13))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 11, style: .continuous)
                .strokeBorder(Color.white.opacity(0.14), lineWidth: 0.8)
        )
    }
}

struct FocusVolumeSlider: View {
    @ObservedObject var store: FocusStore
    var onHero: Bool = false
    var compact: Bool = false

    private func speakerIcon(for volume: Double, isMuted: Bool) -> String {
        if isMuted { return "speaker.slash.fill" }
        if volume < 0.35 { return "speaker.wave.1.fill" }
        if volume < 0.72 { return "speaker.wave.2.fill" }
        return "speaker.wave.3.fill"
    }

    var body: some View {
        let isMuted = store.selectedFocusSound == .off
        let volume = store.preferences.effectiveFocusSoundVolume
        let displayFraction = isMuted ? 0.0 : min(1.0, max(0.0, volume))
        let pct = isMuted ? "Stumm" : "\(Int((volume * 100).rounded())) %"

        HStack(spacing: compact ? 6 : 8) {
            Button {
                store.toggleFocusSoundMute()
            } label: {
                Image(systemName: speakerIcon(for: volume, isMuted: isMuted))
                    .font(.system(size: compact ? 10 : 11, weight: .semibold))
                    .foregroundStyle(onHero ? Color.white.opacity(isMuted ? 0.6 : 0.9) : (isMuted ? Color.secondary : FokusTheme.accent))
                    .frame(width: 16, alignment: .center)
            }
            .buttonStyle(.plain)
            .help(isMuted ? "Ton einschalten" : "Stummschalten")

            GeometryReader { geo in
                let width = max(1, geo.size.width)
                let thumbSize: CGFloat = compact ? 10 : 12
                let trackHeight: CGFloat = compact ? 4.5 : 5.5
                let fillWidth = max(0, min(width, width * displayFraction))
                let thumbX = max(thumbSize / 2, min(width - thumbSize / 2, fillWidth))

                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(onHero ? Color.white.opacity(0.22) : Color.primary.opacity(0.12))
                        .frame(height: trackHeight)

                    Capsule()
                        .fill(onHero ? Color.white.opacity(0.92) : FokusTheme.accent)
                        .frame(width: fillWidth, height: trackHeight)

                    if !isMuted {
                        Circle()
                            .fill(onHero ? Color.white : FokusTheme.accent)
                            .frame(width: thumbSize, height: thumbSize)
                            .shadow(color: Color.black.opacity(0.22), radius: 1.5, x: 0, y: 1)
                            .position(x: thumbX, y: geo.size.height / 2)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .contentShape(Rectangle())
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { value in
                            let raw = Double(value.location.x / width)
                            let clamped = min(1.0, max(0.05, raw))
                            store.setFocusSoundVolume(clamped, unmuteIfOff: true)
                        }
                )
            }
            .frame(height: compact ? 14 : 16)

            Text(pct)
                .font(.system(size: compact ? 10 : 11, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(onHero ? Color.white.opacity(0.88) : Color.secondary)
                .frame(width: compact ? 36 : 40, alignment: .trailing)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Musik-Lautstärke")
        .accessibilityValue(pct)
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment:
                store.setFocusSoundVolume(min(1.0, volume + 0.1), unmuteIfOff: true)
            case .decrement:
                store.setFocusSoundVolume(max(0.05, volume - 0.1), unmuteIfOff: true)
            @unknown default:
                break
            }
        }
    }
}

struct FocusSoundMenuItems: View {
    @ObservedObject var store: FocusStore

    private let volumeSteps: [Double] = [0.25, 0.45, 0.65, 0.85, 1.0]

    var body: some View {
        let current = store.selectedFocusSound

        ForEach(FocusSoundCategory.allCases) { category in
            Section(category.title) {
                ForEach(category.items) { item in
                    Button {
                        store.selectFocusSound(item)
                    } label: {
                        HStack {
                            Label(item.title, systemImage: item.icon)
                            if item == current {
                                Image(systemName: "checkmark")
                            }
                        }
                    }
                }
            }
        }

        Divider()

        Button {
            store.selectFocusSound(.off)
        } label: {
            HStack {
                Label("Aus (Stumm)", systemImage: "speaker.slash")
                if current == .off {
                    Image(systemName: "checkmark")
                }
            }
        }

        Divider()

        Menu("Lautstärke (\(Int((store.preferences.effectiveFocusSoundVolume * 100).rounded())) %)") {
            ForEach(volumeSteps, id: \.self) { level in
                let active = abs(store.preferences.effectiveFocusSoundVolume - level) < 0.06
                Button {
                    store.setFocusSoundVolume(level)
                } label: {
                    HStack {
                        Text("\(Int((level * 100).rounded())) %")
                        if active { Image(systemName: "checkmark") }
                    }
                }
            }
        }

        if current.isSpotify {
            Divider()
            Button {
                store.skipSpotifyTrack()
            } label: {
                Label("Nächster Track in Spotify", systemImage: "forward.end")
            }
            Button {
                store.openActiveSoundInSpotify()
            } label: {
                Label("In Spotify öffnen", systemImage: "arrow.up.right.square")
            }
        }
    }
}

struct FocusSoundStartPicker: View {
    @ObservedObject var store: FocusStore

    private let natureRow: [FocusSound] = [.gentleRain, .forestNature, .forestStream]
    private let deepWorkRow: [FocusSound] = [.courtenRadio, .deepFocus, .houseFocus]
    private let jazzRow: [FocusSound] = [.jazzHouseLounge, .smoothJazzBeats, .coffeeTableJazz]

    var body: some View {
        let selected = store.selectedFocusSound
        let isPlayingPreview = store.isPreviewingFocusSound && selected != .off

        VStack(alignment: .leading, spacing: 7) {
            HStack(spacing: 6) {
                Label("Fokus-Musik", systemImage: selected == .off ? "speaker.slash" : selected.icon)
                    .font(.system(size: 12.5, weight: .semibold))
                    .foregroundStyle(selected == .off ? Color.secondary : FokusTheme.accent)
                    .lineLimit(1)
                    .fixedSize()

                Spacer(minLength: 4)

                if selected.isSpotify {
                    Button {
                        store.openActiveSoundInSpotify()
                    } label: {
                        HStack(spacing: 3) {
                            Image(systemName: "arrow.up.right.square")
                                .font(.system(size: 9.5, weight: .semibold))
                            Text("Spotify")
                                .font(.system(size: 10.5, weight: .medium))
                        }
                        .padding(.horizontal, 7)
                        .padding(.vertical, 3.5)
                        .foregroundStyle(FokusTheme.accent)
                        .background(
                            Capsule()
                                .fill(FokusTheme.accent.opacity(0.10))
                        )
                    }
                    .buttonStyle(.plain)
                    .fixedSize()
                    .help("Ausgewählte Playlist direkt in Spotify öffnen")
                }

                Button {
                    store.toggleFocusSoundPreview()
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: isPlayingPreview ? "stop.fill" : "play.fill")
                            .font(.system(size: 9, weight: .bold))
                        Text(isPlayingPreview ? "Stopp" : "Anhören")
                            .font(.system(size: 11, weight: .medium))
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3.5)
                    .foregroundStyle(isPlayingPreview ? Color.white : FokusTheme.accent)
                    .background(
                        Capsule()
                            .fill(isPlayingPreview ? FokusTheme.accent : FokusTheme.accent.opacity(0.12))
                    )
                }
                .buttonStyle(.plain)
                .fixedSize()
                .help(isPlayingPreview ? "Vorschau beenden" : "Ausgewählten Fokus-Sound vorab anhören")

                Menu {
                    FocusSoundMenuItems(store: store)
                } label: {
                    Text(selected.shortTitle)
                        .font(.system(size: 11.5, weight: .semibold))
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
                .padding(.horizontal, 6)
                .padding(.vertical, 2.5)
                .background(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(FokusTheme.track)
                )
            }

            VStack(spacing: 5) {
                pillRow(items: natureRow, selected: selected)
                pillRow(items: deepWorkRow, selected: selected)
                pillRow(items: jazzRow, selected: selected)
            }

            FocusVolumeSlider(store: store, onHero: false)

            HStack(spacing: 6) {
                Text(selected.badge)
                    .font(.system(size: 9, weight: .bold, design: .rounded))
                    .padding(.horizontal, 5.5)
                    .padding(.vertical, 1.5)
                    .foregroundStyle(selected == .off ? Color.secondary : FokusTheme.accent)
                    .background(
                        Capsule()
                            .fill(selected == .off ? FokusTheme.track : FokusTheme.accent.opacity(0.12))
                    )
                    .fixedSize()

                Text(store.spotifyNowPlaying.map { "Spotify: \($0)" } ?? selected.subtitle)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(FokusTheme.track.opacity(0.55))
        )
    }

    private func pillRow(items: [FocusSound], selected: FocusSound) -> some View {
        HStack(spacing: 5) {
            ForEach(items) { item in
                let isSelected = item == selected
                Button {
                    store.selectFocusSound(item)
                } label: {
                    HStack(spacing: 3.5) {
                        Image(systemName: item.icon)
                            .font(.system(size: 9.5, weight: .semibold))
                        Text(item.shortTitle)
                            .font(.system(size: 10.5, weight: .medium))
                            .lineLimit(1)
                            .minimumScaleFactor(0.85)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 4.5)
                    .padding(.horizontal, 4)
                    .foregroundStyle(isSelected ? Color.white : Color.secondary)
                    .background(
                        RoundedRectangle(cornerRadius: 7, style: .continuous)
                            .fill(isSelected ? AnyShapeStyle(FokusTheme.accent) : AnyShapeStyle(FokusTheme.track))
                    )
                }
                .buttonStyle(.plain)
            }
        }
    }
}

struct RunStateLabel: View {
    let isRunning: Bool

    var body: some View {
        HStack(spacing: 5) {
            Circle()
                .fill(Color.white.opacity(isRunning ? 1 : 0.45))
                .frame(width: 6, height: 6)
            Text(isRunning ? "läuft" : "pausiert")
        }
        .font(.system(size: 12))
        .foregroundStyle(.white.opacity(0.85))
        .accessibilityElement(children: .combine)
    }
}

struct TimerStartForm: View {
    @ObservedObject var store: FocusStore
    var showsCard = true
    var onStart: (() -> Void)? = nil

    @AppStorage(TimerChoiceKeys.mode) private var modeRaw = TimerMode.focus.rawValue
    @AppStorage(TimerChoiceKeys.countdown) private var countdownMinutes = 25
    @State private var taskID: UUID?

    private var mode: TimerMode { TimerMode(rawValue: modeRaw) ?? .focus }
    private var openTasks: [FocusTask] { TaskQuery.sorted(store.tasks.filter { !$0.isCompleted }, now: store.now) }

    var body: some View {
        if showsCard {
            content.fokusCard(padding: 16)
        } else {
            content.padding(16)
        }
    }

    private var content: some View {
        let color = FokusTheme.modeColor(mode)
        return VStack(alignment: .leading, spacing: 13) {
            HStack {
                Text("Timer")
                    .font(.system(size: 15, weight: .semibold))
                Spacer()
                Text("Bereit")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }

            ModeSelector(mode: Binding(get: { mode }, set: { modeRaw = $0.rawValue }))

            modeDetail

            if mode != .rest {
                FocusSoundStartPicker(store: store)

                if mode == .focus || store.preferences.blocksAppsInAllWorkModes {
                    FocusAppBlockerStartPicker(store: store)
                }

                Picker("Aufgabe", selection: taskBinding) {
                    Text("Ohne Aufgabe").tag(UUID?.none)
                    if !openTasks.isEmpty { Divider() }
                    ForEach(openTasks) { task in
                        Text(task.title).tag(Optional(task.id))
                    }
                }
                .pickerStyle(.menu)
            }

            Button {
                TimerChoice.start(store, task: openTasks.first { $0.id == taskBinding.wrappedValue }, mode: mode, countdown: countdownMinutes)
                onStart?()
            } label: {
                Label("\(mode.title) starten", systemImage: "play.fill")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(FokusFilledButtonStyle(color: color, large: true))
        }
    }

    private var taskBinding: Binding<UUID?> {
        Binding(
            get: { openTasks.contains { $0.id == taskID } ? taskID : nil },
            set: { taskID = $0 }
        )
    }

    @ViewBuilder private var modeDetail: some View {
        let prefs = store.preferences
        switch mode {
        case .stopwatch:
            hint("Zählt hoch, bis du beendest. Ideal für offene Aufgaben ohne festes Ende.")
        case .countdown:
            VStack(alignment: .leading, spacing: 7) {
                HStack {
                    Text("Dauer")
                        .font(.system(size: 12.5, weight: .medium))
                    Spacer()
                    MinutesField(value: $countdownMinutes, range: 1...1440, label: "Countdown in Minuten")
                }
                durationPresetRow(selected: countdownMinutes) { countdownMinutes = $0 }
            }
        case .focus:
            VStack(alignment: .leading, spacing: 7) {
                HStack {
                    Text("Fokus-Dauer")
                        .font(.system(size: 12.5, weight: .medium))
                    Spacer()
                    MinutesField(
                        value: Binding(
                            get: { store.preferences.focusMinutes },
                            set: { store.setFocusMinutes($0) }
                        ),
                        range: 1...240,
                        label: "Fokus in Minuten"
                    )
                }
                durationPresetRow(selected: prefs.focusMinutes) { store.setFocusMinutes($0) }
                cycleRow
            }
        case .rest:
            VStack(alignment: .leading, spacing: 6) {
                hint(TimerChoice.longBreakDue(store)
                     ? "Lange Pause mit \(prefs.longBreakMinutes) Min. Pausen zählen nicht als Arbeitszeit."
                     : "Kurze Pause mit \(prefs.breakMinutes) Min. Pausen zählen nicht als Arbeitszeit.")
                cycleRow
            }
        }
    }

    private func durationPresetRow(selected: Int, onSelect: @escaping (Int) -> Void) -> some View {
        HStack(spacing: 5) {
            ForEach([15, 25, 45, 60, 90], id: \.self) { preset in
                let isSelected = selected == preset
                Button {
                    onSelect(preset)
                } label: {
                    Text("\(preset) Min.")
                        .font(.system(size: 11, weight: isSelected ? .semibold : .medium, design: .rounded))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 4)
                        .foregroundStyle(isSelected ? Color.white : Color.secondary)
                        .background(
                            RoundedRectangle(cornerRadius: 6, style: .continuous)
                                .fill(isSelected ? AnyShapeStyle(FokusTheme.accent) : AnyShapeStyle(FokusTheme.track))
                        )
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var cycleRow: some View {
        let sessions = store.state.completedFocusSessions
        return HStack(spacing: 8) {
            FocusDots(filled: TimerChoice.longBreakDue(store) ? 4 : sessions % 4, color: FokusTheme.accent)
            Text(sessions == 1 ? "1 Fokus-Sitzung abgeschlossen" : "\(sessions) Fokus-Sitzungen abgeschlossen")
                .font(.system(size: 11.5))
                .foregroundStyle(.secondary)
        }
    }

    private func hint(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 12.5))
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
    }
}

// MARK: - Task row

struct TaskRow: View {
    @ObservedObject var store: FocusStore
    let task: FocusTask
    var detailed = false
    var hidesTodayDate = false
    var onEdit: (() -> Void)? = nil
    var onArchive: () -> Void

    @AppStorage(TimerChoiceKeys.mode) private var modeRaw = TimerMode.focus.rawValue
    @AppStorage(TimerChoiceKeys.countdown) private var countdownMinutes = 25
    @State private var hovering = false
    @State private var hoveringCheck = false

    private var preferredMode: TimerMode {
        let mode = TimerMode(rawValue: modeRaw) ?? .focus
        return mode == .rest ? .focus : mode
    }

    private var notesPreview: String {
        task.notes.fokusTrimmed.replacingOccurrences(of: "\n", with: " ")
    }

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            completionButton
            VStack(alignment: .leading, spacing: 4) {
                Text(task.title)
                    .font(.system(size: detailed ? 15 : 14))
                    .strikethrough(task.isCompleted, color: .secondary)
                    .foregroundStyle(task.isCompleted ? Color.secondary : Color.primary)
                    .lineLimit(3)
                    .fixedSize(horizontal: false, vertical: true)
                if detailed, !notesPreview.isEmpty {
                    Text(notesPreview)
                        .font(.system(size: 12.5))
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
                TaskMetaLine(store: store, task: task, detailed: detailed, hidesTodayDate: hidesTodayDate)
            }
            .padding(.top, 2)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
            .onTapGesture(count: 2) { if let onEdit { onEdit() } else { store.editTask(task) } }
            actions
        }
        .padding(.vertical, detailed ? 11 : 9)
        .padding(.horizontal, 6)
        .background {
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .fill(hovering ? FokusTheme.hover : Color.clear)
        }
        .padding(.horizontal, -6)
        .onHover { hovering = $0 }
        .animation(.easeOut(duration: 0.12), value: hovering)
        .contextMenu { menuItems }
    }

    private var completionButton: some View {
        Button {
            withAnimation(.easeOut(duration: 0.15)) { store.toggleTask(task) }
        } label: {
            Image(systemName: task.isCompleted ? "checkmark.circle.fill" : (hoveringCheck ? "checkmark.circle" : "circle"))
                .font(.system(size: 19))
                .foregroundStyle(task.isCompleted || hoveringCheck ? FokusTheme.accent : (task.priority == .high ? Color.orange : Color.secondary.opacity(0.7)))
                .frame(width: 24, height: 24)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hoveringCheck = $0 }
        .help(task.isCompleted ? "Wieder öffnen" : "Als erledigt markieren")
        .accessibilityLabel(task.isCompleted ? "\(task.title) wieder öffnen" : "\(task.title) als erledigt markieren")
    }

    private var actions: some View {
        HStack(spacing: 2) {
            timerButton
            Menu {
                menuItems
            } label: {
                Image(systemName: "ellipsis")
                    .font(.system(size: 13, weight: .medium))
                    .frame(width: 24, height: 24)
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
            .help("Weitere Aktionen")
            .accessibilityLabel("Weitere Aktionen für \(task.title)")
        }
    }

    @ViewBuilder private var timerButton: some View {
        if let active = store.active, active.taskID == task.id {
            Button {
                if active.isRunning { store.requestPauseTimer() } else { store.resumeTimer() }
            } label: {
                Image(systemName: active.isRunning ? "pause.circle.fill" : "play.circle.fill")
                    .font(.system(size: 20))
                    .foregroundStyle(FokusTheme.accent)
                    .frame(width: 26, height: 26)
            }
            .buttonStyle(.borderless)
            .help(active.isRunning ? "Timer pausieren" : "Timer fortsetzen")
            .accessibilityLabel(active.isRunning ? "Timer pausieren" : "Timer fortsetzen")
        } else if !task.isCompleted {
            Button {
                TimerChoice.start(store, task: task, mode: preferredMode, countdown: countdownMinutes)
            } label: {
                Image(systemName: hovering ? "play.circle.fill" : "play.circle")
                    .font(.system(size: 20))
                    .foregroundStyle(hovering ? FokusTheme.accent : Color.secondary.opacity(0.6))
                    .frame(width: 26, height: 26)
            }
            .buttonStyle(.borderless)
            .help("\(TimerChoice.describe(preferredMode, store: store, countdown: countdownMinutes)) starten")
            .accessibilityLabel("Timer für \(task.title) starten")
        }
    }

    @ViewBuilder private var menuItems: some View {
        Button {
            if let onEdit { onEdit() } else { store.editTask(task) }
        } label: {
            Label("Bearbeiten…", systemImage: "pencil")
        }
        Button {
            store.toggleTask(task)
        } label: {
            Label(task.isCompleted ? "Wieder öffnen" : "Als erledigt markieren", systemImage: task.isCompleted ? "arrow.uturn.backward" : "checkmark")
        }
        if !task.isCompleted {
            Menu {
                ForEach([TimerMode.stopwatch, .focus, .countdown]) { mode in
                    Button(TimerChoice.describe(mode, store: store, countdown: countdownMinutes)) {
                        TimerChoice.start(store, task: task, mode: mode, countdown: countdownMinutes)
                    }
                }
            } label: {
                Label("Timer starten", systemImage: "play")
            }
        }
        Divider()
        Button(role: .destructive) {
            onArchive()
        } label: {
            Label("Archivieren…", systemImage: "archivebox")
        }
    }
}

struct TaskMetaLine: View {
    @ObservedObject var store: FocusStore
    let task: FocusTask
    var detailed: Bool
    var hidesTodayDate = false

    private struct Item: Identifiable {
        let id: String
        let text: String
        let icon: String
        var color: Color = .secondary
    }

    private var items: [Item] {
        let now = store.now
        var result: [Item] = []
        if let active = store.active, active.taskID == task.id {
            result.append(Item(id: "timer", text: active.isRunning ? "Timer läuft" : "Timer pausiert", icon: "record.circle", color: FokusTheme.accent))
        }
        if task.priority == .high {
            result.append(Item(id: "priority", text: "Hoch", icon: "exclamationmark.circle", color: .orange))
        } else if detailed && task.priority == .low {
            result.append(Item(id: "priority", text: "Niedrig", icon: "arrow.down.circle"))
        }
        let project = task.project.fokusTrimmed
        if !project.isEmpty {
            result.append(Item(id: "project", text: project, icon: "folder"))
        }
        if let completed = task.completedAt {
            result.append(Item(id: "done", text: FokusFormat.completedText(completed, now: now), icon: "checkmark"))
        } else {
            if let due = task.dueDate, !(hidesTodayDate && Calendar.current.isDate(due, inSameDayAs: now)) {
                let overdue = TaskQuery.isOverdue(task, now: now)
                let day = FokusFormat.dayTitle(due, now: now)
                result.append(Item(id: "due", text: overdue ? "Überfällig, \(day)" : day, icon: "calendar", color: overdue ? .red : .secondary))
            }
            if let reminder = task.reminder, detailed || reminder > now {
                result.append(Item(id: "reminder", text: FokusFormat.reminderText(reminder, now: now), icon: "bell"))
            }
        }
        if task.recurrence != .none {
            result.append(Item(id: "repeat", text: task.recurrence.title, icon: "repeat"))
        }
        let tracked = store.seconds(for: task.id)
        if tracked > 0 {
            result.append(Item(id: "tracked", text: TimeFormat.short(tracked), icon: "clock"))
        }
        return result
    }

    var body: some View {
        let list = items
        if !list.isEmpty {
            MetadataFlow {
                ForEach(list) { item in
                    Label(item.text, systemImage: item.icon)
                        .labelStyle(MetaLabelStyle())
                        .foregroundStyle(item.color)
                        .lineLimit(1)
                }
            }
            .font(.system(size: 11.5))
        }
    }
}

struct MetaLabelStyle: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 3) {
            configuration.icon.imageScale(.small)
            configuration.title
        }
    }
}

// MARK: - Sidebar timer (dashboard)

struct SidebarTimerPanel: View {
    @ObservedObject var store: FocusStore
    @State private var showsStart = false

    var body: some View {
        if let active = store.active {
            activeContent(active)
        } else {
            idleContent
        }
    }

    private func activeContent(_ active: ActiveTimer) -> some View {
        let elapsed = active.elapsed(at: store.now)
        let deep = active.mode.isWork ? FokusTheme.accentDeep : FokusTheme.restDeep
        return VStack(alignment: .leading, spacing: 8) {
            HStack {
                Label(active.mode.title, systemImage: FokusTheme.icon(for: active.mode))
                    .font(.system(size: 11.5, weight: .semibold))
                Spacer()
                RunStateLabel(isRunning: active.isRunning)
            }
            Text(active.mode == .rest ? "Pause" : active.title)
                .font(.system(size: 13, weight: .medium))
                .lineLimit(2)
            HStack(alignment: .center) {
                Text(store.timerText)
                    .font(.system(size: 28, weight: .light, design: .rounded))
                    .monospacedDigit()
                    .opacity(active.isRunning ? 1 : 0.6)
                    .accessibilityLabel("Timer \(store.timerText)")
                Spacer(minLength: 4)
                if active.mode != .stopwatch, active.target > 0 {
                    ProgressRing(value: elapsed / active.target, lineWidth: 4)
                        .frame(width: 30, height: 30)
                        .accessibilityLabel("Fortschritt")
                }
            }
            if active.mode != .rest {
                let sound = store.selectedFocusSound
                let isMuted = sound == .off
                VStack(alignment: .leading, spacing: 5) {
                    HStack(spacing: 6) {
                        Button {
                            store.toggleFocusSoundMute()
                        } label: {
                            Image(systemName: isMuted ? "speaker.slash.fill" : sound.icon)
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(.white.opacity(isMuted ? 0.65 : 1))
                                .frame(width: 22, height: 22)
                                .background(Circle().fill(Color.white.opacity(isMuted ? 0.12 : 0.22)))
                        }
                        .buttonStyle(.plain)
                        .help(isMuted ? "Fokus-Musik einschalten" : "Fokus-Musik stummschalten")

                        Menu {
                            FocusSoundMenuItems(store: store)
                        } label: {
                            Text(isMuted ? "Musik: Aus" : sound.shortTitle)
                                .font(.system(size: 11.5, weight: .semibold))
                                .foregroundStyle(.white)
                                .lineLimit(1)
                        }
                        .menuStyle(.borderlessButton)
                        .menuIndicator(.visible)
                        .tint(.white)

                        Spacer(minLength: 0)

                        if sound.isSpotify && !isMuted {
                            Button {
                                store.skipSpotifyTrack()
                            } label: {
                                Image(systemName: "forward.end.fill")
                                    .font(.system(size: 10, weight: .semibold))
                                    .foregroundStyle(.white.opacity(0.9))
                                    .frame(width: 20, height: 20)
                                    .background(Circle().fill(Color.white.opacity(0.15)))
                            }
                            .buttonStyle(.plain)
                            .help("Nächster Track in Spotify")
                        }
                    }

                    FocusVolumeSlider(store: store, onHero: true, compact: true)
                }
                .padding(.horizontal, 7)
                .padding(.vertical, 6)
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(Color.white.opacity(0.12))
                )
            }
            HStack(spacing: 6) {
                Button {
                    if active.isRunning { store.requestPauseTimer() } else { store.resumeTimer() }
                } label: {
                    Label(active.isRunning ? (store.isFocusGuardRequired ? "Pausieren 🔒" : "Pausieren") : "Fortsetzen", systemImage: active.isRunning ? "pause.fill" : "play.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(FokusFilledButtonStyle(color: .white, foreground: deep))
                Button {
                    store.requestStopTimer()
                } label: {
                    Image(systemName: "stop.fill")
                        .frame(width: 18)
                }
                .buttonStyle(FokusSoftButtonStyle(onHero: true))
                .help("Timer beenden")
                .accessibilityLabel("Timer beenden")
            }
        }
        .fokusHero(active.mode, padding: 12)
    }

    private var idleContent: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Kein Timer aktiv")
                .font(.system(size: 13, weight: .medium))
            let goal = store.preferences.dailyGoal
            Text(goal > 0 ? "Heute: \(TimeFormat.short(store.todaySeconds)) von \(FokusFormat.hours(goal))" : "Heute erfasst: \(TimeFormat.short(store.todaySeconds))")
                .font(.system(size: 11.5))
                .foregroundStyle(.secondary)
                .monospacedDigit()
            if goal > 0 {
                FokusProgressBar(value: store.todaySeconds / goal, height: 4)
            }
            Button {
                showsStart = true
            } label: {
                Label("Timer starten", systemImage: "play.fill")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(FokusFilledButtonStyle())
            .popover(isPresented: $showsStart, arrowEdge: .trailing) {
                TimerStartForm(store: store, showsCard: false, onStart: { showsStart = false })
                    .frame(width: 390)
                    .tint(FokusTheme.accent)
            }
        }
        .fokusCard(padding: 12)
    }
}

struct LocalReminderView: View {
    @ObservedObject var store: FocusStore
    var body: some View {
        if let alert = store.localAlerts.first {
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    Label(alert.title, systemImage: "bell.badge.fill").font(.headline).foregroundStyle(FokusTheme.accent)
                    Spacer()
                    if store.localAlerts.count > 1 { Text("+\(store.localAlerts.count - 1)").font(.caption).foregroundStyle(.secondary) }
                    Button { store.dismissAlert(alert) } label: { Image(systemName: "xmark") }.buttonStyle(.plain).accessibilityLabel("Erinnerung schließen")
                }
                Text(alert.message).font(.system(size: 16, weight: .medium)).lineLimit(3).frame(maxWidth: .infinity, alignment: .leading)
                Spacer(minLength: 0)
                HStack {
                    if alert.taskID != nil {
                        Button("In 10 Minuten") { store.snoozeAlert(alert) }.buttonStyle(FokusSoftButtonStyle(large: true))
                        Button("Erledigen") { store.completeAlert(alert) }.buttonStyle(FokusFilledButtonStyle(large: true))
                    } else {
                        Button("Öffnen") { store.openDashboard(); store.dismissAlert(alert) }.buttonStyle(FokusFilledButtonStyle(large: true))
                        Button("Schließen") { store.dismissAlert(alert) }.buttonStyle(FokusSoftButtonStyle(large: true))
                    }
                }
            }.padding(20).frame(width: 400, height: 210).background(FokusTheme.canvas)
        }
    }
}
