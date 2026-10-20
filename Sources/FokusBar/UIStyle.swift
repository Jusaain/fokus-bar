import SwiftUI
import AppKit
import FocusCore

// MARK: - Colors and surfaces

enum FokusTheme {
    static func dynamic(light: NSColor, dark: NSColor) -> Color {
        Color(nsColor: dynamicNS(light: light, dark: dark))
    }

    static func dynamicNS(light: NSColor, dark: NSColor) -> NSColor {
        NSColor(name: nil) { appearance in
            appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua ? dark : light
        }
    }

    private static func rgb(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat, _ a: CGFloat = 1) -> NSColor {
        NSColor(srgbRed: r, green: g, blue: b, alpha: a)
    }

    /// Clear, confident blue for work and primary actions.
    static let accent = dynamic(light: rgb(0.16, 0.40, 0.92), dark: rgb(0.43, 0.64, 1.0))
    /// Deeper end of the blue used for filled hero surfaces.
    static let accentDeep = dynamic(light: rgb(0.10, 0.27, 0.76), dark: rgb(0.13, 0.29, 0.72))
    static let accentBright = dynamic(light: rgb(0.24, 0.50, 0.98), dark: rgb(0.22, 0.42, 0.90))
    /// Soft indigo for rest periods so breaks never look like work.
    static let rest = dynamic(light: rgb(0.45, 0.36, 0.85), dark: rgb(0.70, 0.62, 1.0))
    static let restDeep = dynamic(light: rgb(0.32, 0.23, 0.68), dark: rgb(0.30, 0.22, 0.62))
    static let restBright = dynamic(light: rgb(0.55, 0.45, 0.93), dark: rgb(0.44, 0.35, 0.86))
    /// Cool, quiet window surface.
    static let canvas = dynamic(light: rgb(0.953, 0.961, 0.976), dark: rgb(0.071, 0.082, 0.106))
    /// Lifted card surface.
    static let card = dynamic(light: rgb(1, 1, 1), dark: rgb(0.114, 0.129, 0.161))
    static let sidebar = dynamic(light: rgb(0.925, 0.937, 0.961), dark: rgb(0.055, 0.063, 0.082))
    static let stroke = dynamic(light: rgb(0.10, 0.18, 0.36, 0.09), dark: rgb(1, 1, 1, 0.075))
    static let track = dynamic(light: rgb(0.16, 0.30, 0.62, 0.08), dark: rgb(1, 1, 1, 0.08))
    static let hover = dynamic(light: rgb(0.16, 0.40, 0.92, 0.055), dark: rgb(1, 1, 1, 0.045))
    static let shadow = dynamic(light: rgb(0.10, 0.18, 0.40, 0.07), dark: rgb(0, 0, 0, 0))

    static func modeColor(_ mode: TimerMode) -> Color { mode.isWork ? accent : rest }

    static func heroGradient(_ mode: TimerMode) -> LinearGradient {
        LinearGradient(
            colors: mode.isWork ? [accentBright, accentDeep] : [restBright, restDeep],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    static func icon(for mode: TimerMode) -> String {
        switch mode {
        case .stopwatch: "stopwatch"
        case .countdown: "timer"
        case .focus: "scope"
        case .rest: "cup.and.saucer"
        }
    }
}

struct FokusCardModifier: ViewModifier {
    var padding: CGFloat
    var tint: Color?

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: 14, style: .continuous)
        content
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background {
                ZStack {
                    shape.fill(FokusTheme.card)
                        .shadow(color: FokusTheme.shadow, radius: 10, x: 0, y: 3)
                    if let tint { shape.fill(tint.opacity(0.08)) }
                }
            }
            .overlay { shape.strokeBorder(tint.map { $0.opacity(0.3) } ?? FokusTheme.stroke, lineWidth: 1) }
    }
}

/// Filled surface for the running timer: the one loud element on screen.
struct FokusHeroModifier: ViewModifier {
    var mode: TimerMode
    var padding: CGFloat

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: 16, style: .continuous)
        content
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .foregroundStyle(.white)
            .background {
                shape.fill(FokusTheme.heroGradient(mode))
                    .shadow(color: FokusTheme.modeColor(mode).opacity(0.28), radius: 14, x: 0, y: 6)
            }
            .overlay { shape.strokeBorder(Color.white.opacity(0.12), lineWidth: 1) }
            .environment(\.colorScheme, .dark)
    }
}

