import SwiftUI
import AppKit
import FocusCore

// MARK: - Week data

private struct TaskTotal: Identifiable {
    let id: String
    let taskID: UUID?
    let title: String
    let project: String
    var seconds: TimeInterval
    var sessions: Int
}

private struct WeekSummary {
    let reference: Date
    let days: [Date]
    let values: [TimeInterval]
    let start: Date
    let end: Date
    let total: TimeInterval
    let previousTotal: TimeInterval
    let entries: [TimeEntry]
    let taskTotals: [TaskTotal]

    var workCount: Int { entries.filter { $0.mode.isWork }.count }
    var restCount: Int { entries.filter { !$0.mode.isWork }.count }
    var activeDays: Int { values.filter { $0 > 0 }.count }
    var average: TimeInterval { activeDays > 0 ? total / Double(activeDays) : 0 }

    @MainActor init(store: FocusStore, offset: Int) {
        let calendar = Calendar.current
        let now = store.now
        let reference = calendar.date(byAdding: .weekOfYear, value: offset, to: now) ?? now
        let days = Statistics.days(inWeekContaining: reference)
        let start = days.first.map { Statistics.interval(forDay: $0).start } ?? calendar.startOfDay(for: reference)
        let end = max(start, days.last.map { Statistics.interval(forDay: $0).end } ?? start.addingTimeInterval(7 * 86400))
        let previousStart = calendar.date(byAdding: .day, value: -7, to: start) ?? start.addingTimeInterval(-7 * 86400)

        // Entries are at most a week long, so this window covers everything that can overlap.
        let candidates = store.entries.filter { $0.end > previousStart.addingTimeInterval(-7 * 86400) && $0.start < end }
        let work = candidates.filter { $0.mode.isWork }

        let values = days.map { Statistics.seconds(entries: work, in: Statistics.interval(forDay: $0)) }

        let weekEntries = candidates
            .filter { $0.end > start && $0.start < end }
            .sorted { $0.start > $1.start }

        var buckets: [String: TaskTotal] = [:]
        for entry in weekEntries where entry.mode.isWork {
            let key = entry.taskID?.uuidString ?? "title:\(entry.taskTitle)"
            var bucket = buckets[key] ?? TaskTotal(id: key, taskID: entry.taskID, title: entry.taskTitle, project: entry.project, seconds: 0, sessions: 0)
            bucket.seconds += Statistics.seconds(entries: [entry], in: DateInterval(start: start, end: end))
            bucket.sessions += 1
            buckets[key] = bucket
        }

        self.reference = reference
        self.days = days
        self.values = values
        self.start = start
        self.end = end
        self.total = values.reduce(0, +)
        self.previousTotal = Statistics.seconds(entries: work, in: DateInterval(start: previousStart, end: start))
        self.entries = weekEntries
        self.taskTotals = buckets.values.sorted { $0.seconds > $1.seconds }
    }
}

struct EntryEditorRequest: Identifiable {
    let id = UUID()
    let entry: TimeEntry
    let isNew: Bool
}

// MARK: - Analytics screen

struct AnalyticsScreen: View {
    @ObservedObject var store: FocusStore
    @State private var weekOffset = 0
    @State private var entryEditor: EntryEditorRequest?
    @State private var deleteCandidate: TimeEntry?

