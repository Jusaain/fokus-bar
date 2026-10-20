import SwiftUI
import AppKit
import Combine
import UserNotifications
import FocusCore

@main
struct FokusBarApp: App {
    @NSApplicationDelegateAdaptor(FokusBarDelegate.self) private var delegate
    var body: some Scene {
        Settings {
            if let store = delegate.store {
                SettingsScreen(store: store).frame(width: 720, height: 720)
            }
        }
            .commands {
                CommandGroup(replacing: .appSettings) {
                    Button("Einstellungen …") { delegate.openAppSettings() }
                        .keyboardShortcut(",", modifiers: .command)
                }
                CommandGroup(after: .windowArrangement) {
                    Button("Menüleistenfenster öffnen") { delegate.openMenuPanel() }
                        .keyboardShortcut("m", modifiers: [.command, .shift])
                }
            }
    }
}

@MainActor
final class FokusBarDelegate: NSObject, NSApplicationDelegate, NSPopoverDelegate, NSWindowDelegate, ObservableObject {
    @Published fileprivate var store: FocusStore!
    private var statusItem: NSStatusItem?
    private let popover = NSPopover()
    private var window: NSWindow?
    private var snapshotWindow: NSWindow?
    private var reminderWindow: NSPanel?
    private var observation: AnyCancellable?
    private lazy var hotKey = GlobalHotKey { [weak self] in self?.toggleQuickEntry() }
    private var hotKeyApplied: Bool?
    private var quickEntryPanel: QuickEntryPanel?
    private let quickEntry = QuickEntryModel()
    private var floatingTimerPanel: FloatingTimerPanel?
    private var focusGuardWindow: NSPanel?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        let args = ProcessInfo.processInfo.arguments
        let preview = args.contains("--snapshot") || args.contains("--self-test") || args.contains("--ui-test") || args.contains("--local-alert-test")
        if !preview, let existing = NSRunningApplication.runningApplications(withBundleIdentifier: "de.justin.fokusbar").first(where: { $0.processIdentifier != ProcessInfo.processInfo.processIdentifier }) {
            existing.activate(options: [.activateAllWindows])
            NSApp.terminate(nil)
            return
        }
        store = FocusStore(preview: preview)
        store.dashboardAction = { [weak self] in self?.showDashboard() }
        store.settingsAction = { [weak self] in self?.showDashboard() }
        store.timerChanged = { [weak self] in self?.updateStatus() }
        store.alertChanged = { [weak self] in self?.presentLocalAlert() }
        store.focusGuardChanged = { [weak self] in self?.presentFocusGuardWindowIfNeeded() }
        if args.contains("--local-alert-test") {
            store.state.tasks = [FocusTask(title: "Test: Lokale Erinnerung", reminder: Date().addingTimeInterval(3))]
        }
        if args.contains("--self-test") { runSelfTest(); return }
        if let i = args.firstIndex(of: "--system-check"), args.indices.contains(i + 1) {
            Task { await systemCheck(path: args[i + 1]) }
            return
        }
        if let i = args.firstIndex(of: "--snapshot"), args.indices.contains(i + 1) {
            if !args.contains("--empty") { installFixtures() }
            if let section = args.firstIndex(of: "--section"), args.indices.contains(section + 1) { store.requestedSection = args[section + 1] }
            Task { await snapshot(path: args[i + 1], menu: args.contains("--menu"), dark: args.contains("--dark"), quickEntry: args.contains("--quick-entry"), floatingTimer: args.contains("--floating-timer")) }
            return
        }
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.autosaveName = "FokusBar"
        if let button = item.button {
            button.image = NSImage(systemSymbolName: "checkmark.circle", accessibilityDescription: "FokusBar öffnen")
            button.image?.isTemplate = true
            button.imagePosition = .imageLeading
            button.font = .monospacedDigitSystemFont(ofSize: 12, weight: .medium)
            button.target = self; button.action = #selector(togglePanel)
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
            button.toolTip = "FokusBar: Aufgaben und Zeit"
        }
        statusItem = item
        popover.behavior = .transient
        popover.delegate = self
        popover.contentSize = NSSize(width: 420, height: 660)
        popover.contentViewController = NSHostingController(rootView: AppSurface(store: store, menu: true))
        observation = store.$state.sink { [weak self] _ in DispatchQueue.main.async { self?.updateStatus(); self?.applyAppearance(); self?.applyHotKey() } }
        updateStatus(); applyAppearance(); applyHotKey()
        // A launch opens the app; autostart stays quietly in the menu bar.
        let launchedAtLogin = NSAppleEventManager.shared().currentAppleEvent?.paramDescriptor(forKeyword: keyAEPropData)?.enumCodeValue == keyAELaunchedAsLogInItem
        if !launchedAtLogin && !args.contains("--background") { showDashboard() }
    }
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool { showDashboard(); return false }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }
    func applicationWillTerminate(_ notification: Notification) { store?.prepareTermination() }
    func popoverShouldDetach(_ popover: NSPopover) -> Bool { false }
    private func updateStatus() {
        updateFloatingTimer()
        guard let store, let button = statusItem?.button else { return }
        button.title = store.preferences.showMenuTime && store.active != nil ? " " + store.timerText : ""
        button.image = NSImage(systemSymbolName: store.active?.isRunning == true ? "timer" : "checkmark.circle", accessibilityDescription: "FokusBar öffnen")
        button.image?.isTemplate = true
        button.toolTip = store.active.map { "\($0.title): \(store.timerText)" } ?? "FokusBar: Aufgaben und Zeit"
    }
    private func updateFloatingTimer() {
        let args = ProcessInfo.processInfo.arguments
        guard let store, !args.contains("--snapshot"), !args.contains("--self-test") else { return }
        guard store.active != nil, store.preferences.showFloatingTimer else {
            floatingTimerPanel?.orderOut(nil)
            return
        }
        if floatingTimerPanel == nil {
            floatingTimerPanel = FloatingTimerPanel(store: store)
        }
        guard let panel = floatingTimerPanel else { return }
        if !panel.isVisible || !NSScreen.screens.contains(where: { $0.visibleFrame.intersects(panel.frame) }) {
            panel.restoreOrPlace(on: window?.screen ?? NSScreen.main)
        }
        if !panel.isVisible {
            panel.orderFrontRegardless()
        }
    }
    private func applyAppearance() {
        let appearance: NSAppearance? = switch store.preferences.appearance { case "dark": NSAppearance(named: .darkAqua); case "light": NSAppearance(named: .aqua); default: nil }
        popover.appearance = appearance; window?.appearance = appearance; quickEntryPanel?.appearance = appearance
    }
    private func applyHotKey() {
        let enabled = store.preferences.quickEntryEnabled
        guard enabled != hotKeyApplied else { return }
        hotKeyApplied = enabled
        if enabled { store.quickEntryHotKeyAvailable = hotKey.register() } else { hotKey.unregister(); store.quickEntryHotKeyAvailable = true }
    }
    private func toggleQuickEntry() {
        if let panel = quickEntryPanel, panel.isVisible { panel.orderOut(nil); return }
        if quickEntryPanel == nil {
            let panel = QuickEntryPanel()
            panel.contentViewController = NSHostingController(rootView: QuickEntryView(store: store, model: quickEntry) { [weak self] in self?.quickEntryPanel?.orderOut(nil) })
            panel.delegate = self
            panel.onCancel = { [weak self] in self?.quickEntry.text = ""; self?.quickEntryPanel?.orderOut(nil) }
            quickEntryPanel = panel
        }
        guard let panel = quickEntryPanel else { return }
        applyAppearance()
        quickEntry.confirmation = nil; quickEntry.failed = false
        let screen = NSScreen.screens.first { NSMouseInRect(NSEvent.mouseLocation, $0.frame, false) } ?? NSScreen.main
        let area = screen?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
        panel.setFrameOrigin(NSPoint(x: area.midX - panel.frame.width / 2, y: area.maxY - area.height * 0.22 - panel.frame.height))
        panel.makeKeyAndOrderFront(nil)
        quickEntry.focusToken += 1
    }
    func windowDidResignKey(_ notification: Notification) {
        if let panel = quickEntryPanel, notification.object as? NSWindow === panel { panel.orderOut(nil) }
    }
    func openAppSettings() { store?.openSettings() }
    func openMenuPanel() { togglePanel() }
    @objc private func togglePanel() {
        if NSApp.currentEvent?.type == .rightMouseUp { showContextMenu(); return }
        if popover.isShown { popover.performClose(nil); return }
        guard let button = statusItem?.button, let anchor = button.window, let screen = anchor.screen, screen.frame.intersects(anchor.frame) else { showDashboard(); return }
        store.refreshAuthorization()
        NSApp.activate(ignoringOtherApps: true)
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        popover.contentViewController?.view.window?.makeKey()
    }
    private func showContextMenu() {
        let menu = NSMenu()
        let open = NSMenuItem(title: "FokusBar öffnen", action: #selector(openWindow), keyEquivalent: ""); open.target = self; menu.addItem(open)
        let quick = NSMenuItem(title: "Neue Aufgabe …", action: #selector(openQuickEntry), keyEquivalent: store.preferences.quickEntryEnabled ? " " : "")
        quick.keyEquivalentModifierMask = [.control, .option]; quick.target = self; menu.addItem(quick)
        let settings = NSMenuItem(title: "Einstellungen …", action: #selector(openPreferences), keyEquivalent: ","); settings.target = self; menu.addItem(settings)
        menu.addItem(.separator())
        let quit = NSMenuItem(title: "FokusBar beenden", action: #selector(quitApp), keyEquivalent: "q"); quit.target = self; menu.addItem(quit)
        statusItem?.menu = menu; statusItem?.button?.performClick(nil); statusItem?.menu = nil
    }
    @objc private func openWindow() { showDashboard() }
    @objc private func openQuickEntry() { toggleQuickEntry() }
    @objc private func openPreferences() { store.openSettings() }
    @objc private func quitApp() { store.quit() }
    private func showDashboard() {
        popover.performClose(nil)
        if window == nil {
            let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1080, height: 760), styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false)
            window.title = "FokusBar"
            window.titlebarAppearsTransparent = true
            window.isReleasedWhenClosed = false
            window.minSize = NSSize(width: 940, height: 720)
            window.contentViewController = NSHostingController(rootView: AppSurface(store: store, menu: false))
            window.collectionBehavior = [.moveToActiveSpace, .fullScreenAuxiliary]
            if !window.setFrameUsingName("FokusBarDashboard") { window.center() }
            window.setFrameAutosaveName("FokusBarDashboard")
            self.window = window
        }
        applyAppearance(); store.refreshAuthorization()
        if let window, !NSScreen.screens.contains(where: { $0.visibleFrame.intersects(window.frame) }) { window.center() }
        if window?.isMiniaturized == true { window?.deminiaturize(nil) }
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }
    private func presentLocalAlert() {
        guard !store.localAlerts.isEmpty else { reminderWindow?.orderOut(nil); return }
        if reminderWindow == nil {
            let panel = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 400, height: 210), styleMask: [.titled, .nonactivatingPanel, .fullSizeContentView], backing: .buffered, defer: false)
            panel.title = "FokusBar Erinnerung"; panel.titleVisibility = .hidden; panel.titlebarAppearsTransparent = true
            panel.isReleasedWhenClosed = false; panel.isFloatingPanel = true; panel.hidesOnDeactivate = false
            panel.level = .floating; panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
            panel.contentViewController = NSHostingController(rootView: LocalReminderView(store: store))
            reminderWindow = panel
        }
        let area = (window?.screen ?? NSScreen.main)?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
        let timerOffset: CGFloat = floatingTimerPanel?.isVisible == true ? (FloatingTimerPanel.panelSize.height + 6) : 0
        reminderWindow?.setFrameOrigin(NSPoint(x: area.maxX - 420, y: area.maxY - 230 - timerOffset))
        reminderWindow?.orderFrontRegardless()
    }
    private func presentFocusGuardWindowIfNeeded() {
        let args = ProcessInfo.processInfo.arguments
        guard !args.contains("--snapshot"), !args.contains("--self-test") else { return }
        guard let intent = store.pendingFocusGuardIntent else {
            focusGuardWindow?.orderOut(nil)
            return
        }
        if popover.isShown {
            focusGuardWindow?.orderOut(nil)
            return
        }
        if focusGuardWindow == nil {
            let panel = NSPanel(
                contentRect: NSRect(x: 0, y: 0, width: 460, height: 390),
                styleMask: [.titled, .fullSizeContentView],
                backing: .buffered,
                defer: false
            )
            panel.title = "FokusBar Fokus-Schutz"
            panel.titleVisibility = .hidden
            panel.titlebarAppearsTransparent = true
            panel.isReleasedWhenClosed = false
            panel.isFloatingPanel = true
            panel.hidesOnDeactivate = false
            panel.level = .floating
            panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
            focusGuardWindow = panel
        }
        guard let panel = focusGuardWindow else { return }
        panel.contentViewController = NSHostingController(
            rootView: FocusGuardChallengeCard(store: store, intent: intent)
                .padding(10)
                .frame(width: 460)
        )
        let area = (window?.screen ?? NSScreen.main)?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
        panel.setFrameOrigin(NSPoint(x: area.midX - 230, y: area.midY - 195))
        NSApp.activate(ignoringOtherApps: true)
        panel.makeKeyAndOrderFront(nil)
    }
    private func installFixtures() {
        let today = Calendar.current.startOfDay(for: store.now)
        let design = FocusTask(title: "Neue Startseite gestalten", notes: "Hero, Produktvorteile und mobile Ansicht in Ruhe durchgehen.", project: "Website", priority: .high, dueDate: today, reminder: store.now.addingTimeInterval(3600))
        let mail = FocusTask(title: "Kundenanfragen beantworten", project: "Organisation", dueDate: today)
        let move = FocusTask(title: "Eine Runde an die frische Luft", priority: .low, dueDate: today, recurrence: .daily)
        let planned = FocusTask(title: "Nächste Woche vorbereiten", project: "Organisation", dueDate: today.addingTimeInterval(86400 * 2))
        let done = FocusTask(title: "Angebot fertigstellen", project: "Website", createdAt: today, dueDate: today, completedAt: today.addingTimeInterval(3600))
        store.state.tasks = [design, mail, move, planned, done]
        for (i, day) in Statistics.days(inWeekContaining: store.now).enumerated() where day <= today {
            let start = day.addingTimeInterval(9 * 3600)
            let end = min(start.addingTimeInterval(Double([72, 105, 48, 95, 30, 50, 20][i]) * 60), store.now.addingTimeInterval(-3600))
            if end > start { store.state.entries.append(TimeEntry(taskID: design.id, taskTitle: design.title, project: design.project, start: start, end: end, mode: .focus)) }
        }
        store.state.active = ActiveTimer(taskID: design.id, title: design.title, project: design.project, mode: .focus, target: 1500, accumulated: 462, segmentStart: store.now)
        store.state.completedFocusSessions = 2
    }
    private func snapshot(path: String, menu: Bool, dark: Bool, quickEntry: Bool, floatingTimer: Bool = false) async {
        guard path.hasPrefix("/") else { NSApp.terminate(nil); return }
        let args = ProcessInfo.processInfo.arguments
        let small = args.contains("--small")
        if args.contains("--idle") {
            store.state.active = nil
        }
        if let sIdx = args.firstIndex(of: "--focus-sound"), args.indices.contains(sIdx + 1) {
            store.state.preferences.focusSound = args[sIdx + 1]
        }
        if args.contains("--with-blocked-apps") {
            store.state.preferences.blockedApps = [
                BlockedApp(bundleIdentifier: "com.apple.Safari", name: "Safari", path: "/Applications/Safari.app"),
                BlockedApp(bundleIdentifier: "com.apple.mail", name: "Mail", path: "/System/Applications/Mail.app"),
                BlockedApp(bundleIdentifier: "com.apple.MobileSMS", name: "Nachrichten", path: "/System/Applications/Messages.app")
            ]
            store.state.preferences.blockedWebsites = [
                "instagram.com",
                "youtube.com",
                "x.com"
            ]
            store.state.preferences.appBlockerEnabled = true
        }
        if args.contains("--focus-guard") {
            store.pendingFocusGuardIntent = .pause
        }
        if floatingTimer {
            if let mIdx = args.firstIndex(of: "--timer-mode"), args.indices.contains(mIdx + 1), let mode = TimerMode(rawValue: args[mIdx + 1]) {
                store.state.active?.mode = mode
                if mode == .stopwatch {
                    store.state.active?.accumulated = 824
                } else if mode == .rest {
                    store.state.active?.target = 300
                    store.state.active?.accumulated = 112
                } else if mode == .countdown {
                    store.state.active?.target = 900
                    store.state.active?.accumulated = 315
                }
            }
            if args.contains("--urgent") {
                store.state.active?.target = 1500
                store.state.active?.accumulated = 1458
            }
            if args.contains("--paused") {
                store.state.active?.segmentStart = nil
            }
        }
        let size: NSSize = if floatingTimer {
            FloatingTimerPanel.panelSize
        } else if quickEntry {
            NSSize(width: 620, height: 134)
        } else {
            NSSize(width: menu ? 420 : small ? 940 : 1080, height: menu ? 660 : small ? 700 : 760)
        }
        if quickEntry { self.quickEntry.text = ProcessInfo.processInfo.environment["FOKUS_QUICK_TEXT"] ?? ""; self.quickEntry.focusToken = 1 }
        let root: AnyView = if floatingTimer {
            AnyView(FloatingTimerView(store: store).background(Color(red: 0.12, green: 0.14, blue: 0.18)))
        } else if quickEntry {
            AnyView(QuickEntryView(store: store, model: self.quickEntry) {})
        } else {
            AnyView(AppSurface(store: store, menu: menu))
        }
        let hosting = NSHostingView(rootView: root.environment(\.colorScheme, dark ? .dark : .light))
        hosting.frame = NSRect(origin: .zero, size: size)
        let window = NSWindow(contentRect: hosting.frame, styleMask: [.borderless], backing: .buffered, defer: false)
        window.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
        window.contentView = hosting
        window.setFrameOrigin(NSPoint(x: -2000, y: -2000))
        snapshotWindow = window
        window.orderBack(nil)
        hosting.layoutSubtreeIfNeeded()
        try? await Task.sleep(nanoseconds: 700_000_000)
        hosting.displayIfNeeded()
        if let bitmap = hosting.bitmapImageRepForCachingDisplay(in: hosting.bounds) {
            hosting.cacheDisplay(in: hosting.bounds, to: bitmap)
            if let data = bitmap.representation(using: .png, properties: [:]) { do { try data.write(to: URL(fileURLWithPath: path), options: .atomic) } catch { print(error) } }
        }
        window.orderOut(nil); NSApp.terminate(nil)
    }
    private func systemCheck(path: String) async {
        guard path.hasPrefix("/") else { NSApp.terminate(nil); return }
        let center = UNUserNotificationCenter.current()
        let sound = NSSound(named: "Glass")
        var result: [String: Any] = ["soundLoaded": sound != nil, "soundPlaybackStarted": sound?.play() ?? false, "notificationCheck": "awaiting authorization"]
        if let data = try? JSONSerialization.data(withJSONObject: result, options: [.prettyPrinted, .sortedKeys]) { try? data.write(to: URL(fileURLWithPath: path), options: .atomic) }
        do {
            let allowed = try await center.requestAuthorization(options: [.alert, .sound])
            result["notificationsAuthorized"] = allowed
            result["notificationCheck"] = "completed"
            if allowed {
                let content = UNMutableNotificationContent(); content.title = "FokusBar ist bereit"; content.body = "Erinnerungen und Timer sind eingerichtet."
                try await center.add(UNNotificationRequest(identifier: "setup-check", content: content, trigger: UNTimeIntervalNotificationTrigger(timeInterval: 2, repeats: false)))
                try? await Task.sleep(nanoseconds: 4_000_000_000)
                let delivered = await center.deliveredNotifications()
                result["testNotificationDelivered"] = delivered.contains { $0.request.identifier == "setup-check" }
                center.removeDeliveredNotifications(withIdentifiers: ["setup-check"])
            }
        } catch { result["error"] = error.localizedDescription }
        if let data = try? JSONSerialization.data(withJSONObject: result, options: [.prettyPrinted, .sortedKeys]) { try? data.write(to: URL(fileURLWithPath: path), options: .atomic) }
        NSApp.terminate(nil)
    }
    private func runSelfTest() {
        let task = FocusTask(title: "Integrationstest", project: "QA")
        precondition(store.saveTask(task))
        store.startTimer(task: task, mode: .focus, minutes: 25)
        precondition(store.active?.taskID == task.id)
        precondition(store.isFocusSoundPlaying == true)
        precondition(store.selectedFocusSound == .gentleRain && store.selectedFocusSound.isNatureSound)
        for natureSound in FocusSoundCategory.nature.items {
            guard let res = natureSound.audioResourceName,
                  let url = FocusAudioController.resolveNatureAudioURL(named: res),
                  FileManager.default.fileExists(atPath: url.path) else {
                preconditionFailure("Missing nature audio file for \(natureSound)")
            }
        }
        store.selectFocusSound(.forestNature)
        precondition(store.selectedFocusSound == .forestNature && store.selectedFocusSound.isNatureSound)
        store.selectFocusSound(.jazzHouseLounge)
        precondition(store.selectedFocusSound == .jazzHouseLounge && store.selectedFocusSound.isSpotify)
        store.selectFocusSound(.courtenRadio)
        precondition(store.selectedFocusSound == .courtenRadio && store.selectedFocusSound.isSpotify)
        store.toggleFocusSoundMute()
        precondition(store.selectedFocusSound == .off && store.isFocusSoundPlaying == false)
        store.setFocusSoundVolume(0.7, unmuteIfOff: true)
        precondition(store.selectedFocusSound == .courtenRadio && store.isFocusSoundPlaying == true)
        precondition(abs(store.preferences.effectiveFocusSoundVolume - 0.7) < 0.001)
        store.setFocusMinutes(45)
        precondition(store.preferences.focusMinutes == 45)
        let targetBefore = store.active?.target ?? 0
        store.adjustActiveTimerMinutes(5)
        precondition(abs((store.active?.target ?? 0) - (targetBefore + 300)) < 0.1)
        // Test Focus Guard (Breathing Challenge interception on Pause/Stop)
        precondition(store.isFocusGuardRequired == true)
        store.requestPauseTimer()
        precondition(store.pendingFocusGuardIntent == .pause && store.active?.isRunning == true)
        store.cancelFocusGuardChallenge()
        precondition(store.pendingFocusGuardIntent == nil && store.active?.isRunning == true)
        store.requestPauseTimer()
        store.completeFocusGuardChallenge()
        precondition(store.active?.isRunning == false && store.isFocusSoundPlaying == false)
        store.resumeTimer(); precondition(store.active?.isRunning == true && store.isFocusSoundPlaying == true)
        // Test App & Website Blocker
        let sampleBlocked = BlockedApp(bundleIdentifier: "com.apple.Chess", name: "Schach")
        store.toggleBlockedApp(sampleBlocked)
        precondition(store.isAppBlocked(sampleBlocked) && store.isAppBlockerActive == true)
        precondition(store.addBlockedWebsite("https://www.instagram.com/reels/"))
        precondition(store.isWebsiteBlocked("instagram.com") && store.totalBlockedItemsCount == 2)
        store.toggleBlockedWebsite("twitter.com")
        precondition(store.isWebsiteBlocked("x.com") && store.totalBlockedItemsCount == 3)
        // While Focus is running, trying to disable blocker triggers Focus Guard
        store.setAppBlockerEnabled(false)
        precondition(store.pendingFocusGuardIntent == .unlockBlocker && store.isAppBlockerActive == true)
        store.completeFocusGuardChallenge()
        precondition(store.isAppBlockerActive == false)
        store.setAppBlockerEnabled(true)
        precondition(store.isAppBlockerActive == true)
        store.pauseTimer()
        store.removeBlockedApp(sampleBlocked)
        store.removeBlockedWebsite("instagram.com")
        store.removeBlockedWebsite("x.com")
        precondition(!store.isAppBlocked(sampleBlocked) && store.blockedWebsites.isEmpty && store.isAppBlockerActive == false)
        store.resumeTimer()
        store.toggleTask(task); precondition(store.tasks[0].isCompleted && store.active == nil)
        store.toggleTask(store.tasks[0]); precondition(!store.tasks[0].isCompleted)
        var repeated = FocusTask(title: "Täglich", dueDate: Date(), recurrence: .daily)
        precondition(store.saveTask(repeated)); store.toggleTask(repeated)
        let count = store.tasks.count
        store.toggleTask(repeated); store.toggleTask(repeated)
        precondition(store.tasks.count == count)
        repeated.title = ""; precondition(!store.saveTask(repeated))
        var preferences = store.preferences; preferences.focusMinutes = 40; store.savePreferences(preferences)
        precondition(store.preferences.focusMinutes == 40)
        let entry = TimeEntry(taskTitle: "Nachtrag", start: Date().addingTimeInterval(-3600), end: Date().addingTimeInterval(-3000))
        precondition(store.saveEntry(entry))
        precondition(!store.saveEntry(TimeEntry(taskTitle: "Überschneidung", start: entry.start, end: entry.end)))
        store.deleteEntry(entry); precondition(!store.entries.contains { $0.id == entry.id })
        store.archiveTask(task); precondition(!store.tasks.contains { $0.id == task.id })
        store.restoreTask(task); precondition(store.tasks.contains { $0.id == task.id })
        store.startTimer(task: task, mode: .focus, minutes: 1)
        store.startBreak(); precondition(store.active?.mode == .rest && store.isFocusSoundPlaying == false)
        store.startNextFocus(); precondition(store.active?.taskID == task.id && store.isFocusSoundPlaying == true)
        store.stopTimer()
        precondition(store.addQuickTask("Schnelltest #QA @morgen !"))
        let quick = store.tasks.last
        precondition(quick?.title == "Schnelltest" && quick?.project == "QA" && quick?.priority == .high && quick?.dueDate == Calendar.current.date(byAdding: .day, value: 1, to: Calendar.current.startOfDay(for: Date())))
        print("PASS: task CRUD, timer integration, completion, recurrence deduplication, validation, preferences, manual entries, overlap prevention, archive restore, focus-break task attribution, quick add, focus sounds, Spotify Courten Radio, App/Website blocker & Focus Guard breathing barrier")
        NSApp.terminate(nil)
    }
}

private struct AppSurface: View {
    @ObservedObject var store: FocusStore
    let menu: Bool
    var body: some View {
        Group { if menu { MenuPanel(store: store) } else { DashboardView(store: store) } }
            .preferredColorScheme(store.preferences.appearance == "dark" ? .dark : store.preferences.appearance == "light" ? .light : nil)
    }
}