extension View {
    func fokusCard(padding: CGFloat = 14, tint: Color? = nil) -> some View {
        modifier(FokusCardModifier(padding: padding, tint: tint))
    }

    func fokusHero(_ mode: TimerMode, padding: CGFloat = 16) -> some View {
        modifier(FokusHeroModifier(mode: mode, padding: padding))
    }
}

// MARK: - Buttons and progress

/// Keeps primary actions blue even when the window is inactive, unlike `.borderedProminent`.
struct FokusFilledButtonStyle: ButtonStyle {
    var color: Color = FokusTheme.accent
    var large = false
    var foreground: Color = .white

    func makeBody(configuration: Configuration) -> some View {
        FilledBody(configuration: configuration, color: color, large: large, foreground: foreground)
    }

    private struct FilledBody: View {
        let configuration: ButtonStyle.Configuration
        let color: Color
        let large: Bool
        let foreground: Color
        @Environment(\.isEnabled) private var isEnabled
        @State private var hovering = false

        var body: some View {
            configuration.label
                .font(.system(size: large ? 13.5 : 12.5, weight: .semibold))
                .foregroundStyle(foreground)
                .padding(.horizontal, large ? 14 : 10)
                .frame(minHeight: large ? 34 : 26)
                .background {
                    RoundedRectangle(cornerRadius: large ? 9 : 7, style: .continuous)
                        .fill(color)
                        .brightness(configuration.isPressed ? -0.08 : (hovering ? 0.04 : 0))
                }
                .opacity(isEnabled ? 1 : 0.45)
                .contentShape(Rectangle())
                .onHover { hovering = $0 }
        }
    }
}

/// Secondary action: tinted text on a soft tinted surface. `onHero` adapts it to the filled timer card.
struct FokusSoftButtonStyle: ButtonStyle {
    var color: Color = FokusTheme.accent
    var large = false
    var onHero = false

    func makeBody(configuration: Configuration) -> some View {
        SoftBody(configuration: configuration, color: color, large: large, onHero: onHero)
    }

    private struct SoftBody: View {
        let configuration: ButtonStyle.Configuration
        let color: Color
        let large: Bool
        let onHero: Bool
        @Environment(\.isEnabled) private var isEnabled
        @State private var hovering = false

        var body: some View {
            let base = onHero ? Color.white : color
            configuration.label
                .font(.system(size: large ? 13.5 : 12.5, weight: .semibold))
                .foregroundStyle(base)
                .padding(.horizontal, large ? 14 : 10)
                .frame(minHeight: large ? 34 : 26)
                .background {
                    RoundedRectangle(cornerRadius: large ? 9 : 7, style: .continuous)
                        .fill(base.opacity(configuration.isPressed ? 0.26 : (hovering ? 0.19 : (onHero ? 0.16 : 0.11))))
                }
                .opacity(isEnabled ? 1 : 0.45)
                .contentShape(Rectangle())
                .onHover { hovering = $0 }
        }
    }
}

struct FokusProgressBar: View {
    let value: Double
    var color: Color = FokusTheme.accent
    var track: Color = FokusTheme.track
    var height: CGFloat = 6

    var body: some View {
        GeometryReader { proxy in
            let fraction = min(1, max(0, value.isFinite ? value : 0))
            ZStack(alignment: .leading) {
                Capsule().fill(track)
                Capsule()
                    .fill(color)
                    .frame(width: fraction > 0 ? max(height, proxy.size.width * fraction) : 0)
            }
        }
        .frame(height: height)
        .animation(.easeOut(duration: 0.4), value: value)
    }
}

struct ProgressRing: View {
    let value: Double
    var color: Color = .white
    var track: Color = Color.white.opacity(0.2)
    var lineWidth: CGFloat = 6

    var body: some View {
        let fraction = min(1, max(0, value.isFinite ? value : 0))
        ZStack {
            Circle().stroke(track, lineWidth: lineWidth)
            Circle()
                .trim(from: 0, to: fraction)
                .stroke(color, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))
        }
        .animation(.easeOut(duration: 0.4), value: fraction)
    }
}

/// "2 von 5 erledigt" with a slim bar, shared by the menu panel and the Today header.
struct DayProgress: View {
    let done: Int
    let total: Int
    var width: CGFloat = 120