    var body: some View {
        let week = WeekSummary(store: store, offset: weekOffset)
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                header(week)
                statCards(week)
                chartCard(week)
                taskTotalsCard(week)
                sessionsCard(week)
            }
            .padding(.horizontal, 32)
            .padding(.vertical, 26)
            .frame(maxWidth: 900)
            .frame(maxWidth: .infinity)
        }
        .sheet(item: $entryEditor) { request in
            EntryEditorSheet(store: store, request: request)
        }
        .confirmationDialog(
            "Eintrag löschen?",
            isPresented: Binding(get: { deleteCandidate != nil }, set: { if !$0 { deleteCandidate = nil } }),
            titleVisibility: .visible,
            presenting: deleteCandidate
        ) { entry in
            Button("Löschen", role: .destructive) { store.deleteEntry(entry) }
            Button("Abbrechen", role: .cancel) {}
        } message: { entry in
            Text("„\(entry.taskTitle)“ mit \(TimeFormat.short(entry.duration)) wird dauerhaft entfernt.")
        }
    }

    // MARK: Header

    private func header(_ week: WeekSummary) -> some View {
        let calendar = Calendar.current
        let number = calendar.component(.weekOfYear, from: week.reference)
        let lastDay = week.days.last ?? week.start
        let relative: String
        switch weekOffset {
        case 0: relative = "Diese Woche"
        case -1: relative = "Letzte Woche"
        default: relative = "KW \(number)"
        }
        let range = "\(FokusFormat.dayMonth(week.start)) bis \(FokusFormat.dayMonthYear(lastDay))"

        return HStack(alignment: .lastTextBaseline, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Zeitübersicht")
                    .font(.system(size: 28, weight: .bold))
                Text(weekOffset == 0 || weekOffset == -1 ? "\(relative), KW \(number), \(range)" : "\(relative), \(range)")
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
            Spacer()
            HStack(spacing: 6) {
                Button {
                    weekOffset -= 1
                } label: {
                    Image(systemName: "chevron.left")
                }
                .help("Vorherige Woche")
                .accessibilityLabel("Vorherige Woche")
                Button("Diese Woche") { weekOffset = 0 }
                    .disabled(weekOffset == 0)
                Button {
                    weekOffset += 1
                } label: {
                    Image(systemName: "chevron.right")
                }
                .disabled(weekOffset >= 0)
                .help("Nächste Woche")
                .accessibilityLabel("Nächste Woche")
            }
            Button {
                openNewEntry(week)
            } label: {
                Label("Zeit eintragen", systemImage: "plus")
            }
            .buttonStyle(FokusFilledButtonStyle())
        }
    }

    // MARK: Stats

    private func statCards(_ week: WeekSummary) -> some View {
        let comparison: String
        if week.previousTotal <= 0 {
            comparison = week.total > 0 ? "Vorwoche ohne erfasste Zeit" : "Noch keine Zeit erfasst"
        } else {
            let difference = week.total - week.previousTotal
            comparison = "\(difference >= 0 ? "+" : "-")\(TimeFormat.short(abs(difference))) gegenüber Vorwoche"
        }
        return HStack(spacing: 12) {
            StatCard(title: "Arbeitszeit", value: TimeFormat.short(week.total), caption: comparison, icon: "clock")
            StatCard(
                title: "Durchschnitt pro Tag",
                value: TimeFormat.short(week.average),
                caption: week.activeDays == 1 ? "an 1 aktiven Tag" : "an \(week.activeDays) aktiven Tagen",
                icon: "chart.line.uptrend.xyaxis"
            )
            StatCard(
                title: "Sitzungen",
                value: "\(week.workCount)",
                caption: "Gespeicherte Arbeitsblöcke",
                icon: "list.bullet.rectangle"
            )
        }
    }

    // MARK: Chart

    private func chartCard(_ week: WeekSummary) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .firstTextBaseline) {
                Text("Arbeitszeit pro Tag")
                    .font(.system(size: 15, weight: .semibold))
                Spacer()
                let goal = store.preferences.dailyGoal
                let reached = week.values.filter { goal > 0 && $0 >= goal }.count
                Text(goal > 0 ? "Gestrichelt: Tagesziel \(FokusFormat.hours(goal)), an \(reached) von 7 Tagen erreicht" : "Gespeicherte Zeit, ohne Pausen")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
            WeekBarChart(days: week.days, values: week.values, now: store.now, goal: store.preferences.dailyGoal)
                .overlay {
                    if week.total <= 0 {
                        VStack(spacing: 4) {
                            Text("Keine Arbeitszeit in dieser Woche")
                                .font(.system(size: 13, weight: .semibold))
                            Text("Starte einen Timer oder trage Zeit nachträglich ein.")
                                .font(.system(size: 12))
                                .foregroundStyle(.secondary)
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)
                        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(FokusTheme.card))
                        .padding(.bottom, 40)
                    }
                }
        }
        .fokusCard(padding: 18)
    }

    // MARK: Per task

    private func taskTotalsCard(_ week: WeekSummary) -> some View {
        let maximum = max(week.taskTotals.first?.seconds ?? 0, 1)
        return VStack(alignment: .leading, spacing: 12) {
            Text("Nach Aufgabe")
                .font(.system(size: 15, weight: .semibold))
            if week.taskTotals.isEmpty {
                Text("Sobald du in dieser Woche Zeit erfasst, siehst du hier, wohin sie geflossen ist.")
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
                    .padding(.vertical, 4)
            } else {
                VStack(spacing: 12) {
                    ForEach(week.taskTotals) { total in
                        taskTotalRow(total, fraction: total.seconds / maximum)
                    }
                }
            }
        }
        .fokusCard(padding: 18)
    }

    private func taskTotalRow(_ total: TaskTotal, fraction: Double) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                VStack(alignment: .leading, spacing: 1) {
                    Text(total.title)
                        .font(.system(size: 14, weight: .medium))
                        .lineLimit(1)
                    let details = [total.project.fokusTrimmed, total.sessions == 1 ? "1 Sitzung" : "\(total.sessions) Sitzungen"].filter { !$0.isEmpty }
                    Text(details.joined(separator: " · "))
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 1) {
                    Text(TimeFormat.short(total.seconds))
                        .font(.system(size: 14, weight: .semibold))
                        .monospacedDigit()
                    if let taskID = total.taskID, abs(store.seconds(for: taskID) - total.seconds) >= 60 {
                        Text("gesamt \(TimeFormat.short(store.seconds(for: taskID)))")
                            .font(.system(size: 11.5))
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                    }
                }
            }
            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule().fill(FokusTheme.track)
                    Capsule()
                        .fill(FokusTheme.accent.opacity(0.75))
                        .frame(width: max(4, proxy.size.width * min(1, max(0, fraction))))
                }
            }
            .frame(height: 5)
            .accessibilityHidden(true)
        }
        .accessibilityElement(children: .combine)
    }

    // MARK: Sessions

    private func sessionsCard(_ week: WeekSummary) -> some View {
        let days = week.days.reversed().filter { day in
            week.entries.contains { Statistics.clipped($0, to: Statistics.interval(forDay: day)) != nil }
        }


        return VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline) {
                Text("Sitzungen pro Tag")
                    .font(.system(size: 15, weight: .semibold))
                Spacer()
                Button {
                    openNewEntry(week)
                } label: {
                    Label("Eintrag hinzufügen", systemImage: "plus")
                }
                .controlSize(.small)
            }
            if days.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Keine Sitzungen in dieser Woche.")
                        .font(.system(size: 13, weight: .medium))
                    Text("Erfasste Timer erscheinen hier automatisch. Vergessene Zeiten kannst du nachtragen.")
                        .font(.system(size: 12.5))
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 4)
            } else {
                ForEach(days, id: \.self) { day in
                    let entries = week.entries.compactMap { Statistics.clipped($0, to: Statistics.interval(forDay: day)) }
                    let workSeconds = entries.filter { $0.mode.isWork }.reduce(0.0) { $0 + $1.duration }
                    VStack(alignment: .leading, spacing: 6) {
                        SectionLabel(title: FokusFormat.sectionDayTitle(day, now: store.now), trailing: TimeFormat.short(workSeconds))
                        VStack(spacing: 0) {
                            ForEach(Array(entries.enumerated()), id: \.element.id) { index, entry in
                                if index > 0 { Divider().padding(.leading, 15) }
                                EntryRow(
                                    entry: entry,
                                    onEdit: { entryEditor = EntryEditorRequest(entry: store.entries.first(where: { $0.id == entry.id }) ?? entry, isNew: false) },
                                    onDelete: { deleteCandidate = store.entries.first(where: { $0.id == entry.id }) ?? entry }
                                )
                            }
                        }
                        .padding(.horizontal, 12)
                        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(FokusTheme.track))
                    }
                }
            }
        }
        .fokusCard(padding: 18)
    }

    private func openNewEntry(_ week: WeekSummary) {
        let calendar = Calendar.current
        let now = store.now
        let start: Date
        let end: Date
        if now >= week.start && now < week.end {
            let rounded = calendar.dateInterval(of: .minute, for: now)?.start ?? now
            end = rounded
            start = rounded.addingTimeInterval(-30 * 60)
        } else {
            let day = week.days.first ?? week.start
            start = calendar.date(bySettingHour: 9, minute: 0, second: 0, of: day) ?? day
            end = start.addingTimeInterval(60 * 60)
        }
        entryEditor = EntryEditorRequest(entry: TimeEntry(taskTitle: "", start: start, end: end), isNew: true)
    }
}

