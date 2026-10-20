import XCTest
@testable import FocusCore

final class FocusCoreTests: XCTestCase {
    let t = Date(timeIntervalSince1970: 1_800_000_000)
    func testPauseResumeExcludesGap() {
        var state = AppState()
        TimerEngine.start(state: &state, task: nil, mode: .stopwatch, minutes: 25, at: t)
        TimerEngine.pause(state: &state, at: t.addingTimeInterval(60))
        TimerEngine.pause(state: &state, at: t.addingTimeInterval(120))
        TimerEngine.resume(state: &state, at: t.addingTimeInterval(600))
        TimerEngine.stop(state: &state, at: t.addingTimeInterval(630))
        XCTAssertEqual(state.entries.count, 2)
        XCTAssertEqual(state.entries.reduce(0) { $0 + $1.duration }, 90)
        XCTAssertNil(state.active)
    }
    func testCountdownClampsDelayedTickAndCompletesOnce() {
        var state = AppState()
        TimerEngine.start(state: &state, task: nil, mode: .focus, minutes: 1, at: t)
        XCTAssertEqual(TimerEngine.tick(state: &state, at: t.addingTimeInterval(120)), .focus)
        XCTAssertEqual(state.entries.first?.duration, 60)
        XCTAssertEqual(state.completedFocusSessions, 1)
        XCTAssertNil(TimerEngine.tick(state: &state, at: t.addingTimeInterval(130)))
        XCTAssertEqual(state.completedFocusSessions, 1)
    }
    func testSwitchRecordsOldTaskAndOnlyOneTimer() {
        var state = AppState()
        let a = FocusTask(title: "A"), b = FocusTask(title: "B")
        TimerEngine.start(state: &state, task: a, mode: .stopwatch, minutes: 25, at: t)
        TimerEngine.start(state: &state, task: b, mode: .focus, minutes: 30, at: t.addingTimeInterval(30))
        XCTAssertEqual(state.entries.first?.taskID, a.id)
        XCTAssertEqual(state.entries.first?.duration, 30)
        XCTAssertEqual(state.active?.taskID, b.id)
    }
    func testBreakPreservesWorkTaskAttribution() {
        var state = AppState()
        let task = FocusTask(title: "Focus")
        TimerEngine.start(state: &state, task: task, mode: .focus, minutes: 1, at: t)
        _ = TimerEngine.tick(state: &state, at: t.addingTimeInterval(60))
        TimerEngine.start(state: &state, task: nil, mode: .rest, minutes: 1, at: t.addingTimeInterval(60))
        XCTAssertEqual(state.lastWorkTaskID, task.id)
        _ = TimerEngine.tick(state: &state, at: t.addingTimeInterval(120))
        XCTAssertEqual(state.lastWorkTaskID, task.id)
    }
    func testBreakNeverAddsWork() {
        var state = AppState()
        TimerEngine.start(state: &state, task: nil, mode: .rest, minutes: 1, at: t)
        XCTAssertEqual(TimerEngine.tick(state: &state, at: t.addingTimeInterval(61)), .rest)
        XCTAssertTrue(state.entries.isEmpty)
        XCTAssertEqual(state.completedFocusSessions, 0)
    }
    func testRecoveryDoesNotCountOfflineTime() {
        var state = AppState()
        TimerEngine.start(state: &state, task: nil, mode: .stopwatch, minutes: 25, at: t)
        state.lastCheckpoint = t.addingTimeInterval(45)
        XCTAssertTrue(TimerEngine.recover(state: &state, at: t.addingTimeInterval(86400)))
        XCTAssertEqual(state.entries.first?.duration, 45)
        XCTAssertEqual(state.active?.isRunning, false)
        _ = TimerEngine.recover(state: &state, at: t.addingTimeInterval(90000))
        XCTAssertEqual(state.entries.count, 1)
    }
    func testSleepExpirationDoesNotRecordSleep() {
        var state = AppState()
        TimerEngine.start(state: &state, task: nil, mode: .focus, minutes: 25, at: t)
        TimerEngine.sleep(state: &state, at: t.addingTimeInterval(100))
        XCTAssertEqual(state.entries.first?.duration, 100)
        XCTAssertEqual(TimerEngine.wake(state: &state, at: t.addingTimeInterval(2000)), .focus)
        XCTAssertNil(state.active)
        XCTAssertEqual(state.entries.reduce(0) { $0 + $1.duration }, 100)
    }
    func testWakeBeforeDeadlineKeepsPausedRemaining() {
        var state = AppState()
        TimerEngine.start(state: &state, task: nil, mode: .countdown, minutes: 10, at: t)
        TimerEngine.sleep(state: &state, at: t.addingTimeInterval(60))
        XCTAssertNil(TimerEngine.wake(state: &state, at: t.addingTimeInterval(300)))
        XCTAssertEqual(state.active?.remaining(at: t.addingTimeInterval(300)), 300)
        XCTAssertEqual(state.active?.isRunning, false)
        TimerEngine.resume(state: &state, at: t.addingTimeInterval(1000))
        TimerEngine.stop(state: &state, at: t.addingTimeInterval(1030))
        XCTAssertEqual(state.entries.reduce(0) { $0 + $1.duration }, 90)
    }
    func testStopwatchSleepRemainsPaused() {
        var state = AppState()
        TimerEngine.start(state: &state, task: nil, mode: .stopwatch, minutes: 1, at: t)
        TimerEngine.sleep(state: &state, at: t.addingTimeInterval(20))
        XCTAssertNil(TimerEngine.wake(state: &state, at: t.addingTimeInterval(300)))
        XCTAssertEqual(state.active?.elapsed(at: t.addingTimeInterval(500)), 20)
    }
    func testClockBackwardsDoesNotCreateNegativeTime() {
        var state = AppState()
        TimerEngine.start(state: &state, task: nil, mode: .stopwatch, minutes: 1, at: t)
        TimerEngine.stop(state: &state, at: t.addingTimeInterval(-100))
        XCTAssertTrue(state.entries.isEmpty)
    }
    func testClippingKeepsIdentityAndOnlyIntervalTime() {
        let entry = TimeEntry(taskTitle: "Overnight", start: t.addingTimeInterval(-600), end: t.addingTimeInterval(600))
        let clipped = Statistics.clipped(entry, to: DateInterval(start: t, duration: 86400))!
        XCTAssertEqual(clipped.id, entry.id)
        XCTAssertEqual(clipped.duration, 600)
        XCTAssertEqual(entry.duration, 1200)
        XCTAssertNil(Statistics.clipped(entry, to: DateInterval(start: t.addingTimeInterval(1000), duration: 100)))
    }
    func testMidnightSplitsDuration() {
        let entry = TimeEntry(start: t.addingTimeInterval(-600), end: t.addingTimeInterval(600))
        XCTAssertEqual(Statistics.seconds(entries: [entry], in: DateInterval(start: t, duration: 86400)), 600)
        XCTAssertEqual(Statistics.seconds(entries: [entry], in: DateInterval(start: t.addingTimeInterval(-86400), duration: 86400)), 600)
    }
    func testDSTDayHasCorrectLengthAndMondayStart() {
        var calendar = Calendar(identifier: .gregorian); calendar.timeZone = TimeZone(identifier: "Europe/Berlin")!
        let date = calendar.date(from: DateComponents(year: 2026, month: 10, day: 25, hour: 12))!
        XCTAssertEqual(Statistics.interval(forDay: date, calendar: calendar).duration, 25 * 3600)
        let days = Statistics.days(inWeekContaining: date, calendar: calendar)
        XCTAssertEqual(days.count, 7)
        XCTAssertEqual(calendar.component(.weekday, from: days[0]), 2)
        XCTAssertEqual(calendar.component(.day, from: days[6]), 25)
    }
    func testWeekdayRecurrenceSkipsWeekend() {
        var calendar = Calendar(identifier: .gregorian); calendar.timeZone = TimeZone(identifier: "Europe/Berlin")!
        let friday = calendar.date(from: DateComponents(year: 2026, month: 10, day: 16, hour: 9))!
        let task = FocusTask(title: "Daily", dueDate: friday, reminder: friday.addingTimeInterval(-3600), recurrence: .weekdays)
        let next = TaskRules.nextOccurrence(of: task, after: friday, calendar: calendar)!
        XCTAssertEqual(calendar.component(.day, from: next.dueDate!), 19)
        XCTAssertEqual(calendar.component(.hour, from: next.reminder!), 8)
        XCTAssertEqual(next.predecessorID, task.id)
        XCTAssertNotEqual(next.id, task.id)
    }
    func testRecurringRemindersKeepLocalHourAcrossDST() {
        var calendar = Calendar(identifier: .gregorian); calendar.timeZone = TimeZone(identifier: "Europe/Berlin")!
        for (month, day) in [(3, 29), (10, 25)] {
            let due = calendar.date(from: DateComponents(year: 2026, month: month, day: day))!
            let reminder = calendar.date(from: DateComponents(year: 2026, month: month, day: day, hour: 9))!
            let task = FocusTask(title: "Daily", dueDate: due, reminder: reminder, recurrence: .daily)
            let next = TaskRules.nextOccurrence(of: task, after: due, calendar: calendar)!
            XCTAssertEqual(calendar.component(.hour, from: next.reminder!), 9)
            XCTAssertEqual(calendar.component(.day, from: next.reminder!), day + 1)
        }
    }
    func testNonexistentReminderTimeMovesToNextValidTime() {
        var calendar = Calendar(identifier: .gregorian); calendar.timeZone = TimeZone(identifier: "Europe/Berlin")!
        let due = calendar.date(from: DateComponents(year: 2026, month: 3, day: 28))!
        let reminder = calendar.date(from: DateComponents(year: 2026, month: 3, day: 28, hour: 2, minute: 30))!
        let task = FocusTask(title: "Daily", dueDate: due, reminder: reminder, recurrence: .daily)
        let next = TaskRules.nextOccurrence(of: task, after: due, calendar: calendar)!
        XCTAssertEqual(calendar.component(.day, from: next.reminder!), 29)
        XCTAssertEqual(calendar.component(.hour, from: next.reminder!), 3)
        XCTAssertEqual(calendar.component(.minute, from: next.reminder!), 0)
    }
    func testOverdueRecurrenceSkipsPastOccurrences() {
        let task = FocusTask(title: "Daily", dueDate: t.addingTimeInterval(-86400 * 50), recurrence: .daily)
        XCTAssertGreaterThan(TaskRules.nextOccurrence(of: task, after: t)!.dueDate!, t)
        XCTAssertNil(TaskRules.nextOccurrence(of: FocusTask(title: "Once"), after: t))
    }
    func testRoundtripAndPrivatePermissions() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: dir) }
        let repo = LocalRepository(directory: dir)
        var state = AppState(); state.tasks = [FocusTask(title: "Äpfel ✓", createdAt: t)]
        try repo.save(state)
        XCTAssertEqual(try repo.load(), state)
        state.tasks[0].title = "Updated"; try repo.save(state)
        XCTAssertEqual(try LocalRepository.decode(Data(contentsOf: repo.backupURL)).tasks[0].title, "Äpfel ✓")
        let attrs = try FileManager.default.attributesOfItem(atPath: repo.stateURL.path)
        XCTAssertEqual((attrs[.posixPermissions] as? NSNumber)?.intValue, 0o600)
    }
    func testCorruptDataNeverOverwritten() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: dir) }
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let repo = LocalRepository(directory: dir)
        let bad = Data("invalid original".utf8); try bad.write(to: repo.stateURL)
        XCTAssertThrowsError(try repo.load())
        XCTAssertThrowsError(try repo.save(AppState()))
        XCTAssertEqual(try Data(contentsOf: repo.stateURL), bad)
        try repo.restore(AppState())
        XCTAssertEqual(try repo.load(), AppState())
        XCTAssertTrue(try FileManager.default.contentsOfDirectory(atPath: dir.path).contains { $0.hasPrefix("before-restore-") })
    }
    func testRejectsUnknownVersionDuplicateIDsAndBadIntervals() throws {
        var state = AppState(); state.version = 42
        XCTAssertThrowsError(try state.validated())
        state = AppState(); let task = FocusTask(title: "Duplicate"); state.tasks = [task, task]
        XCTAssertThrowsError(try state.validated())
        state = AppState(); state.entries = [TimeEntry(start: t, end: t.addingTimeInterval(-1))]
        XCTAssertThrowsError(try state.validated())
        state = AppState(); state.preferences.focusMinutes = 0
        XCTAssertThrowsError(try state.validated())
    }
    func testCSVQuotesAndFormulaProtection() {
        let entry = TimeEntry(taskTitle: "=1+1", project: "Test;\"Name\"", start: t, end: t.addingTimeInterval(90))
        let csv = Statistics.csv(entries: [entry])
        XCTAssertTrue(csv.contains("\"'=1+1\""))
        XCTAssertTrue(csv.contains("\"Test;\"\"Name\"\"\""))
        XCTAssertTrue(csv.contains("\"90\""))
    }
    func testLocalRemindersCatchUpAndDoNotRepeatAfterAcknowledgement() throws {
        var state = AppState()
        let task = FocusTask(title: "Reminder", reminder: t)
        state.tasks = [task]
        XCTAssertTrue(ReminderRules.due(in: state, at: t.addingTimeInterval(-1)).isEmpty)
        XCTAssertEqual(ReminderRules.due(in: state, at: t.addingTimeInterval(500)).count, 1)
        state.dismissedReminderKeys = [ReminderRules.key(for: task)!]
        let reloaded = try LocalRepository.decode(LocalRepository.encode(state))
        XCTAssertTrue(ReminderRules.due(in: reloaded, at: t.addingTimeInterval(500)).isEmpty)
        state.tasks[0].reminder = t.addingTimeInterval(600)
        XCTAssertEqual(ReminderRules.due(in: state, at: t.addingTimeInterval(601)).count, 1)
        state.tasks[0].archived = true
        XCTAssertTrue(ReminderRules.due(in: state, at: t.addingTimeInterval(601)).isEmpty)
        state.tasks[0].archived = false; state.tasks[0].completedAt = t
        XCTAssertTrue(ReminderRules.due(in: state, at: t.addingTimeInterval(601)).isEmpty)
    }
    func testTimerFormatting() {
        XCTAssertEqual(TimeFormat.clock(3661), "1:01:01")
        XCTAssertEqual(TimeFormat.clock(-5), "00:00")
        XCTAssertFalse(TimeFormat.clock(1e300).isEmpty)
        XCTAssertFalse(TimeFormat.short(.infinity).isEmpty)
        XCTAssertEqual(TimeFormat.short(61), "1 Min.")
    }
    func testQuickAddParsesExplicitTokensOnly() {
        var calendar = Calendar(identifier: .gregorian); calendar.timeZone = TimeZone(identifier: "Europe/Berlin")!
        let now = calendar.date(from: DateComponents(year: 2026, month: 10, day: 16, hour: 10))! // Freitag
        let today = calendar.startOfDay(for: now)
        let r = QuickAddParser.parse("Angebot schreiben #website @morgen !", now: now, calendar: calendar, knownProjects: ["Website"])
        XCTAssertEqual(r.title, "Angebot schreiben")
        XCTAssertEqual(r.project, "Website")
        XCTAssertEqual(r.priority, .high)
        XCTAssertEqual(r.dueDate, calendar.date(byAdding: .day, value: 1, to: today))
        let plain = QuickAddParser.parse("Kuchen für morgen backen", now: now, calendar: calendar)
        XCTAssertEqual(plain.title, "Kuchen für morgen backen")
        XCTAssertFalse(plain.hasTokens)
        XCTAssertNil(QuickAddParser.parse("Platz #1 sichern", now: now, calendar: calendar).project)
        XCTAssertEqual(QuickAddParser.parse("Launch #Neue_Seite", now: now, calendar: calendar).project, "Neue Seite")
        XCTAssertEqual(QuickAddParser.parse("Review @fr", now: now, calendar: calendar).dueDate, today)
        XCTAssertEqual(QuickAddParser.parse("Review @mo", now: now, calendar: calendar).dueDate, calendar.date(byAdding: .day, value: 3, to: today))
        XCTAssertEqual(QuickAddParser.parse("Steuer @3.1.", now: now, calendar: calendar).dueDate, calendar.date(from: DateComponents(year: 2027, month: 1, day: 3)))
        XCTAssertNil(QuickAddParser.parse("Termin @31.2.", now: now, calendar: calendar).dueDate)
        XCTAssertEqual(QuickAddParser.parse("Termin @31.2.", now: now, calendar: calendar).title, "Termin @31.2.")
        XCTAssertEqual(QuickAddParser.parse("#Website !", now: now, calendar: calendar).title, "#Website !")
        XCTAssertEqual(QuickAddParser.parse("Ablage !niedrig", now: now, calendar: calendar).priority, .low)
    }
    func testDailyGoalLoadsFromOlderFilesAndIsValidated() throws {
        // State files written before the goal existed have no key and must keep loading with the four-hour default.
        let old = Data(#"{"sound":"Glass","soundEnabled":true,"notificationsEnabled":true,"showMenuTime":true,"focusMinutes":25,"breakMinutes":5,"longBreakMinutes":15,"appearance":"system"}"#.utf8)
        let decoded = try JSONDecoder().decode(Preferences.self, from: old)
        XCTAssertNil(decoded.dailyGoalMinutes)
        XCTAssertEqual(decoded.dailyGoal, 4 * 3600)
        var state = AppState(); state.preferences.dailyGoalMinutes = 0
        XCTAssertEqual(state.preferences.dailyGoal, 0)
        XCTAssertNoThrow(try state.validated())
        state.preferences.dailyGoalMinutes = 961
        XCTAssertThrowsError(try state.validated())
        state.preferences.dailyGoalMinutes = -15
        XCTAssertThrowsError(try state.validated())
    }
    func testQuickEntryShortcutDefaultsToOnForOlderFiles() throws {
        let old = Data(#"{"sound":"Glass","soundEnabled":true,"notificationsEnabled":true,"showMenuTime":true,"focusMinutes":25,"breakMinutes":5,"longBreakMinutes":15,"appearance":"system"}"#.utf8)
        var preferences = try JSONDecoder().decode(Preferences.self, from: old)
        XCTAssertTrue(preferences.quickEntryEnabled)
        preferences.quickEntryHotKey = false
        let roundTrip = try JSONDecoder().decode(Preferences.self, from: JSONEncoder().encode(preferences))
        XCTAssertFalse(roundTrip.quickEntryEnabled)
    }
    func testFloatingTimerDefaultsToOnForOlderFiles() throws {
        let old = Data(#"{"sound":"Glass","soundEnabled":true,"notificationsEnabled":true,"showMenuTime":true,"focusMinutes":25,"breakMinutes":5,"longBreakMinutes":15,"appearance":"system"}"#.utf8)
        var preferences = try JSONDecoder().decode(Preferences.self, from: old)
        XCTAssertTrue(preferences.showFloatingTimer)
        preferences.floatingTimer = false
        let roundTrip = try JSONDecoder().decode(Preferences.self, from: JSONEncoder().encode(preferences))
        XCTAssertFalse(roundTrip.showFloatingTimer)
    }
    func testFocusSoundsAndSpotifyPresetsLoadAndValidate() throws {
        let old = Data(#"{"sound":"Glass","soundEnabled":true,"notificationsEnabled":true,"showMenuTime":true,"focusMinutes":25,"breakMinutes":5,"longBreakMinutes":15,"appearance":"system"}"#.utf8)
        let decoded = try JSONDecoder().decode(Preferences.self, from: old)
        XCTAssertEqual(decoded.selectedFocusSound, .gentleRain)
        XCTAssertEqual(decoded.effectiveFocusSoundVolume, 0.45, accuracy: 0.001)
        XCTAssertTrue(decoded.playsFocusSoundInAllWorkModes)
        XCTAssertTrue(decoded.shouldPlayFocusSound(for: .focus))
        XCTAssertFalse(decoded.shouldPlayFocusSound(for: .rest))
        XCTAssertTrue(FocusSound.courtenRadio.isSpotify)
        XCTAssertNotNil(FocusSound.courtenRadio.spotifyURI)
        XCTAssertTrue(FocusSound.deepFocus.isSpotify)
        XCTAssertTrue(FocusSound.jazzHouseLounge.isSpotify)
        XCTAssertTrue(FocusSound.gentleRain.isNatureSound)
        XCTAssertTrue(FocusSound.forestNature.isNatureSound)
        XCTAssertNotNil(FocusSound.gentleRain.audioResourceName)
        XCTAssertEqual(FocusSound.resolved(from: "gamma40"), .gentleRain)
        XCTAssertEqual(FocusSound.resolved(from: "binauralRain"), .gentleRain)

        var state = AppState()
        state.preferences.focusSound = FocusSound.courtenRadio.rawValue
        state.preferences.focusSoundVolume = 0.75
        XCTAssertNoThrow(try state.validated())

        state.preferences.focusSound = "gamma40"
        XCTAssertNoThrow(try state.validated())

        state.preferences.focusSound = "unknown-sound"
        XCTAssertThrowsError(try state.validated())

        state.preferences.focusSound = FocusSound.forestNature.rawValue
        state.preferences.focusSoundVolume = 1.5
        XCTAssertThrowsError(try state.validated())
    }
    func testAppBlockerLoadsValidatesAndProtectsSystemApps() throws {
        let old = Data(#"{"sound":"Glass","soundEnabled":true,"notificationsEnabled":true,"showMenuTime":true,"focusMinutes":25,"breakMinutes":5,"longBreakMinutes":15,"appearance":"system"}"#.utf8)
        let decoded = try JSONDecoder().decode(Preferences.self, from: old)
        XCTAssertTrue(decoded.isAppBlockerEnabled)
        XCTAssertTrue(decoded.effectiveBlockedApps.isEmpty)
        XCTAssertFalse(decoded.shouldBlockApps(for: .focus))

        var prefs = Preferences()
        let discord = BlockedApp(bundleIdentifier: "com.hnc.Discord", name: "Discord")
        prefs.blockedApps = [discord]
        XCTAssertTrue(prefs.shouldBlockApps(for: .focus))
        XCTAssertFalse(prefs.shouldBlockApps(for: .countdown))
        XCTAssertFalse(prefs.shouldBlockApps(for: .rest))
        prefs.blockAppsInAllWorkModes = true
        XCTAssertTrue(prefs.shouldBlockApps(for: .countdown))
        XCTAssertFalse(prefs.shouldBlockApps(for: .rest))
        prefs.appBlockerEnabled = false
        XCTAssertFalse(prefs.shouldBlockApps(for: .focus))

        var state = AppState()
        state.preferences.blockedApps = [discord]
        XCTAssertNoThrow(try state.validated())

        state.preferences.blockedApps = [BlockedApp(bundleIdentifier: "de.justin.fokusbar", name: "FokusBar")]
        XCTAssertThrowsError(try state.validated())

        state.preferences.blockedApps = [BlockedApp(bundleIdentifier: "com.apple.finder", name: "Finder")]
        XCTAssertThrowsError(try state.validated())
    }
    func testWebsiteBlockerAndFocusGuardLoadAndValidate() throws {
        XCTAssertEqual(BlockedWebsite.normalizeDomain("https://www.instagram.com/reels/123?hl=de"), "instagram.com")
        XCTAssertEqual(BlockedWebsite.normalizeDomain("https://youtu.be/dQw4w9WgXcQ"), "youtube.com")
        XCTAssertEqual(BlockedWebsite.normalizeDomain("https://twitter.com/home"), "x.com")
        XCTAssertEqual(BlockedWebsite.normalizeDomain("m.youtube.com"), "youtube.com")
        XCTAssertNil(BlockedWebsite.normalizeDomain("keine domain"))

        let blocked = ["instagram.com", "youtube.com", "x.com"]
        XCTAssertEqual(BlockedWebsite.matchedDomain(for: "https://www.instagram.com/explore", in: blocked), "instagram.com")
        XCTAssertEqual(BlockedWebsite.matchedDomain(for: "https://youtu.be/abc", in: blocked), "youtube.com")
        XCTAssertEqual(BlockedWebsite.matchedDomain(for: "https://yewtu.be/watch?v=abc", in: blocked), "youtube.com")
        XCTAssertEqual(BlockedWebsite.matchedDomain(for: "https://mobile.twitter.com/test", in: blocked), "x.com")
        XCTAssertEqual(BlockedWebsite.matchedDomain(for: "https://xcancel.com/someone", in: blocked), "x.com")
        XCTAssertEqual(BlockedWebsite.matchedDomain(for: "https://translate.google.com/translate?u=https%3A%2F%2Fwww.youtube.com%2Fwatch", in: blocked), "youtube.com")
        XCTAssertEqual(BlockedWebsite.matchedDomain(for: "https://www.croxyproxy.com/", in: blocked), "croxyproxy.com")
        XCTAssertNil(BlockedWebsite.matchedDomain(for: "https://developer.apple.com", in: blocked))

        var prefs = Preferences()
        XCTAssertTrue(prefs.isFocusGuardEnabled)
        XCTAssertEqual(prefs.effectiveFocusGuardSeconds, 30)
        XCTAssertTrue(prefs.shouldRequireFocusGuard(for: .focus))
        XCTAssertFalse(prefs.shouldRequireFocusGuard(for: .rest))

        prefs.blockedWebsites = ["https://www.instagram.com", "twitter.com", "youtube.com"]
        XCTAssertEqual(prefs.effectiveBlockedWebsites, ["instagram.com", "x.com", "youtube.com"])
        XCTAssertEqual(prefs.totalBlockedItemsCount, 3)
        XCTAssertTrue(prefs.shouldBlockApps(for: .focus))

        var state = AppState()
        state.preferences = prefs
        state.preferences.focusGuardSeconds = 60
        XCTAssertNoThrow(try state.validated())

        state.preferences.focusGuardSeconds = 5
        XCTAssertThrowsError(try state.validated())

        state.preferences.focusGuardSeconds = 45
        state.preferences.blockedWebsites = ["not a domain"]
        XCTAssertThrowsError(try state.validated())
    }
    func testAllBundledSoundsAndSpotifyPlaylistsArePortable() throws {
        let repoRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        for sound in FocusSound.playableCases {
            if sound.isNatureSound {
                let res = try XCTUnwrap(sound.audioResourceName)
                let fileURL = repoRoot.appendingPathComponent("Resources/Sounds/\(res).m4a")
                XCTAssertTrue(FileManager.default.fileExists(atPath: fileURL.path), "Missing bundled sound: \(res).m4a")
            } else if sound.isSpotify {
                let id = try XCTUnwrap(sound.spotifyPlaylistID)
                XCTAssertFalse(id.isEmpty)
                let webURL = try XCTUnwrap(sound.spotifyWebURL)
                XCTAssertTrue(webURL.absoluteString.hasPrefix("https://open.spotify.com/playlist/"))
            }
        }
    }
}