    var body: some View {
        if total > 0 {
            VStack(alignment: .trailing, spacing: 5) {
                Text("\(done) von \(total) erledigt")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
                FokusProgressBar(value: Double(done) / Double(total), height: 5)
                    .frame(width: width)
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("\(done) von \(total) Aufgaben für heute erledigt")
        }
    }
}

/// "1 Std. 20 Min. von 4 Std." with a slim bar; reads "Tagesziel erreicht" once the goal is met.
struct GoalProgress: View {
    let seconds: TimeInterval
    let goal: TimeInterval
    var width: CGFloat = 120

    var body: some View {
        let reached = seconds >= goal
        VStack(alignment: .trailing, spacing: 5) {
            HStack(spacing: 4) {
                if reached {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(FokusTheme.accent)
                }
                Text(reached ? "Tagesziel erreicht" : "\(TimeFormat.short(seconds)) von \(FokusFormat.hours(goal))")
            }
            .font(.system(size: 12, weight: .medium))
            .foregroundStyle(.secondary)
            .monospacedDigit()
            FokusProgressBar(value: seconds / goal, height: 5)
                .frame(width: width)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Heute \(TimeFormat.short(seconds)) von \(FokusFormat.hours(goal)) Tagesziel erfasst")
    }
}

extension String {
    var fokusTrimmed: String { trimmingCharacters(in: .whitespacesAndNewlines) }
}

// MARK: - Formatting

enum FokusFormat {
    static let locale = Locale(identifier: "de_DE")
    private static var style: Date.FormatStyle { Date.FormatStyle(locale: locale) }

    static func time(_ date: Date) -> String { date.formatted(Date.FormatStyle(date: .omitted, time: .shortened, locale: locale)) }
    static func longDate(_ date: Date) -> String { date.formatted(style.weekday(.wide).day().month(.wide)) }
    static func shortDate(_ date: Date) -> String { date.formatted(style.weekday(.abbreviated).day().month(.abbreviated)) }
    static func dayMonth(_ date: Date) -> String { date.formatted(style.day().month(.abbreviated)) }
    static func dayMonthYear(_ date: Date) -> String { date.formatted(style.day().month(.abbreviated).year()) }
    static func weekdayShort(_ date: Date) -> String { date.formatted(style.weekday(.abbreviated)) }

    /// "Heute", "Morgen", "Gestern" or a short date.
    static func dayTitle(_ date: Date, now: Date) -> String {
        let calendar = Calendar.current
        if calendar.isDate(date, inSameDayAs: now) { return "Heute" }
        if let next = calendar.date(byAdding: .day, value: 1, to: now), calendar.isDate(date, inSameDayAs: next) { return "Morgen" }
        if let previous = calendar.date(byAdding: .day, value: -1, to: now), calendar.isDate(date, inSameDayAs: previous) { return "Gestern" }
        return shortDate(date)
    }

    static func sectionDayTitle(_ date: Date, now: Date) -> String {
        let title = dayTitle(date, now: now)
        return title == shortDate(date) ? longDate(date) : title
    }

    static func reminderText(_ date: Date, now: Date) -> String { "\(dayTitle(date, now: now)), \(time(date)) Uhr" }

    static func completedText(_ date: Date, now: Date) -> String {
        switch dayTitle(date, now: now) {
        case "Heute": "Erledigt heute um \(time(date)) Uhr"
        case "Gestern": "Erledigt gestern"
        default: "Erledigt am \(dayMonth(date))"
        }
    }

    /// Goal length without zero parts, e.g. "4 Std.", "4 Std. 30 Min." or "45 Min."
    static func hours(_ value: TimeInterval) -> String {
        let minutes = Int(max(0, value.isFinite ? value : 0)) / 60
        if minutes < 60 { return "\(minutes) Min." }
        return minutes % 60 == 0 ? "\(minutes / 60) Std." : "\(minutes / 60) Std. \(minutes % 60) Min."
    }

    /// Short value for chart labels, e.g. "45 Min." or "2:05 Std."
    static func compact(_ value: TimeInterval) -> String {
        let minutes = Int(max(0, value.isFinite ? value : 0)) / 60
        if minutes < 60 { return minutes == 0 && value > 0 ? "< 1 Min." : "\(minutes) Min." }
        return String(format: "%d:%02d Std.", minutes / 60, minutes % 60)
    }

    static func nextFullHour(after date: Date) -> Date {
        Calendar.current.nextDate(after: date, matching: DateComponents(minute: 0), matchingPolicy: .nextTime) ?? date.addingTimeInterval(3600)
    }
}

// MARK: - Task queries

enum ProjectFilter: Hashable {
    case all
    case none
    case named(String)
}

enum TaskQuery {
    private static func dayStart(_ date: Date) -> Date { Calendar.current.startOfDay(for: date) }