struct StatCard: View {
    let title: String
    let value: String
    let caption: String
    let icon: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label(title, systemImage: icon)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.secondary)
            Text(value)
                .font(.system(size: 22, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Text(caption)
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .lineLimit(2)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .fokusCard(padding: 16)
        .accessibilityElement(children: .combine)
    }
}

struct WeekBarChart: View {
    let days: [Date]
    let values: [TimeInterval]
    let now: Date
    var goal: TimeInterval = 0

    var body: some View {
        let maximum = max(values.max() ?? 0, goal * 1.1, 1)
        HStack(alignment: .bottom, spacing: 14) {
            ForEach(Array(days.enumerated()), id: \.offset) { index, day in
                let value = index < values.count ? values[index] : 0
                let isToday = Calendar.current.isDate(day, inSameDayAs: now)
                VStack(spacing: 6) {
                    Text(value > 0 ? FokusFormat.compact(value) : " ")
                        .font(.system(size: 11, weight: .medium))
                        .monospacedDigit()
                        .foregroundStyle(isToday ? Color.primary : Color.secondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.75)
                    GeometryReader { proxy in
                        ZStack(alignment: .bottom) {
                            RoundedRectangle(cornerRadius: 6, style: .continuous)
                                .fill(FokusTheme.track)
                            RoundedRectangle(cornerRadius: 6, style: .continuous)
                                .fill(isToday
                                      ? AnyShapeStyle(LinearGradient(colors: [FokusTheme.accentBright, FokusTheme.accentDeep], startPoint: .top, endPoint: .bottom))
                                      : AnyShapeStyle(FokusTheme.accent.opacity(goal > 0 && value >= goal ? 0.85 : 0.42)))
                                .frame(height: value > 0 ? max(4, proxy.size.height * value / maximum) : 0)
                            if goal > 0 {
                                Path { path in
                                    path.move(to: CGPoint(x: 0, y: 1))
                                    path.addLine(to: CGPoint(x: proxy.size.width, y: 1))
                                }
                                .stroke(Color.primary.opacity(0.45), style: StrokeStyle(lineWidth: 1.5, dash: [4, 3]))
                                .frame(height: 2)
                                .offset(y: -proxy.size.height * goal / maximum + 1)
                            }
                        }
                    }
                    .frame(height: 170)
                    Text(FokusFormat.weekdayShort(day))
                        .font(.system(size: 12, weight: isToday ? .semibold : .regular))
                        .foregroundStyle(isToday ? Color.primary : Color.secondary)
                    Text(FokusFormat.dayMonth(day))
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("\(FokusFormat.longDate(day)): \(TimeFormat.short(value))")
            }
        }
    }
}

struct EntryRow: View {
    let entry: TimeEntry
    let onEdit: () -> Void
    let onDelete: () -> Void

