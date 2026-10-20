import Foundation

public enum TimerEngine {
    public static func start(state: inout AppState, task: FocusTask?, mode: TimerMode, minutes: Int, at now: Date) {
        stop(state: &state, at: now)
        if mode.isWork { state.lastWorkTaskID = task?.id }
        state.active = ActiveTimer(taskID: task?.id, title: task?.title ?? (mode == .rest ? "Erholung" : "Freie Sitzung"), project: task?.project ?? "", mode: mode, target: TimeInterval(min(1440, max(1, minutes)) * 60), segmentStart: now)
        state.lastCheckpoint = now
    }
    public static func pause(state: inout AppState, at now: Date) {
        guard var timer = state.active, let start = timer.segmentStart else { return }
        let end = max(start, min(now, timer.deadline ?? now))
        if timer.mode.isWork, end > start {
            state.entries.append(TimeEntry(taskID: timer.taskID, taskTitle: timer.title, project: timer.project, start: start, end: end, mode: timer.mode))
        }
        timer.accumulated = timer.elapsed(at: end)
        timer.segmentStart = nil
        state.active = timer
        state.lastCheckpoint = now
    }
    public static func resume(state: inout AppState, at now: Date) {
        guard var timer = state.active, !timer.isRunning, timer.suspendedDeadline == nil else { return }
        timer.segmentStart = now
        state.active = timer
        state.lastCheckpoint = now
    }
    public static func stop(state: inout AppState, at now: Date) {
        pause(state: &state, at: now)
        state.active = nil
        state.lastCheckpoint = now
    }
    @discardableResult public static func tick(state: inout AppState, at now: Date) -> TimerMode? {
        guard let timer = state.active, let deadline = timer.deadline, now >= deadline else { return nil }
        pause(state: &state, at: deadline)
        state.active = nil
        if timer.mode == .focus { state.completedFocusSessions += 1 }
        return timer.mode
    }
    public static func sleep(state: inout AppState, at now: Date) {
        guard let active = state.active, active.isRunning else { return }
        let deadline = active.deadline
        pause(state: &state, at: now)
        state.active?.suspendedDeadline = deadline
    }
    @discardableResult public static func wake(state: inout AppState, at now: Date) -> TimerMode? {
        guard var timer = state.active, let deadline = timer.suspendedDeadline else { return nil }
        timer.suspendedDeadline = nil
        if now >= deadline {
            state.active = nil
            if timer.mode == .focus { state.completedFocusSessions += 1 }
            return timer.mode
        }
        timer.accumulated = max(0, timer.target - deadline.timeIntervalSince(now))
        // Stay paused after sleep; only explicit resume records work again.
        state.active = timer
        return nil
    }
    @discardableResult public static func recover(state: inout AppState, at now: Date) -> Bool {
        guard state.active != nil else { return false }
        let checkpoint = min(now, state.lastCheckpoint ?? state.active?.segmentStart ?? now)
        pause(state: &state, at: checkpoint)
        state.active?.suspendedDeadline = nil
        return true
    }
}

public enum TaskRules {
    public static func nextOccurrence(of task: FocusTask, after now: Date, calendar: Calendar = .current) -> FocusTask? {
        guard task.recurrence != .none else { return nil }
        let base = task.dueDate ?? task.reminder ?? now
        var date = base
        var steps = 0
        repeat {
            let component: Calendar.Component = task.recurrence == .monthly ? .month : .day
            let amount = task.recurrence == .weekly ? 7 : 1
            guard let next = calendar.date(byAdding: component, value: amount, to: date) else { return nil }
            date = next
            if task.recurrence == .weekdays {
                while calendar.isDateInWeekend(date) {
                    guard let next = calendar.date(byAdding: .day, value: 1, to: date) else { return nil }
                    date = next
                }
            }
            steps += 1
        } while date <= now && steps < 100_000
        var next = task
        next.id = UUID(); next.predecessorID = task.id; next.createdAt = now; next.completedAt = nil
        next.dueDate = date
        if let reminder = task.reminder {
            let dayOffset = calendar.dateComponents([.day], from: calendar.startOfDay(for: base), to: calendar.startOfDay(for: reminder)).day ?? 0
            let clock = calendar.dateComponents([.hour, .minute, .second], from: reminder)
            let reminderDay = calendar.date(byAdding: .day, value: dayOffset, to: calendar.startOfDay(for: date)) ?? date
            // Missing local times move to the next valid time; repeated times use the first occurrence.
            next.reminder = calendar.date(bySettingHour: clock.hour ?? 9, minute: clock.minute ?? 0, second: clock.second ?? 0, of: reminderDay, matchingPolicy: .nextTime, repeatedTimePolicy: .first, direction: .forward)
            if let reminder = next.reminder, reminder <= now { next.reminder = nil }
        }
        return next
    }
}

public enum Statistics {
    public static func seconds(entries: [TimeEntry], in interval: DateInterval) -> TimeInterval {
        entries.filter { $0.mode.isWork }.reduce(0) { total, entry in
            total + max(0, min(entry.end, interval.end).timeIntervalSince(max(entry.start, interval.start)))
        }
    }
    public static func interval(forDay date: Date, calendar: Calendar = .current) -> DateInterval {
        calendar.dateInterval(of: .day, for: date) ?? DateInterval(start: date, duration: 86400)
    }
    public static func days(inWeekContaining date: Date, calendar: Calendar = .current) -> [Date] {
        var calendar = calendar; calendar.firstWeekday = 2
        let start = calendar.dateInterval(of: .weekOfYear, for: date)?.start ?? calendar.startOfDay(for: date)
        return (0..<7).compactMap { calendar.date(byAdding: .day, value: $0, to: start) }
    }
    public static func csv(entries: [TimeEntry]) -> String {
        let iso = ISO8601DateFormatter()
        func cell(_ string: String) -> String {
            let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
            let safe = ["=", "+", "-", "@"].contains(where: { trimmed.hasPrefix($0) }) ? "'" + string : string
            return "\"" + safe.replacingOccurrences(of: "\"", with: "\"\"") + "\""
        }
        let rows = entries.sorted { $0.start < $1.start }.map { entry in
            [entry.taskTitle, entry.project, iso.string(from: entry.start), iso.string(from: entry.end), String(Int(entry.duration)), entry.mode.title].map(cell).joined(separator: ";")
        }
        return "\u{feff}Aufgabe;Projekt;Start;Ende;Sekunden;Modus\r\n" + rows.joined(separator: "\r\n") + "\r\n"
    }
}

extension Statistics {
    public static func clipped(_ entry: TimeEntry, to interval: DateInterval) -> TimeEntry? {
        let start = max(entry.start, interval.start), end = min(entry.end, interval.end)
        guard end > start else { return nil }
        var result = entry; result.start = start; result.end = end
        return result
    }
}

public enum ReminderRules {
    public static func key(for task: FocusTask) -> String? {
        guard let reminder = task.reminder else { return nil }
        return task.id.uuidString + ":" + String(Int(reminder.timeIntervalSince1970.rounded()))
    }
    public static func due(in state: AppState, at now: Date) -> [FocusTask] {
        let dismissed = Set(state.dismissedReminderKeys ?? [])
        return state.tasks.filter { task in
            guard !task.archived, !task.isCompleted, let date = task.reminder, date <= now, let key = key(for: task) else { return false }
            return !dismissed.contains(key)
        }.sorted { $0.reminder! < $1.reminder! }
    }
}