    static func isOverdue(_ task: FocusTask, now: Date) -> Bool {
        guard !task.isCompleted, let due = task.dueDate else { return false }
        return dayStart(due) < dayStart(now)
    }

    /// Open tasks without a date, due today, or overdue.
    static func belongsToToday(_ task: FocusTask, now: Date) -> Bool {
        guard !task.isCompleted else { return false }
        guard let due = task.dueDate else { return true }
        return dayStart(due) <= dayStart(now)
    }

    static func completedToday(_ tasks: [FocusTask], now: Date) -> [FocusTask] {
        tasks
            .filter { task in task.completedAt.map { Calendar.current.isDate($0, inSameDayAs: now) } ?? false }
            .sorted { ($0.completedAt ?? .distantPast) > ($1.completedAt ?? .distantPast) }
    }

    /// Overdue first, then priority, then due date, then creation order.
    static func sorted(_ tasks: [FocusTask], now: Date) -> [FocusTask] {
        tasks.sorted { a, b in
            let aOverdue = isOverdue(a, now: now), bOverdue = isOverdue(b, now: now)
            if aOverdue != bOverdue { return aOverdue }
            if a.priority.rank != b.priority.rank { return a.priority.rank > b.priority.rank }
            switch (a.dueDate, b.dueDate) {
            case let (x?, y?) where x != y: return x < y
            case (_?, nil): return true
            case (nil, _?): return false
            default: return a.createdAt < b.createdAt
            }
        }
    }

    static func matches(_ task: FocusTask, search: String, project: ProjectFilter) -> Bool {
        let taskProject = task.project.fokusTrimmed
        switch project {
        case .all: break
        case .none: if !taskProject.isEmpty { return false }
        case .named(let name): if taskProject != name.fokusTrimmed { return false }
        }
        let query = search.fokusTrimmed
        guard !query.isEmpty else { return true }
        return task.title.localizedCaseInsensitiveContains(query)
            || task.notes.localizedCaseInsensitiveContains(query)
            || taskProject.localizedCaseInsensitiveContains(query)
    }
}

// MARK: - Timer choice shared by the start form and task rows

enum TimerChoiceKeys {
    static let mode = "fokus.ui.timerMode"
    static let countdown = "fokus.ui.countdownMinutes"
}

@MainActor
enum TimerChoice {
    static func longBreakDue(_ store: FocusStore) -> Bool {
        let count = store.state.completedFocusSessions
        return count > 0 && count % 4 == 0
    }

    static func minutes(for mode: TimerMode, store: FocusStore, countdown: Int) -> Int {
        switch mode {
        case .stopwatch: 25
        case .countdown: min(max(countdown, 1), 1440)
        case .focus: store.preferences.focusMinutes
        case .rest: longBreakDue(store) ? store.preferences.longBreakMinutes : store.preferences.breakMinutes
        }
    }

    static func describe(_ mode: TimerMode, store: FocusStore, countdown: Int) -> String {
        mode == .stopwatch ? "Stoppuhr" : "\(mode.title) (\(minutes(for: mode, store: store, countdown: countdown)) Min.)"
    }

    static func start(_ store: FocusStore, task: FocusTask?, mode: TimerMode, countdown: Int) {
        store.startTimer(task: mode == .rest ? nil : task, mode: mode, minutes: minutes(for: mode, store: store, countdown: countdown))
    }
}

// MARK: - Small shared pieces

struct AppGlyph: View {
    var size: CGFloat = 30

    var body: some View {
        RoundedRectangle(cornerRadius: size * 0.27, style: .continuous)
            .fill(LinearGradient(colors: [FokusTheme.accentBright, FokusTheme.accentDeep], startPoint: .topLeading, endPoint: .bottomTrailing))
            .frame(width: size, height: size)
            .overlay {
                Image(systemName: "checkmark")
                    .font(.system(size: size * 0.46, weight: .bold))
                    .foregroundStyle(.white)
            }
            .accessibilityHidden(true)
    }
}

struct FocusDots: View {
    let filled: Int
    let color: Color