    var body: some View {
        let color = FokusTheme.modeColor(entry.mode)
        HStack(spacing: 12) {
            RoundedRectangle(cornerRadius: 1.5)
                .fill(color)
                .frame(width: 3, height: 30)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(entry.taskTitle)
                    .font(.system(size: 14, weight: .medium))
                    .lineLimit(1)
                HStack(spacing: 8) {
                    Text("\(FokusFormat.time(entry.start)) bis \(FokusFormat.time(entry.end))")
                        .monospacedDigit()
                    Label(entry.mode.title, systemImage: FokusTheme.icon(for: entry.mode))
                        .labelStyle(MetaLabelStyle())
                        .foregroundStyle(color)
                    if !entry.project.fokusTrimmed.isEmpty {
                        Label(entry.project, systemImage: "folder")
                            .labelStyle(MetaLabelStyle())
                    }
                }
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .lineLimit(1)
            }
            Spacer(minLength: 8)
            Text(TimeFormat.clock(entry.duration))
                .font(.system(size: 13, weight: .medium))
                .monospacedDigit()
                .foregroundStyle(entry.mode.isWork ? Color.primary : Color.secondary)
            Button(action: onEdit) {
                Image(systemName: "pencil")
                    .frame(width: 22, height: 22)
            }
            .buttonStyle(.borderless)
            .help("Eintrag bearbeiten")
            .accessibilityLabel("Eintrag \(entry.taskTitle) bearbeiten")
            Button(action: onDelete) {
                Image(systemName: "trash")
                    .frame(width: 22, height: 22)
            }
            .buttonStyle(.borderless)
            .foregroundStyle(.secondary)
            .help("Eintrag löschen")
            .accessibilityLabel("Eintrag \(entry.taskTitle) löschen")
        }
        .padding(.vertical, 9)
        .contentShape(Rectangle())
        .onTapGesture(count: 2, perform: onEdit)
        .contextMenu {
            Button("Bearbeiten…", action: onEdit)
            Button("Löschen…", role: .destructive, action: onDelete)
        }
    }
}

