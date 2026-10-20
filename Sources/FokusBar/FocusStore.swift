import AppKit
import SwiftUI
import Combine
import UserNotifications
import ServiceManagement
import UniformTypeIdentifiers
import FocusCore

struct LocalAlert: Identifiable {
    var id = UUID()
    var title: String
    var message: String
    var taskID: UUID?
    var reminderKey: String?
}

@MainActor
final class FocusStore: NSObject, ObservableObject, UNUserNotificationCenterDelegate {
    @Published var state = AppState()
    @Published var now = Date()
    @Published var errorMessage: String?
    @Published var notice: String?
    @Published var finishedMode: TimerMode?
    @Published var notificationStatus = "Wird geprüft …"
    @Published var launchAtLogin = false
    @Published var storageBlocked = false
    @Published var requestedSection = "today"
    @Published var requestedTaskID: UUID?
    @Published var localAlerts: [LocalAlert] = []
    @Published var quickEntryHotKeyAvailable = true
    @Published var isPreviewingFocusSound = false
    @Published var spotifyNowPlaying: String?
    @Published var pendingFocusGuardIntent: FocusGuardIntent?
    var dashboardAction: (() -> Void)?
    var settingsAction: (() -> Void)?
    var timerChanged: (() -> Void)?
    var alertChanged: (() -> Void)?
    var focusGuardChanged: (() -> Void)?
    var usesLocalAlerts: Bool { preview || Bundle.main.object(forInfoDictionaryKey: "FokusBarLocalNotificationsOnly") as? Bool == true }
    private let repository: LocalRepository?
    private let preview: Bool
    private let focusAudio: FocusAudioController
    private let appBlocker: AppBlockerController
    private var clock: AnyCancellable?
    private var observers: [NSObjectProtocol] = []
    private var lastPersist = Date()
    private var scheduleRevision = 0
    private var notificationTask: Task<Void, Never>?
    private var lastSchedule = Date.distantPast
    private var sleepAt: Date?
    var tasks: [FocusTask] { state.tasks.filter { !$0.archived } }
    var entries: [TimeEntry] { state.entries }
    var active: ActiveTimer? { state.active }
    var preferences: Preferences { state.preferences }
    var selectedFocusSound: FocusSound { preferences.selectedFocusSound }
    var isFocusSoundPlaying: Bool {
        guard selectedFocusSound != .off else { return false }
        if let active = state.active, active.isRunning, preferences.shouldPlayFocusSound(for: active.mode) {
            return true
        }
        return isPreviewingFocusSound
    }
    var blockedApps: [BlockedApp] { preferences.effectiveBlockedApps }
    var blockedWebsites: [String] { preferences.effectiveBlockedWebsites }
    var totalBlockedItemsCount: Int { preferences.totalBlockedItemsCount }
    var isAppBlockerActive: Bool {
        guard let active = state.active, active.isRunning else { return false }
        return preferences.shouldBlockApps(for: active.mode)
    }
    var isFocusGuardRequired: Bool {
        guard let active = state.active, active.isRunning else { return false }
        return preferences.shouldRequireFocusGuard(for: active.mode)
    }
    var projects: [String] { Array(Set(tasks.map(\.project).filter { !$0.isEmpty })).sorted { $0.localizedStandardCompare($1) == .orderedAscending } }
    var todaySeconds: TimeInterval {
        var values = entries
        if let timer = active, timer.mode.isWork, let start = timer.segmentStart {
            values.append(TimeEntry(start: start, end: min(now, timer.deadline ?? now)))
        }
        return Statistics.seconds(entries: values, in: Statistics.interval(forDay: now))
    }
    var timerText: String {
        guard let active else { return "00:00" }
        return TimeFormat.clock(active.mode == .stopwatch ? active.elapsed(at: now) : ceil(active.remaining(at: now)))
    }
    init(preview: Bool = false) {
        self.preview = preview
        self.focusAudio = FocusAudioController(preview: preview)
        self.appBlocker = AppBlockerController(preview: preview)
        repository = preview ? nil : LocalRepository(directory: FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("FokusBar", isDirectory: true))
        super.init()
        focusAudio.onNowPlayingChanged = { [weak self] track in self?.spotifyNowPlaying = track }
        appBlocker.onAppBlocked = { [weak self] appName in
            self?.notice = "🔒 \(appName) ist während deiner Fokus-Sitzung blockiert."
        }
        appBlocker.onWebsiteBlocked = { [weak self] siteName in
            self?.notice = "🔒 \(siteName) wurde während deiner Fokus-Sitzung im Browser geschlossen."
        }
        if preview { notificationStatus = "Lokale Erinnerungsfenster" }
        if let repository {
            do {
                state = try repository.load()
                if TimerEngine.recover(state: &state, at: now) {
                    notice = "Deine letzte Sitzung ist pausiert. Gesichert wurde die Zeit bis zum letzten Speicherpunkt."
                    try repository.save(state)
                }
            } catch {
                storageBlocked = true
                errorMessage = "Die lokalen Daten konnten nicht sicher geladen werden. Die Originaldatei bleibt erhalten. Stelle unter Einstellungen eine Sicherung wieder her. \(error.localizedDescription)"
            }
        }
        if preview && (ProcessInfo.processInfo.arguments.contains("--ui-test") || ProcessInfo.processInfo.arguments.contains("--local-alert-test")) {
            clock = Timer.publish(every: 1, on: .main, in: .common).autoconnect().sink { [weak self] date in self?.tick(date) }
        }
        if !preview {
            if !usesLocalAlerts {
                UNUserNotificationCenter.current().delegate = self
                registerNotificationActions()
            }
            refreshAuthorization()
            launchAtLogin = SMAppService.mainApp.status == .enabled
            clock = Timer.publish(every: 1, on: .main, in: .common).autoconnect().sink { [weak self] date in self?.tick(date) }
            let center = NSWorkspace.shared.notificationCenter
            observers.append(center.addObserver(forName: NSWorkspace.willSleepNotification, object: nil, queue: .main) { [weak self] _ in MainActor.assumeIsolated { self?.willSleep() } })
            observers.append(center.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { [weak self] _ in MainActor.assumeIsolated { self?.didWake() } })
            observers.append(center.addObserver(forName: NSWorkspace.sessionDidResignActiveNotification, object: nil, queue: .main) { [weak self] _ in MainActor.assumeIsolated { self?.pauseForLock() } })
            rescheduleNotifications()
            syncFocusAudio()
            syncAppBlocker()
        }
    }
    @discardableResult private func commit(_ mutate: (inout AppState) -> Void, notifications: Bool = true) -> Bool {
        guard !storageBlocked else { return false }
        var next = state
        mutate(&next)
        next.lastCheckpoint = Date()
        do {
            _ = try next.validated()
            try repository?.save(next)
            let remindersChanged = state.tasks != next.tasks || state.preferences != next.preferences
            if next.active?.isRunning == true { isPreviewingFocusSound = false }
            state = next; lastPersist = Date(); now = Date()
            if notifications && remindersChanged { rescheduleNotifications() }
            syncFocusAudio()
            syncAppBlocker()
            timerChanged?()
            return true
        } catch {
            errorMessage = "Speichern fehlgeschlagen. Die Änderung wurde nicht übernommen. \(error.localizedDescription)"
            return false
        }
    }
    /// Understands `#Projekt`, `@morgen`/`@fr`/`@24.12.` and `!` for high priority.
    @discardableResult func addQuickTask(_ input: String, defaultProject: String = "") -> Bool {
        let parsed = QuickAddParser.parse(input, now: Date(), knownProjects: projects)
        return saveTask(FocusTask(title: parsed.title, project: parsed.project ?? defaultProject, priority: parsed.priority ?? .normal, dueDate: parsed.dueDate))
    }
    @discardableResult func saveTask(_ value: FocusTask) -> Bool {
        var task = value
        task.title = task.title.trimmingCharacters(in: .whitespacesAndNewlines)
        task.project = task.project.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !task.title.isEmpty else { errorMessage = "Bitte gib deiner Aufgabe einen Titel."; return false }
        guard task.title.count <= 500, task.notes.count <= 50_000, task.project.count <= 100 else { errorMessage = "Titel, Notiz oder Projektname ist zu lang."; return false }
        let old = state.tasks.first { $0.id == task.id }
        if let reminder = task.reminder, reminder <= Date(), old?.reminder != reminder { errorMessage = "Die Erinnerung muss in der Zukunft liegen."; return false }
        let saved = commit { state in
            if let index = state.tasks.firstIndex(where: { $0.id == task.id }) { state.tasks[index] = task } else { state.tasks.append(task) }
            if state.active?.taskID == task.id { state.active?.title = task.title; state.active?.project = task.project }
        }
        if saved, task.reminder != nil { requestNotificationsIfNeeded() }
        return saved
    }
    func toggleTask(_ task: FocusTask) {
        _ = commit { state in
            guard let index = state.tasks.firstIndex(where: { $0.id == task.id }) else { return }
            if state.tasks[index].isCompleted { state.tasks[index].completedAt = nil }
            else {
                state.tasks[index].completedAt = Date()
                if state.active?.taskID == task.id { TimerEngine.stop(state: &state, at: Date()) }
                if !state.tasks.contains(where: { $0.predecessorID == task.id }), let next = TaskRules.nextOccurrence(of: state.tasks[index], after: Date()) { state.tasks.append(next) }
            }
        }
    }
    func archiveTask(_ task: FocusTask) {
        if commit({ state in
            if state.active?.taskID == task.id { TimerEngine.stop(state: &state, at: Date()) }
            if let index = state.tasks.firstIndex(where: { $0.id == task.id }) { state.tasks[index].archived = true }
        }) { notice = "Aufgabe entfernt. Deine erfassten Zeiten bleiben erhalten." }
    }
    func restoreTask(_ task: FocusTask) {
        if commit({ state in
            if let index = state.tasks.firstIndex(where: { $0.id == task.id }) { state.tasks[index].archived = false }
        }) { notice = "Aufgabe wiederhergestellt." }
    }
    func editTask(_ task: FocusTask) {
        requestedTaskID = task.id
        requestedSection = task.isCompleted ? "completed" : "all"
        openDashboard()
    }
    func startTimer(task: FocusTask? = nil, mode: TimerMode = .stopwatch, minutes: Int = 25) {
        guard task?.isCompleted != true else { errorMessage = "Öffne die Aufgabe erneut, bevor du Zeit darauf erfasst."; return }
        guard (1...1440).contains(minutes) else { errorMessage = "Bitte wähle zwischen 1 und 1.440 Minuten."; return }
        if commit({ TimerEngine.start(state: &$0, task: task, mode: mode, minutes: minutes, at: Date()) }) {
            finishedMode = nil
            pendingFocusGuardIntent = nil
            focusGuardChanged?()
            if mode != .stopwatch { requestNotificationsIfNeeded() }
        }
    }
    func pauseTimer() {
        pendingFocusGuardIntent = nil
        focusGuardChanged?()
        _ = commit { TimerEngine.pause(state: &$0, at: Date()) }
    }
    func resumeTimer() {
        pendingFocusGuardIntent = nil
        focusGuardChanged?()
        _ = commit { TimerEngine.resume(state: &$0, at: Date()) }
    }
    func stopTimer() {
        pendingFocusGuardIntent = nil
        focusGuardChanged?()
        _ = commit { TimerEngine.stop(state: &$0, at: Date()) }
    }
    func requestPauseTimer() {
        if isFocusGuardRequired {
            pendingFocusGuardIntent = .pause
            focusGuardChanged?()
        } else {
            pauseTimer()
        }
    }
    func requestStopTimer() {
        if isFocusGuardRequired {
            pendingFocusGuardIntent = .stop
            focusGuardChanged?()
        } else {
            stopTimer()
        }
    }
    func requestToggleBlockerDuringSession() {
        if preferences.isAppBlockerEnabled && isAppBlockerActive && isFocusGuardRequired {
            pendingFocusGuardIntent = .unlockBlocker
            focusGuardChanged?()
        } else {
            setAppBlockerEnabled(!preferences.isAppBlockerEnabled)
        }
    }
    func cancelFocusGuardChallenge() {
        pendingFocusGuardIntent = nil
        focusGuardChanged?()
        notice = "Stark geblieben – Fokus läuft weiter!"
    }
    func completeFocusGuardChallenge() {
        guard let intent = pendingFocusGuardIntent else { return }
        pendingFocusGuardIntent = nil
        focusGuardChanged?()
        switch intent {
        case .pause:
            pauseTimer()
        case .stop:
            stopTimer()
        case .unlockBlocker:
            var draft = preferences
            draft.appBlockerEnabled = false
            savePreferences(draft)
        }
    }
    func setFocusGuardEnabled(_ enabled: Bool) {
        if !enabled && isFocusGuardRequired {
            pendingFocusGuardIntent = .pause
            focusGuardChanged?()
            return
        }
        var draft = preferences
        draft.focusGuardEnabled = enabled
        savePreferences(draft)
    }
    func setFocusGuardSeconds(_ seconds: Int) {
        let clamped = min(180, max(15, seconds))
        var draft = preferences
        draft.focusGuardSeconds = clamped
        savePreferences(draft)
    }
    func startBreak() { startTimer(mode: .rest, minutes: state.completedFocusSessions > 0 && state.completedFocusSessions % 4 == 0 ? preferences.longBreakMinutes : preferences.breakMinutes) }
    func startNextFocus() {
        let task = tasks.first { $0.id == state.lastWorkTaskID && !$0.isCompleted }
        startTimer(task: task, mode: .focus, minutes: preferences.focusMinutes)
    }
    private func tick(_ date: Date) {
        now = date
        if date.timeIntervalSince(lastSchedule) >= 300 { rescheduleNotifications() }
        guard !storageBlocked else { return }
        checkLocalReminders(at: date)
        if let timer = active, let deadline = timer.deadline, date >= deadline {
            var mode: TimerMode?
            if commit({ mode = TimerEngine.tick(state: &$0, at: date) }) { finish(mode) }
        } else if active?.isRunning == true, date.timeIntervalSince(lastPersist) >= 15 {
            if !commit({ _ in }, notifications: false) {
                // Stop the in-memory clock if durable checkpoints stop working.
                TimerEngine.pause(state: &state, at: date)
                storageBlocked = true
                rescheduleNotifications()
                errorMessage = "Die Zeiterfassung wurde wegen eines Speicherfehlers pausiert. Exportiere eine Sicherung und prüfe den Speicherplatz."
            }
        }
        timerChanged?()
    }
    private func finish(_ mode: TimerMode?) {
        guard let mode else { return }
        finishedMode = mode
        pendingFocusGuardIntent = nil
        focusGuardChanged?()
        notice = mode == .rest ? "Pause beendet. Bereit für die nächste Fokusphase?" : "Zeit geschafft. Deine Sitzung ist gespeichert."
        if !preview && preferences.soundEnabled { NSSound(named: NSSound.Name(preferences.sound))?.play() }
        if usesLocalAlerts && preferences.notificationsEnabled {
            enqueue(LocalAlert(title: mode == .rest ? "Deine Pause ist vorbei" : "Timer abgelaufen", message: "Deine Sitzung ist gespeichert. Bereit für den nächsten Schritt?"))
        } else if !preview && preferences.notificationsEnabled {
            let content = UNMutableNotificationContent()
            content.title = mode == .rest ? "Deine Pause ist vorbei" : "Timer abgelaufen"
            content.body = "Öffne FokusBar für deine nächste Sitzung."
            Task {
                do { try await UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: "timer-finished", content: content, trigger: nil)) }
                catch { notificationStatus = "Timer-Mitteilung fehlgeschlagen: \(error.localizedDescription)" }
            }
        }
    }
    private func willSleep() {
        sleepAt = Date()
        isPreviewingFocusSound = false
        focusAudio.stop(immediate: true)
        appBlocker.stopBlocking()
        _ = commit({ TimerEngine.sleep(state: &$0, at: Date()) }, notifications: false)
    }
    private func didWake() {
        now = Date()
        var mode: TimerMode?
        if commit({ mode = TimerEngine.wake(state: &$0, at: Date()) }) {
            if mode != nil { finish(mode) }
            else if active != nil { notice = "Während des Ruhezustands wurde keine Arbeitszeit erfasst. Setze die Sitzung bei Bedarf fort." }
        }
        sleepAt = nil
        refreshAuthorization()
    }
    private func pauseForLock() {
        guard active?.isRunning == true, active?.mode.isWork == true else { return }
        pauseTimer()
        notice = "Deine Sitzung wurde beim Sperren des Macs pausiert."
    }
    func seconds(for taskID: UUID) -> TimeInterval {
        var result = entries.filter { $0.taskID == taskID && $0.mode.isWork }.reduce(0) { $0 + $1.duration }
        if let timer = active, timer.taskID == taskID, timer.mode.isWork, let start = timer.segmentStart { result += max(0, min(now, timer.deadline ?? now).timeIntervalSince(start)) }
        return result
    }
    func savePreferences(_ value: Preferences) {
        if commit({ $0.preferences = value }), !value.notificationsEnabled { localAlerts.removeAll(); alertChanged?() }
    }
    func previewSound() { NSSound(named: NSSound.Name(preferences.sound))?.play() }
    func selectFocusSound(_ sound: FocusSound, startPreviewIfIdle: Bool = false) {
        var draft = preferences
        draft.focusSound = sound.rawValue
        if sound != .off { draft.lastFocusSound = sound.rawValue }
        if sound == .off {
            isPreviewingFocusSound = false
        } else if startPreviewIfIdle, active?.isRunning != true {
            isPreviewingFocusSound = true
        }
        savePreferences(draft)
    }
    func toggleFocusSoundMute() {
        if selectedFocusSound != .off {
            selectFocusSound(.off)
        } else {
            selectFocusSound(preferences.preferredPlayableFocusSound)
        }
    }
    func setFocusSoundVolume(_ volume: Double, unmuteIfOff: Bool = false) {
        let clamped = min(1.0, max(0.05, volume))
        var draft = preferences
        draft.focusSoundVolume = clamped
        if unmuteIfOff, selectedFocusSound == .off {
            let restored = preferences.preferredPlayableFocusSound
            draft.focusSound = restored.rawValue
            draft.lastFocusSound = restored.rawValue
        }
        focusAudio.updateVolume(clamped)
        savePreferences(draft)
    }
    func setFocusMinutes(_ minutes: Int) {
        let clamped = min(240, max(1, minutes))
        guard preferences.focusMinutes != clamped else { return }
        var draft = preferences
        draft.focusMinutes = clamped
        savePreferences(draft)
    }
    func adjustActiveTimerMinutes(_ deltaMinutes: Int) {
        guard let current = state.active, current.mode != .stopwatch else { return }
        let elapsed = current.elapsed(at: Date())
        let minTarget = max(60, ceil(elapsed / 60.0) * 60.0)
        let newTarget = min(86400, max(minTarget, current.target + Double(deltaMinutes * 60)))
        _ = commit { state in
            state.active?.target = newTarget
        }
    }
    func toggleFocusSoundPreview() {
        if isPreviewingFocusSound {
            isPreviewingFocusSound = false
            syncFocusAudio()
        } else {
            if selectedFocusSound == .off {
                var draft = preferences
                let restored = preferences.preferredPlayableFocusSound
                draft.focusSound = restored.rawValue
                draft.lastFocusSound = restored.rawValue
                isPreviewingFocusSound = true
                savePreferences(draft)
            } else {
                isPreviewingFocusSound = true
                syncFocusAudio()
            }
        }
    }
    func skipSpotifyTrack() { focusAudio.skipSpotifyTrack() }
    func openActiveSoundInSpotify() { focusAudio.openInSpotifyApp(sound: selectedFocusSound) }
    private func syncFocusAudio() {
        guard !preview else { return }
        if isFocusSoundPlaying {
            focusAudio.play(sound: selectedFocusSound, volume: preferences.effectiveFocusSoundVolume)
        } else {
            focusAudio.stop()
        }
    }
    private func syncAppBlocker() {
        guard !preview else { return }
        let keepSpotifyAlive = isFocusSoundPlaying && selectedFocusSound.isSpotify
        appBlocker.sync(
            isBlocking: isAppBlockerActive,
            blockedApps: blockedApps,
            blockedWebsites: blockedWebsites,
            keepSpotifyAlive: keepSpotifyAlive
        )
    }
    func blockDetectedDistractionApps(_ detected: [BlockedApp]) {
        guard !detected.isEmpty else { return }
        var draft = preferences
        var list = draft.effectiveBlockedApps
        for app in detected where !BlockedApp.isProtected(app.bundleIdentifier) {
            let lower = app.bundleIdentifier.lowercased()
            if !list.contains(where: { $0.bundleIdentifier.lowercased() == lower }) {
                list.append(app)
            }
        }
        list.sort { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        draft.blockedApps = list
        draft.appBlockerEnabled = true
        savePreferences(draft)
    }
    func blockTopSocialWebsites() {
        var draft = preferences
        var list = draft.effectiveBlockedWebsites
        for preset in BlockedWebsite.presets.prefix(5) {
            if !list.contains(preset.domain) {
                list.append(preset.domain)
            }
        }
        list.sort()
        draft.blockedWebsites = list
        draft.appBlockerEnabled = true
        savePreferences(draft)
    }
    func isAppBlocked(_ app: BlockedApp) -> Bool {
        let target = app.bundleIdentifier.lowercased()
        return blockedApps.contains { $0.bundleIdentifier.lowercased() == target }
    }
    func toggleBlockedApp(_ app: BlockedApp) {
        guard !BlockedApp.isProtected(app.bundleIdentifier) else { return }
        var draft = preferences
        var list = draft.effectiveBlockedApps
        let target = app.bundleIdentifier.lowercased()
        if let idx = list.firstIndex(where: { $0.bundleIdentifier.lowercased() == target }) {
            if isAppBlockerActive && isFocusGuardRequired {
                pendingFocusGuardIntent = .unlockBlocker
                focusGuardChanged?()
                return
            }
            list.remove(at: idx)
        } else {
            list.append(app)
            list.sort { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
            draft.appBlockerEnabled = true
        }
        draft.blockedApps = list
        savePreferences(draft)
    }
    func removeBlockedApp(_ app: BlockedApp) {
        if isAppBlockerActive && isFocusGuardRequired {
            pendingFocusGuardIntent = .unlockBlocker
            focusGuardChanged?()
            return
        }
        var draft = preferences
        let target = app.bundleIdentifier.lowercased()
        draft.blockedApps = draft.effectiveBlockedApps.filter { $0.bundleIdentifier.lowercased() != target }
        savePreferences(draft)
    }
    func isWebsiteBlocked(_ domain: String) -> Bool {
        guard let norm = BlockedWebsite.normalizeDomain(domain) else { return false }
        return blockedWebsites.contains(norm)
    }
    func toggleBlockedWebsite(_ domain: String) {
        guard let norm = BlockedWebsite.normalizeDomain(domain) else { return }
        var draft = preferences
        var list = draft.effectiveBlockedWebsites
        if let idx = list.firstIndex(of: norm) {
            if isAppBlockerActive && isFocusGuardRequired {
                pendingFocusGuardIntent = .unlockBlocker
                focusGuardChanged?()
                return
            }
            list.remove(at: idx)
        } else {
            list.append(norm)
            list.sort()
            draft.appBlockerEnabled = true
        }
        draft.blockedWebsites = list
        savePreferences(draft)
    }
    @discardableResult func addBlockedWebsite(_ raw: String) -> Bool {
        guard let norm = BlockedWebsite.normalizeDomain(raw) else { return false }
        var draft = preferences
        var list = draft.effectiveBlockedWebsites
        if !list.contains(norm) {
            list.append(norm)
            list.sort()
        }
        draft.blockedWebsites = list
        draft.appBlockerEnabled = true
        savePreferences(draft)
        return true
    }
    func removeBlockedWebsite(_ domain: String) {
        if isAppBlockerActive && isFocusGuardRequired {
            pendingFocusGuardIntent = .unlockBlocker
            focusGuardChanged?()
            return
        }
        guard let norm = BlockedWebsite.normalizeDomain(domain) else { return }
        var draft = preferences
        draft.blockedWebsites = draft.effectiveBlockedWebsites.filter { $0 != norm }
        savePreferences(draft)
    }
    func setAppBlockerEnabled(_ enabled: Bool) {
        if !enabled && isAppBlockerActive && isFocusGuardRequired {
            pendingFocusGuardIntent = .unlockBlocker
            focusGuardChanged?()
            return
        }
        var draft = preferences
        draft.appBlockerEnabled = enabled
        savePreferences(draft)
    }
    func pickBlockedAppFromFinder() {
        let panel = NSOpenPanel()
        panel.title = "Zu blockierende Apps auswählen"
        panel.prompt = "Blockieren"
        panel.allowedContentTypes = [.applicationBundle]
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        panel.directoryURL = URL(fileURLWithPath: "/Applications", isDirectory: true)
        guard panel.runModal() == .OK else { return }
        var draft = preferences
        var list = draft.effectiveBlockedApps
        for url in panel.urls {
            guard let app = AppBlockerController.blockedApp(from: url) else { continue }
            let lower = app.bundleIdentifier.lowercased()
            if !list.contains(where: { $0.bundleIdentifier.lowercased() == lower }) {
                list.append(app)
            }
        }
        list.sort { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        draft.blockedApps = list
        draft.appBlockerEnabled = true
        savePreferences(draft)
    }
    func setLaunchAtLogin(_ enabled: Bool) {
        guard !preview else { launchAtLogin = enabled; return }
        do {
            if enabled { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
            launchAtLogin = SMAppService.mainApp.status == .enabled
            if enabled && !launchAtLogin { notice = "Bitte bestätige FokusBar in Systemeinstellungen > Allgemein > Anmeldeobjekte." }
        } catch { errorMessage = "Autostart konnte nicht geändert werden: \(error.localizedDescription)" }
    }
    @discardableResult func saveEntry(_ value: TimeEntry) -> Bool {
        var entry = value
        entry.taskTitle = entry.taskTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !entry.taskTitle.isEmpty, entry.end > entry.start, entry.end <= Date().addingTimeInterval(1), entry.duration <= 604800 else { errorMessage = "Bitte prüfe Titel und Zeitspanne. Das Ende muss nach dem Beginn liegen und darf nicht in der Zukunft sein (maximal 7 Tage)."; return false }
        let overlap = entries.contains { $0.id != entry.id && $0.start < entry.end && $0.end > entry.start }
        let activeOverlap = active.map { timer in timer.mode.isWork && timer.segmentStart.map { $0 < entry.end && Date() > entry.start } == true } ?? false
        guard !overlap && !activeOverlap else { errorMessage = "Diese Zeitspanne überschneidet sich mit einer anderen Sitzung. Bitte korrigiere sie zuerst."; return false }
        return commit { state in
            if let index = state.entries.firstIndex(where: { $0.id == entry.id }) { state.entries[index] = entry } else { state.entries.append(entry) }
        }
    }
    func deleteEntry(_ entry: TimeEntry) { _ = commit { $0.entries.removeAll { $0.id == entry.id } } }
    func exportBackup() {
        let panel = NSSavePanel(); panel.nameFieldStringValue = "FokusBar-Sicherung-\(Date().formatted(.iso8601.year().month().day().dateSeparator(.dash))).json"; panel.allowedContentTypes = [.json]
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            var snapshot = state; TimerEngine.pause(state: &snapshot, at: Date())
            try LocalRepository.encode(snapshot).write(to: url, options: .atomic)
            notice = "Sicherung gespeichert."
        } catch { errorMessage = "Export fehlgeschlagen: \(error.localizedDescription)" }
    }
    func importBackup() {
        let panel = NSOpenPanel(); panel.allowedContentTypes = [.json]; panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            var imported = try LocalRepository.decode(Data(contentsOf: url))
            _ = TimerEngine.recover(state: &imported, at: Date())
            let alert = NSAlert(); alert.messageText = "Sicherung wiederherstellen?"
            alert.informativeText = "Die Sicherung enthält \(imported.tasks.count) Aufgaben und \(imported.entries.count) Zeiteinträge. Sie ersetzt den aktuellen Stand. Vorher wird eine lokale Kopie des bisherigen Stands gesichert."
            alert.addButton(withTitle: "Wiederherstellen"); alert.addButton(withTitle: "Abbrechen")
            guard alert.runModal() == .alertFirstButtonReturn else { return }
            if !storageBlocked, !commit({ TimerEngine.pause(state: &$0, at: Date()) }) { return }
            try repository?.restore(imported)
            state = imported; storageBlocked = false; errorMessage = nil; finishedMode = nil; lastPersist = Date()
            rescheduleNotifications(); syncFocusAudio(); syncAppBlocker(); timerChanged?(); notice = "Sicherung wiederhergestellt."
        } catch { errorMessage = "Die Sicherung konnte nicht eingelesen werden. \(error.localizedDescription)" }
    }
    func exportCSV() {
        let panel = NSSavePanel(); panel.nameFieldStringValue = "FokusBar-Zeiten.csv"; panel.allowedContentTypes = [.commaSeparatedText]
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do { try Statistics.csv(entries: entries).write(to: url, atomically: true, encoding: .utf8); notice = "Gespeicherte Sitzungen als CSV exportiert." }
        catch { errorMessage = "CSV-Export fehlgeschlagen: \(error.localizedDescription)" }
    }
    private func checkLocalReminders(at date: Date) {
        guard usesLocalAlerts, preferences.notificationsEnabled else { return }
        let due = ReminderRules.due(in: state, at: date)
        for task in due.prefix(10) {
            guard let key = ReminderRules.key(for: task), !localAlerts.contains(where: { $0.reminderKey == key }) else { continue }
            enqueue(LocalAlert(title: "Erinnerung", message: task.title, taskID: task.id, reminderKey: key), sound: true)
        }
        // Remove alerts for tasks completed, archived or rescheduled elsewhere.
        let valid = Set(due.compactMap { ReminderRules.key(for: $0) })
        let count = localAlerts.count
        localAlerts.removeAll { $0.reminderKey.map { !valid.contains($0) } ?? false }
        if count != localAlerts.count { alertChanged?() }
    }
    private func enqueue(_ alert: LocalAlert, sound: Bool = false) {
        let wasEmpty = localAlerts.isEmpty
        localAlerts.append(alert)
        if wasEmpty && sound && preferences.soundEnabled { NSSound(named: NSSound.Name(preferences.sound))?.play() }
        alertChanged?()
    }
    func dismissAlert(_ alert: LocalAlert) {
        if let key = alert.reminderKey {
            guard commit({ state in
                let valid = Set(state.tasks.compactMap { ReminderRules.key(for: $0) })
                var keys = (state.dismissedReminderKeys ?? []).filter { valid.contains($0) }
                if !keys.contains(key) { keys.append(key) }
                state.dismissedReminderKeys = keys
            }, notifications: false) else { return }
        }
        localAlerts.removeAll { $0.id == alert.id }; alertChanged?()
    }
    func snoozeAlert(_ alert: LocalAlert) {
        guard let id = alert.taskID, var task = tasks.first(where: { $0.id == id }) else { dismissAlert(alert); return }
        task.reminder = Date().addingTimeInterval(600)
        if saveTask(task) { localAlerts.removeAll { $0.id == alert.id }; alertChanged?() }
    }
    func completeAlert(_ alert: LocalAlert) {
        guard let id = alert.taskID, let task = tasks.first(where: { $0.id == id }) else { dismissAlert(alert); return }
        toggleTask(task)
        if state.tasks.first(where: { $0.id == id })?.isCompleted == true { localAlerts.removeAll { $0.id == alert.id }; alertChanged?() }
    }
    func openDashboard() { dashboardAction?() }
    func openSettings() { requestedSection = "settings"; (settingsAction ?? dashboardAction)?() }
    func quit() {
        isPreviewingFocusSound = false
        focusAudio.stop(immediate: true)
        appBlocker.stopBlocking()
        guard storageBlocked || commit({ TimerEngine.pause(state: &$0, at: Date()) }) else { return }
        NSApp.terminate(nil)
    }
    func prepareTermination() {
        isPreviewingFocusSound = false
        focusAudio.stop(immediate: true)
        appBlocker.stopBlocking()
        if !storageBlocked { _ = commit { TimerEngine.pause(state: &$0, at: Date()) } }
    }
    func requestNotifications() {
        if usesLocalAlerts {
            enqueue(LocalAlert(title: "FokusBar ist bereit", message: "Lokale Erinnerungen erscheinen hier, solange FokusBar läuft."), sound: true)
            return
        }
        guard !preview else { return }
        Task {
            do {
                let allowed = try await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge])
                if !allowed { notice = "Mitteilungen sind ausgeschaltet. Du kannst sie in den macOS-Systemeinstellungen für FokusBar erlauben. Timer-Sounds in der laufenden App bleiben verfügbar." }
                refreshAuthorization(); rescheduleNotifications()
            } catch { errorMessage = "Mitteilungen konnten nicht aktiviert werden: \(error.localizedDescription)" }
        }
    }
    private func requestNotificationsIfNeeded() {
        guard !preview, !usesLocalAlerts, preferences.notificationsEnabled else { return }
        Task { let settings = await UNUserNotificationCenter.current().notificationSettings(); if settings.authorizationStatus == .notDetermined { requestNotifications() } }
    }
    func refreshAuthorization() {
        if usesLocalAlerts { notificationStatus = "Lokale Erinnerungsfenster"; return }
        guard !preview else { notificationStatus = "Vorschau"; return }
        Task {
            let settings = await UNUserNotificationCenter.current().notificationSettings()
            switch settings.authorizationStatus {
            case .authorized, .provisional, .ephemeral: notificationStatus = "Erlaubt"
            case .denied: notificationStatus = "In macOS ausgeschaltet"
            case .notDetermined: notificationStatus = "Noch nicht angefragt"
            @unknown default: notificationStatus = "Unbekannt"
            }
        }
    }
    private func registerNotificationActions() {
        let snooze = UNNotificationAction(identifier: "snooze", title: "In 10 Minuten erinnern", options: [])
        let done = UNNotificationAction(identifier: "done", title: "Erledigen", options: [])
        UNUserNotificationCenter.current().setNotificationCategories([UNNotificationCategory(identifier: "task", actions: [snooze, done], intentIdentifiers: [])])
    }
    private func rescheduleNotifications() {
        guard !preview, !usesLocalAlerts else { return }
        scheduleRevision += 1
        let revision = scheduleRevision
        lastSchedule = Date()
        let previous = notificationTask
        previous?.cancel()
        notificationTask = Task {
            await previous?.value
            guard revision == scheduleRevision else { return }
            let center = UNUserNotificationCenter.current()
            let pending = await center.pendingNotificationRequests()
            guard revision == scheduleRevision else { return }
            center.removePendingNotificationRequests(withIdentifiers: pending.map(\.identifier))
            guard preferences.notificationsEnabled else { return }
            let settings = await center.notificationSettings()
            guard revision == scheduleRevision, settings.authorizationStatus == .authorized || settings.authorizationStatus == .provisional else { return }
            let reminders = tasks.filter { !$0.isCompleted && ($0.reminder ?? .distantPast) > Date() }.sorted { $0.reminder! < $1.reminder! }
            if reminders.count > 60 { notice = "Die nächsten 60 Erinnerungen sind geplant. Weitere rücken beim nächsten Öffnen nach." }
            for task in reminders.prefix(60) {
                guard revision == scheduleRevision, let reminder = task.reminder else { return }
                let content = UNMutableNotificationContent(); content.title = "Zeit für deine Aufgabe"; content.body = task.title; content.categoryIdentifier = "task"; content.userInfo = ["taskID": task.id.uuidString]
                if preferences.soundEnabled { content.sound = .default }
                let trigger = UNTimeIntervalNotificationTrigger(timeInterval: max(1, reminder.timeIntervalSinceNow), repeats: false)
                do { try await center.add(UNNotificationRequest(identifier: "task-\(task.id)", content: content, trigger: trigger)) }
                catch { notificationStatus = "Planung fehlgeschlagen: \(error.localizedDescription)" }
            }

        }
    }
    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification, withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) { completionHandler([.banner, .sound]) }
    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse, withCompletionHandler completionHandler: @escaping () -> Void) {
        Task { @MainActor in
            if let value = response.notification.request.content.userInfo["taskID"] as? String, let id = UUID(uuidString: value), var task = tasks.first(where: { $0.id == id }) {
                if response.actionIdentifier == "done", !task.isCompleted { toggleTask(task) }
                else if response.actionIdentifier == "snooze", !task.isCompleted { task.reminder = Date().addingTimeInterval(600); _ = saveTask(task) }
                else { openDashboard() }
            } else { openDashboard() }
            completionHandler()
        }
    }
}