    var body: some View {
        HStack(spacing: 4) {
            ForEach(0..<4, id: \.self) { index in
                Circle()
                    .fill(index < filled ? color : Color.primary.opacity(0.13))
                    .frame(width: 7, height: 7)
            }
        }
        .accessibilityElement()
        .accessibilityLabel("\(filled) von 4 Fokus-Sitzungen im aktuellen Zyklus")
    }
}

struct MinutesField: View {
    @Binding var value: Int
    let range: ClosedRange<Int>
    var label = "Minuten"
    var step = 1

    var body: some View {
        let clamped = Binding<Int>(
            get: { value },
            set: { value = min(max($0, range.lowerBound), range.upperBound) }
        )
        HStack(spacing: 6) {
            TextField(label, value: clamped, format: .number)
                .textFieldStyle(.roundedBorder)
                .multilineTextAlignment(.trailing)
                .frame(width: 58)
                .labelsHidden()
            Text("Min.").foregroundStyle(.secondary)
            Stepper(label, value: clamped, in: range, step: step)
                .labelsHidden()
        }
    }
}

struct SectionLabel: View {
    let title: String
    var trailing: String? = nil
    var warning = false

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Text(title)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(warning ? Color.red : Color.secondary)
            if let trailing {
                Text(trailing)
                    .font(.system(size: 12))
                    .foregroundStyle(.tertiary)
                    .monospacedDigit()
            }
            Spacer(minLength: 0)
        }
        .padding(.leading, 4)
    }
}

struct QuickAddField: View {
    var placeholder: String
    @Binding var text: String
    var projects: [String] = []
    /// Changing this value moves the keyboard focus into the field, e.g. when a panel opens.
    var focusToken: Int? = nil
    var onSubmit: (String) -> Void
    var onDetails: ((String) -> Void)? = nil
    @FocusState private var focused: Bool

    private var trimmed: String { text.fokusTrimmed }

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            field
            if focused || !trimmed.isEmpty { preview.transition(.opacity) }
        }
        .animation(.easeOut(duration: 0.15), value: focused)
        .task(id: focusToken) {
            guard focusToken != nil else { return }
            try? await Task.sleep(nanoseconds: 50_000_000)
            focused = true
        }
    }

    private var field: some View {
        HStack(spacing: 9) {
            Image(systemName: "plus")
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(.white)
                .frame(width: 20, height: 20)
                .background(Circle().fill(FokusTheme.accent))
                .accessibilityHidden(true)
            TextField(placeholder, text: $text)
                .textFieldStyle(.plain)
                .font(.system(size: 14))
                .focused($focused)
                .onSubmit(submit)
                .accessibilityLabel("Neue Aufgabe")
                .accessibilityHint("Eingabetaste legt die Aufgabe an. Kürzel: Raute für Projekt, at für Datum, Ausrufezeichen für hohe Priorität")
            if !trimmed.isEmpty {
                Button("Hinzufügen", action: submit)
                    .buttonStyle(FokusFilledButtonStyle())
            }
            if let onDetails {
                Button {
                    onDetails(trimmed)
                    text = ""
                } label: {
                    Image(systemName: "square.and.pencil")
                        .font(.system(size: 14))
                        .foregroundStyle(FokusTheme.accent)
                }
                .buttonStyle(.borderless)
                .help("Mit allen Details anlegen")
                .accessibilityLabel("Aufgabe mit Details anlegen")
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(FokusTheme.card)
                .shadow(color: FokusTheme.shadow, radius: focused ? 12 : 8, x: 0, y: 2)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(focused ? FokusTheme.accent.opacity(0.75) : FokusTheme.stroke, lineWidth: focused ? 1.5 : 1)
        }
    }

    @ViewBuilder private var preview: some View {
        let parsed = QuickAddParser.parse(trimmed, now: Date(), knownProjects: projects)
        if parsed.hasTokens {
            HStack(spacing: 6) {
                Text("Wird angelegt mit")
                    .foregroundStyle(.secondary)
                if let project = parsed.project { TokenChip(text: project, icon: "folder") }
                if let priority = parsed.priority { TokenChip(text: priority.title, icon: priority == .high ? "exclamationmark" : "arrow.down", color: priority == .high ? .orange : .secondary) }
                if let due = parsed.dueDate { TokenChip(text: FokusFormat.dayTitle(due, now: Date()), icon: "calendar") }
                Spacer(minLength: 0)
            }
            .font(.system(size: 11.5))
            .padding(.leading, 4)
        } else {
            Text("Kürzel:  #Projekt   @morgen  @fr  @24.12.   !  für hohe Priorität")
                .font(.system(size: 11.5))
                .foregroundStyle(.tertiary)
                .padding(.leading, 4)
        }
    }

    private func submit() {
        let value = trimmed
        guard !value.isEmpty else { return }
        onSubmit(value)
        text = ""
        focused = true
    }
}