// MARK: - Entry editor

struct EntryEditorSheet: View {
    @ObservedObject var store: FocusStore
    let request: EntryEditorRequest

    @Environment(\.dismiss) private var dismiss
    @State private var day: Date
    @State private var startTime: Date
    @State private var endTime: Date
    @State private var title: String
    @State private var project: String
    @State private var taskID: UUID?
    @State private var mode: TimerMode
    @State private var confirmsDelete = false

    init(store: FocusStore, request: EntryEditorRequest) {
        _store = ObservedObject(wrappedValue: store)
        self.request = request
        let entry = request.entry
        _day = State(initialValue: entry.start)
        _startTime = State(initialValue: entry.start)
        _endTime = State(initialValue: entry.end)
        _title = State(initialValue: entry.taskTitle)
        _project = State(initialValue: entry.project)
        _taskID = State(initialValue: entry.taskID)
        _mode = State(initialValue: entry.mode)
    }

    private var range: (start: Date, end: Date) {
        let original = request.entry
        if !request.isNew && day == original.start && startTime == original.start && endTime == original.end {
            return (original.start, original.end)
        }
        let start = combine(day, startTime)
        var end = combine(day, endTime)
        if end <= start { end = Calendar.current.date(byAdding: .day, value: 1, to: end) ?? end.addingTimeInterval(86400) }
        return (start, end)
    }

    private var isValid: Bool {
        let duration = range.end.timeIntervalSince(range.start)
        return duration > 0 && duration < 86400
    }

    private var linkableTasks: [FocusTask] {
        store.tasks.sorted { $0.title.localizedStandardCompare($1.title) == .orderedAscending }
    }

    var body: some View {
        let current = range
        let crossesMidnight = !Calendar.current.isDate(current.start, inSameDayAs: current.end)

        VStack(spacing: 0) {
            HStack {
                Text(request.isNew ? "Zeit eintragen" : "Eintrag bearbeiten")
                    .font(.system(size: 20, weight: .semibold))
                Spacer()
            }
            .padding(.horizontal, 24)
            .padding(.top, 20)
            .padding(.bottom, 6)

            if let message = store.errorMessage {
                FokusBanner(kind: .error, title: message, dismiss: { store.errorMessage = nil })
                    .padding(.horizontal, 20)
                    .padding(.bottom, 4)
            }

            Form {
                Section("Zeitraum") {
                    DatePicker("Datum", selection: $day, displayedComponents: .date)
                    DatePicker("Beginn", selection: $startTime, displayedComponents: .hourAndMinute)
                    DatePicker("Ende", selection: $endTime, displayedComponents: .hourAndMinute)
                    LabeledContent("Dauer") {
                        if isValid {
                            Text(crossesMidnight ? "\(TimeFormat.clock(current.end.timeIntervalSince(current.start))), endet am Folgetag" : TimeFormat.clock(current.end.timeIntervalSince(current.start)))
                                .monospacedDigit()
                        } else {
                            Text("Beginn und Ende sind gleich")
                                .foregroundStyle(.orange)
                        }
                    }
                }

                Section("Zuordnung") {
                    Picker("Aufgabe", selection: $taskID) {
                        Text("Keine Aufgabe").tag(UUID?.none)
                        if let linked = request.entry.taskID, !linkableTasks.contains(where: { $0.id == linked }) {
                            Text("\(request.entry.taskTitle) (archiviert)").tag(Optional(linked))
                        }
                        if !linkableTasks.isEmpty { Divider() }
                        ForEach(linkableTasks) { task in
                            Text(task.title).tag(Optional(task.id))
                        }
                    }
                    TextField("Titel", text: $title, prompt: Text("Freie Sitzung"))
                    TextField("Projekt", text: $project, prompt: Text("Optional"))
                }

                Section {
                    Picker("Art", selection: $mode) {
                        ForEach(TimerMode.allCases) { Text($0.title).tag($0) }
                    }
                } footer: {
                    Text("Pausen erscheinen in der Liste, zählen aber nicht zur Arbeitszeit.")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }
            }
            .formStyle(.grouped)

            Divider()

            HStack(spacing: 10) {
                if !request.isNew {
                    Button(role: .destructive) {
                        confirmsDelete = true
                    } label: {
                        Label("Löschen…", systemImage: "trash")
                    }
                }
                Spacer()
                Button("Abbrechen", role: .cancel) { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button(request.isNew ? "Eintragen" : "Sichern", action: save)
                    .keyboardShortcut(.defaultAction)
                    .disabled(!isValid)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 14)
        }
        .frame(width: 520, height: 600)
        .tint(FokusTheme.accent)
        .onChange(of: taskID) { _, newValue in
            guard let newValue, let task = store.tasks.first(where: { $0.id == newValue }) else { return }
            title = task.title
            project = task.project
        }
        .confirmationDialog("Eintrag löschen?", isPresented: $confirmsDelete, titleVisibility: .visible) {
            Button("Löschen", role: .destructive) {
                store.deleteEntry(request.entry)
                dismiss()
            }
            Button("Abbrechen", role: .cancel) {}
        } message: {
            Text("Dieser Zeiteintrag wird dauerhaft entfernt.")
        }
    }

    private func combine(_ day: Date, _ time: Date) -> Date {
        let calendar = Calendar.current
        let parts = calendar.dateComponents([.hour, .minute], from: time)
        return calendar.date(bySettingHour: parts.hour ?? 0, minute: parts.minute ?? 0, second: 0, of: day) ?? day
    }

    private func save() {
        guard isValid else { return }
        let current = range
        let trimmedTitle = title.fokusTrimmed
        let entry = TimeEntry(
            id: request.entry.id,
            taskID: taskID,
            taskTitle: trimmedTitle.isEmpty ? "Freie Sitzung" : trimmedTitle,
            project: project.fokusTrimmed,
            start: current.start,
            end: current.end,
            mode: mode
        )
        if store.saveEntry(entry) { dismiss() }
    }
}