struct TokenChip: View {
    let text: String
    let icon: String
    var color: Color = FokusTheme.accent

    var body: some View {
        Label(text, systemImage: icon)
            .labelStyle(MetaLabelStyle())
            .font(.system(size: 11.5, weight: .medium))
            .foregroundStyle(color)
            .padding(.horizontal, 7)
            .padding(.vertical, 2)
            .background(Capsule().fill(color.opacity(0.12)))
            .lineLimit(1)
    }
}

/// Four timer modes as tappable tiles; clearer than a segmented control and keeps its color when inactive.
struct ModeSelector: View {
    @Binding var mode: TimerMode

    var body: some View {
        HStack(spacing: 6) {
            ForEach(TimerMode.allCases) { item in
                let selected = item == mode
                let color = FokusTheme.modeColor(item)
                Button {
                    withAnimation(.easeOut(duration: 0.15)) { mode = item }
                } label: {
                    VStack(spacing: 4) {
                        Image(systemName: FokusTheme.icon(for: item))
                            .font(.system(size: 14, weight: .semibold))
                            .frame(height: 18)
                        Text(item.title)
                            .font(.system(size: 11.5, weight: .semibold))
                            .lineLimit(1)
                            .minimumScaleFactor(0.85)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                    .foregroundStyle(selected ? Color.white : Color.secondary)
                    .background {
                        RoundedRectangle(cornerRadius: 9, style: .continuous)
                            .fill(selected ? AnyShapeStyle(color) : AnyShapeStyle(FokusTheme.track))
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(item.title)
                .accessibilityAddTraits(selected ? .isSelected : [])
            }
        }
    }
}

struct ArchiveConfirmation: ViewModifier {
    @Binding var candidate: FocusTask?
    let store: FocusStore
    var onArchived: (() -> Void)? = nil

    func body(content: Content) -> some View {
        content.confirmationDialog(
            "Aufgabe archivieren?",
            isPresented: Binding(get: { candidate != nil }, set: { if !$0 { candidate = nil } }),
            titleVisibility: .visible,
            presenting: candidate
        ) { task in
            Button("Archivieren", role: .destructive) {
                store.archiveTask(task)
                onArchived?()
            }
            Button("Abbrechen", role: .cancel) {}
        } message: { task in
            Text("„\(task.title)“ verschwindet aus allen Listen. Bereits erfasste Zeiten bleiben in der Zeitübersicht erhalten.")
        }
    }
}

extension View {
    func archiveConfirmation(candidate: Binding<FocusTask?>, store: FocusStore, onArchived: (() -> Void)? = nil) -> some View {
        modifier(ArchiveConfirmation(candidate: candidate, store: store, onArchived: onArchived))
    }
}

// Metadata wraps as whole labels instead of truncating every label in a narrow panel.
struct MetadataFlow: Layout {
    var spacing: CGFloat = 10
    var lineSpacing: CGFloat = 5
    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        layout(width: proposal.width ?? 600, subviews: subviews).size
    }
    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let result = layout(width: bounds.width, subviews: subviews)
        for (index, point) in result.points.enumerated() {
            subviews[index].place(at: CGPoint(x: bounds.minX + point.x, y: bounds.minY + point.y), proposal: ProposedViewSize(width: result.widths[index], height: nil))
        }
    }
    private func layout(width: CGFloat, subviews: Subviews) -> (size: CGSize, points: [CGPoint], widths: [CGFloat]) {
        let width = max(1, width)
        var x: CGFloat = 0, y: CGFloat = 0, lineHeight: CGFloat = 0
        var points: [CGPoint] = [], widths: [CGFloat] = []
        for view in subviews {
            let ideal = view.sizeThatFits(.unspecified)
            let childWidth = min(width, ideal.width)
            let size = view.sizeThatFits(ProposedViewSize(width: childWidth, height: nil))
            if x > 0 && x + childWidth > width { x = 0; y += lineHeight + lineSpacing; lineHeight = 0 }
            points.append(CGPoint(x: x, y: y)); widths.append(childWidth)
            x += childWidth + spacing; lineHeight = max(lineHeight, size.height)
        }
        return (CGSize(width: width, height: y + lineHeight), points, widths)
    }
}
