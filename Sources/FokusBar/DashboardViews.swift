import SwiftUI
import AppKit
import FocusCore

// MARK: - Sections

enum FokusSection: String, CaseIterable, Identifiable {
    case today, planned, all, completed, archive, analytics, settings

    var id: String { rawValue }

    var title: String {
        switch self {
        case .today: "Heute"
        case .planned: "Geplant"
        case .all: "Alle Aufgaben"
        case .completed: "Erledigt"
        case .archive: "Archiv"
        case .analytics: "Zeitübersicht"
        case .settings: "Einstellungen"
        }
    }

    var icon: String {
        switch self {
        case .today: "sun.max"
        case .planned: "calendar"
        case .all: "tray.full"
        case .completed: "checkmark.circle"
        case .archive: "archivebox"
        case .analytics: "chart.bar.xaxis"
        case .settings: "gearshape"
        }
    }
}

struct TaskEditorRequest: Identifiable {
    let id = UUID()
    let task: FocusTask
    let isNew: Bool
}

// MARK: - Dashboard

struct DashboardView: View {
    @ObservedObject var store: FocusStore
    @State private var search = ""
    @State private var projectFilter: ProjectFilter = .all
    @State private var editor: TaskEditorRequest?

    private var section: FokusSection { FokusSection(rawValue: store.requestedSection) ?? .today }

    private var selection: Binding<String?> {
        Binding(
            get: { store.requestedSection },
            set: { if let value = $0 { store.requestedSection = value } }
        )
    }

    var body: some View {
        NavigationSplitView {
            DashboardSidebar(store: store, selection: selection)
                .navigationSplitViewColumnWidth(min: 210, ideal: 236, max: 300)
        } detail: {
            detail
                .safeAreaInset(edge: .top, spacing: 0) { bannerArea }
                .background(FokusTheme.canvas)
                .navigationTitle(section.title)
                .toolbar {
                    ToolbarItem(placement: .primaryAction) {
                        Button {
                            openNewTask(title: "")
                        } label: {
                            Label("Neue Aufgabe", systemImage: "plus")
                        }
                        .keyboardShortcut("n", modifiers: .command)
                        .help("Neue Aufgabe mit allen Details (⌘N)")
                    }
                }
        }
        .frame(minWidth: 920, idealWidth: 1080, minHeight: 680, idealHeight: 760)
        .tint(FokusTheme.accent)
        .sheet(item: $editor) { request in
            TaskEditorSheet(store: store, request: request)
        }
        .onChange(of: store.requestedTaskID) { _, _ in consumeRequestedTask() }
        .onAppear { consumeRequestedTask() }
        .background { sectionShortcuts }
    }

    /// ⌘1 … ⌘7 jump straight to a section.
    private var sectionShortcuts: some View {
        ZStack {
            ForEach(Array(FokusSection.allCases.enumerated()), id: \.element) { index, item in
                Button(item.title) { store.requestedSection = item.rawValue }
                    .keyboardShortcut(KeyEquivalent(Character("\(index + 1)")), modifiers: .command)
            }
        }
        .opacity(0)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private func consumeRequestedTask() {
        guard let id = store.requestedTaskID, let task = store.tasks.first(where: { $0.id == id }) else { return }
        editor = TaskEditorRequest(task: task, isNew: false)
        store.requestedTaskID = nil
    }

    @ViewBuilder private var detail: some View {
        switch section {
        case .archive:
            ArchiveScreen(store: store)
        case .analytics:
            AnalyticsScreen(store: store)
        case .settings:
            SettingsScreen(store: store)
        case .today, .planned, .all, .completed:
            TaskListScreen(
                store: store,
                section: section,
                search: $search,
                projectFilter: $projectFilter,
                onEdit: { editor = TaskEditorRequest(task: $0, isNew: false) },
                onNew: { openNewTask(title: $0) }
            )
        }
    }

    @ViewBuilder private var bannerArea: some View {
        if StatusBanners.hasContent(store) {
            StatusBanners(store: store)
                .padding(.horizontal, 32)
                .padding(.top, 14)
                .padding(.bottom, 6)
                .frame(maxWidth: 840)
                .frame(maxWidth: .infinity)
                .background(FokusTheme.canvas)
        }
    }

    private func openNewTask(title: String) {
        var task = FocusTask(title: title)
        if case .named(let project) = projectFilter { task.project = project }
        if section == .planned { task.dueDate = Calendar.current.startOfDay(for: store.now) }
        editor = TaskEditorRequest(task: task, isNew: true)
    }
}

struct DashboardSidebar: View {
    @ObservedObject var store: FocusStore
    @Binding var selection: String?

    var body: some View {
        let open = store.tasks.filter { !$0.isCompleted }
        let todayCount = open.filter { TaskQuery.belongsToToday($0, now: store.now) }.count
        let plannedCount = open.filter { $0.dueDate != nil }.count

        List(selection: $selection) {
            Section("Aufgaben") {
                row(.today, count: todayCount)
                row(.planned, count: plannedCount)
                row(.all, count: open.count)
                row(.completed, count: 0)
                row(.archive, count: 0)
            }
            Section("Auswertung") {
                row(.analytics, count: 0)
            }
            Section("App") {
                row(.settings, count: 0)
            }
        }
        .listStyle(.sidebar)
        .scrollContentBackground(.hidden)
        .background(FokusTheme.sidebar)
        .safeAreaInset(edge: .bottom, spacing: 0) {
            SidebarTimerPanel(store: store)
                .padding(10)
        }
    }

    private func row(_ section: FokusSection, count: Int) -> some View {
        Label {
            Text(section.title).foregroundStyle(Color.primary)
        } icon: {
            Image(systemName: section.icon).foregroundStyle(FokusTheme.accent)
        }
            .badge(count)
            .tag(section.rawValue)
            .help("\(section.title) (⌘\((FokusSection.allCases.firstIndex(of: section) ?? 0) + 1))")
    }
}

// MARK: - Task lists

private struct TaskListGroup: Identifiable {
    let id: String
    let title: String?
    let warning: Bool
    let tasks: [FocusTask]

    init(id: String, title: String?, warning: Bool = false, tasks: [FocusTask]) {
        self.id = id
        self.title = title
        self.warning = warning
        self.tasks = tasks
    }
}

struct TaskListScreen: View {
    @ObservedObject var store: FocusStore
    let section: FokusSection
    @Binding var search: String
    @Binding var projectFilter: ProjectFilter
    let onEdit: (FocusTask) -> Void
    let onNew: (String) -> Void

    @State private var quickTitle = ""
    @State private var archiveCandidate: FocusTask?

    private var isFiltering: Bool { !search.fokusTrimmed.isEmpty || projectFilter != .all }

    var body: some View {
        let groups = makeGroups()
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                header
                if section != .completed {
                    QuickAddField(
                        placeholder: quickPlaceholder,
                        text: $quickTitle,
                        projects: store.projects,
                        onSubmit: { input in
                            if case .named(let project) = projectFilter {
                                store.addQuickTask(input, defaultProject: project)
                            } else {
                                store.addQuickTask(input)
                            }
                        },
                        onDetails: { onNew($0) }
                    )
                }
                if isFiltering { filterSummary }
                if groups.isEmpty {
                    emptyState
                        .frame(maxWidth: .infinity)
                        .padding(.top, 36)
                } else {
                    ForEach(groups) { group in
                        groupView(group)
                    }
                }
            }
            .padding(.horizontal, 32)
            .padding(.vertical, 26)
            .frame(maxWidth: 840)
            .frame(maxWidth: .infinity)
        }
        .searchable(text: $search, placement: .toolbar, prompt: "Aufgaben durchsuchen")
        .toolbar {
            ToolbarItem(placement: .automatic) {
                Picker(selection: $projectFilter) {
                    Text("Alle Projekte").tag(ProjectFilter.all)
                    Text("Ohne Projekt").tag(ProjectFilter.none)
                    if !store.projects.isEmpty { Divider() }
                    ForEach(store.projects, id: \.self) { project in
                        Text(project).tag(ProjectFilter.named(project))
                    }
                } label: {
                    Label("Projekt", systemImage: "folder")
                }
                .pickerStyle(.menu)
                .labelsHidden()
                .frame(width: 150)
                .fixedSize()
                .help("Nach Projekt filtern")
            }
        }
        .onAppear(perform: validateFilter)
        .onChange(of: store.projects) { _, _ in validateFilter() }
        .archiveConfirmation(candidate: $archiveCandidate, store: store)
    }

    private var quickPlaceholder: String {
        switch section {
        case .today: "Neue Aufgabe für heute, Eingabetaste zum Anlegen"
        case .planned: "Neue Aufgabe, z. B. mit @morgen oder @fr planen"
        default: "Neue Aufgabe, Eingabetaste zum Anlegen"
        }
    }

    private var header: some View {
        let open = store.tasks.filter { !$0.isCompleted }
        let subtitle: String
        switch section {
        case .today: subtitle = FokusFormat.longDate(store.now)
        case .planned: subtitle = "Aufgaben mit Fälligkeitsdatum, nach Tag geordnet"
        case .all: subtitle = open.count == 1 ? "1 offene Aufgabe" : "\(open.count) offene Aufgaben"
        default: subtitle = "Abgeschlossene Aufgaben, neueste zuerst"
        }
        return HStack(alignment: .lastTextBaseline) {
            VStack(alignment: .leading, spacing: 4) {
                Text(section.title)
                    .font(.system(size: 28, weight: .bold))
                    .tracking(-0.3)
                Text(subtitle)
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if section == .today {
                let todayOpen = open.filter { TaskQuery.belongsToToday($0, now: store.now) }.count
                let todayDone = TaskQuery.completedToday(store.tasks, now: store.now).count
                let goal = store.preferences.dailyGoal
                HStack(alignment: .bottom, spacing: 22) {
                    DayProgress(done: todayDone, total: todayOpen + todayDone, width: 140)
                    if goal > 0 {
                        GoalProgress(seconds: store.todaySeconds, goal: goal, width: 140)
                    } else {
                        VStack(alignment: .trailing, spacing: 2) {
                            Text(TimeFormat.short(store.todaySeconds))
                                .font(.system(size: 17, weight: .semibold))
                                .monospacedDigit()
                            Text("heute erfasst")
                                .font(.system(size: 12))
                                .foregroundStyle(.secondary)
                        }
                        .accessibilityElement(children: .combine)
                    }
                }
            }
        }
    }

    private var filterSummary: some View {
        var parts: [String] = []
        switch projectFilter {
        case .all: break
        case .none: parts.append("Ohne Projekt")
        case .named(let name): parts.append("Projekt \(name)")
        }
        let query = search.fokusTrimmed
        if !query.isEmpty { parts.append("Suche „\(query)“") }
        return HStack(spacing: 8) {
            Image(systemName: "line.3.horizontal.decrease.circle")
                .foregroundStyle(FokusTheme.accent)
                .accessibilityHidden(true)
            Text("Gefiltert: \(parts.joined(separator: ", "))")
                .font(.system(size: 12.5))
                .foregroundStyle(.secondary)
                .lineLimit(1)
            Spacer()
            Button("Filter zurücksetzen", action: resetFilter)
                .controlSize(.small)
        }
    }

    @ViewBuilder private var emptyState: some View {
        if isFiltering {
            ContentUnavailableView {
                Label("Keine Treffer", systemImage: "magnifyingglass")
            } description: {
                Text("Keine Aufgabe in „\(section.title)“ passt zu Suche oder Projektfilter.")
            } actions: {
                Button("Filter zurücksetzen", action: resetFilter)
            }
        } else {
            switch section {
            case .today:
                ContentUnavailableView {
                    Label("Dein Tag ist frei", systemImage: "sun.max")
                } description: {
                    Text("Aufgaben ohne Datum und alles, was heute fällig oder überfällig ist, erscheint hier.")
                } actions: {
                    Button("Neue Aufgabe") { onNew("") }
                        .buttonStyle(FokusFilledButtonStyle(large: true))
                }
            case .planned:
                ContentUnavailableView {
                    Label("Nichts geplant", systemImage: "calendar")
                } description: {
                    Text("Gib einer Aufgabe ein Fälligkeitsdatum, dann erscheint sie hier nach Tagen geordnet.")
                } actions: {
                    Button("Aufgabe planen") { onNew("") }
                        .buttonStyle(FokusFilledButtonStyle(large: true))
                }
            case .completed:
                ContentUnavailableView {
                    Label("Noch nichts erledigt", systemImage: "checkmark.circle")
                } description: {
                    Text("Abgehakte Aufgaben sammeln sich hier. Du kannst sie jederzeit wieder öffnen.")
                }
            default:
                ContentUnavailableView {
                    Label("Noch keine Aufgaben", systemImage: "checklist")
                } description: {
                    Text("Lege oben eine Aufgabe an oder drücke ⌘N, um Notizen, Projekt, Termin und Erinnerung festzulegen.")
                } actions: {
                    Button("Neue Aufgabe") { onNew("") }
                        .buttonStyle(FokusFilledButtonStyle(large: true))
                }
            }
        }
    }

    private func groupView(_ group: TaskListGroup) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            if let title = group.title {
                SectionLabel(title: title, trailing: "\(group.tasks.count)", warning: group.warning)
            }
            VStack(spacing: 0) {
                ForEach(Array(group.tasks.enumerated()), id: \.element.id) { index, task in
                    if index > 0 { Divider().padding(.leading, 34) }
                    TaskRow(
                        store: store,
                        task: task,
                        detailed: true,
                        hidesTodayDate: section == .today,
                        onEdit: { onEdit(task) },
                        onArchive: { archiveCandidate = task }
                    )
                }
            }
            .padding(.horizontal, 14)
            .fokusCard(padding: 0)
        }
    }

    private func makeGroups() -> [TaskListGroup] {
        let now = store.now
        let calendar = Calendar.current
        let visible = store.tasks.filter { TaskQuery.matches($0, search: search, project: projectFilter) }
        let open = visible.filter { !$0.isCompleted }

        switch section {
        case .today:
            let today = TaskQuery.sorted(open.filter { TaskQuery.belongsToToday($0, now: now) }, now: now)
            let overdue = today.filter { TaskQuery.isOverdue($0, now: now) }
            let current = today.filter { !TaskQuery.isOverdue($0, now: now) }
            let done = TaskQuery.completedToday(visible, now: now)
            return [
                TaskListGroup(id: "overdue", title: "Überfällig", warning: true, tasks: overdue),
                TaskListGroup(id: "current", title: overdue.isEmpty && done.isEmpty ? nil : "Für heute", tasks: current),
                TaskListGroup(id: "done", title: "Heute erledigt", tasks: done)
            ].filter { !$0.tasks.isEmpty }

        case .planned:
            let dated = open.filter { $0.dueDate != nil }
            let overdue = TaskQuery.sorted(dated.filter { TaskQuery.isOverdue($0, now: now) }, now: now)
            var groups: [TaskListGroup] = overdue.isEmpty ? [] : [TaskListGroup(id: "overdue", title: "Überfällig", warning: true, tasks: overdue)]
            let upcoming = dated.filter { !TaskQuery.isOverdue($0, now: now) }
            let byDay = Dictionary(grouping: upcoming) { calendar.startOfDay(for: $0.dueDate ?? now) }
            for day in byDay.keys.sorted() {
                groups.append(TaskListGroup(
                    id: "day-\(day.timeIntervalSince1970)",
                    title: FokusFormat.sectionDayTitle(day, now: now),
                    tasks: TaskQuery.sorted(byDay[day] ?? [], now: now)
                ))
            }
            return groups

        case .completed:
            let done = visible.filter(\.isCompleted).sorted { ($0.completedAt ?? .distantPast) > ($1.completedAt ?? .distantPast) }
            let byDay = Dictionary(grouping: done) { calendar.startOfDay(for: $0.completedAt ?? now) }
            return byDay.keys.sorted(by: >).map { day in
                TaskListGroup(id: "done-\(day.timeIntervalSince1970)", title: FokusFormat.sectionDayTitle(day, now: now), tasks: byDay[day] ?? [])
            }

        default:
            let sorted = TaskQuery.sorted(open, now: now)
            let byProject = Dictionary(grouping: sorted) { $0.project.fokusTrimmed }
            let names = byProject.keys.filter { !$0.isEmpty }.sorted { $0.localizedStandardCompare($1) == .orderedAscending }
            var groups = names.map { TaskListGroup(id: "project-\($0)", title: $0, tasks: byProject[$0] ?? []) }
            if let loose = byProject[""], !loose.isEmpty {
                groups.append(TaskListGroup(id: "project-none", title: names.isEmpty ? nil : "Ohne Projekt", tasks: loose))
            }
            return groups
        }
    }

    private func resetFilter() {
        search = ""
        projectFilter = .all
    }

    private func validateFilter() {
        if case .named(let name) = projectFilter, !store.projects.contains(name) {
            projectFilter = .all
        }
    }
}

// MARK: - Task editor

struct TaskEditorSheet: View {
    @ObservedObject var store: FocusStore
    let request: TaskEditorRequest

    @Environment(\.dismiss) private var dismiss
    @State private var draft: FocusTask
    @State private var hasDue: Bool
    @State private var due: Date
    @State private var hasReminder: Bool
    @State private var reminder: Date
    @State private var confirmsArchive = false
    @FocusState private var titleFocused: Bool

    init(store: FocusStore, request: TaskEditorRequest) {
        _store = ObservedObject(wrappedValue: store)
        self.request = request
        let task = request.task
        _draft = State(initialValue: task)
        _hasDue = State(initialValue: task.dueDate != nil)
        _due = State(initialValue: task.dueDate ?? Calendar.current.startOfDay(for: Date()))
        _hasReminder = State(initialValue: task.reminder != nil)
        _reminder = State(initialValue: task.reminder ?? FokusFormat.nextFullHour(after: Date()))
    }

    private var trimmedTitle: String { draft.title.fokusTrimmed }

    var body: some View {
        VStack(spacing: 0) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(request.isNew ? "Neue Aufgabe" : "Aufgabe bearbeiten")
                        .font(.system(size: 20, weight: .semibold))
                    if !request.isNew {
                        Text("Angelegt am \(FokusFormat.dayMonthYear(request.task.createdAt))")
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                    }
                }
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
                Section {
                    TextField("Titel", text: $draft.title, prompt: Text("Was möchtest du erledigen?"))
                        .font(.system(size: 15))
                        .focused($titleFocused)
                    TextField("Notizen", text: $draft.notes, prompt: Text("Details, Links, Gedanken"), axis: .vertical)
                        .lineLimit(3...8)
                }

                Section("Einordnung") {
                    LabeledContent("Projekt") {
                        HStack(spacing: 6) {
                            TextField("Projekt", text: $draft.project, prompt: Text("Optional"))
                                .labelsHidden()
                            if !store.projects.isEmpty {
                                Menu {
                                    ForEach(store.projects, id: \.self) { project in
                                        Button(project) { draft.project = project }
                                    }
                                    if !draft.project.isEmpty {
                                        Divider()
                                        Button("Kein Projekt") { draft.project = "" }
                                    }
                                } label: {
                                    Image(systemName: "folder")
                                }
                                .menuStyle(.borderlessButton)
                                .fixedSize()
                                .help("Vorhandenes Projekt wählen")
                                .accessibilityLabel("Vorhandenes Projekt wählen")
                            }
                        }
                    }
                    Picker("Priorität", selection: $draft.priority) {
                        ForEach(Priority.allCases) { Text($0.title).tag($0) }
                    }
                    .pickerStyle(.segmented)
                }

                Section("Termin") {
                    Toggle("Fälligkeitsdatum", isOn: $hasDue.animation(.easeOut(duration: 0.15)))
                    if hasDue {
                        DatePicker("Fällig am", selection: $due, displayedComponents: .date)
                    }
                    Picker("Wiederholen", selection: $draft.recurrence) {
                        ForEach(RepeatRule.allCases) { Text($0.title).tag($0) }
                    }
                }

                Section {
                    Toggle("Erinnerung", isOn: $hasReminder.animation(.easeOut(duration: 0.15)))
                    if hasReminder {
                        DatePicker("Erinnern am", selection: $reminder, displayedComponents: [.date, .hourAndMinute])
                        if reminder < store.now {
                            Label("Dieser Zeitpunkt liegt in der Vergangenheit.", systemImage: "exclamationmark.triangle")
                                .font(.system(size: 12))
                                .foregroundStyle(.orange)
                        }
                    }
                } header: {
                    Text("Erinnerung")
                } footer: {
                    Text(store.preferences.notificationsEnabled
                         ? "Einmalige Mitteilung zum gewählten Zeitpunkt."
                         : "Mitteilungen sind in den Einstellungen ausgeschaltet.")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }

                if !request.isNew {
                    Section("Zeit") {
                        LabeledContent("Insgesamt erfasst", value: TimeFormat.short(store.seconds(for: request.task.id)))
                        if let completed = request.task.completedAt {
                            LabeledContent("Erledigt", value: "\(FokusFormat.dayMonthYear(completed)), \(FokusFormat.time(completed))")
                        }
                    }
                }
            }
            .formStyle(.grouped)

            Divider()

            HStack(spacing: 10) {
                if !request.isNew {
                    Button(role: .destructive) {
                        confirmsArchive = true
                    } label: {
                        Label("Archivieren…", systemImage: "archivebox")
                    }
                }
                Spacer()
                Button("Abbrechen", role: .cancel) { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button(request.isNew ? "Anlegen" : "Sichern", action: save)
                    .keyboardShortcut(.defaultAction)
                    .disabled(trimmedTitle.isEmpty)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 14)
        }
        .frame(width: 560, height: 660)
        .tint(FokusTheme.accent)
        .onAppear { if request.isNew { titleFocused = true } }
        .confirmationDialog("Aufgabe archivieren?", isPresented: $confirmsArchive, titleVisibility: .visible) {
            Button("Archivieren", role: .destructive) {
                store.archiveTask(request.task)
                dismiss()
            }
            Button("Abbrechen", role: .cancel) {}
        } message: {
            Text("„\(request.task.title)“ verschwindet aus allen Listen. Bereits erfasste Zeiten bleiben erhalten.")
        }
    }

    private func save() {
        guard !trimmedTitle.isEmpty else { return }
        var task = draft
        task.title = trimmedTitle
        task.project = draft.project.fokusTrimmed
        task.dueDate = hasDue ? Calendar.current.startOfDay(for: due) : nil
        task.reminder = hasReminder ? reminder : nil
        if store.saveTask(task) { dismiss() }
    }
}

struct ArchiveScreen: View {
    @ObservedObject var store: FocusStore
    var body: some View {
        let archived = store.state.tasks.filter(\.archived).sorted { $0.createdAt > $1.createdAt }
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Text("Archiv").font(.system(size: 28, weight: .bold))
                Text("Entfernte Aufgaben und ihre Zeiten bleiben erhalten. Du kannst sie jederzeit zurückholen.").foregroundStyle(.secondary)
                if archived.isEmpty {
                    ContentUnavailableView("Dein Archiv ist leer", systemImage: "archivebox", description: Text("Archivierte Aufgaben erscheinen hier."))
                } else {
                    ForEach(archived) { task in
                        HStack(spacing: 16) {
                            VStack(alignment: .leading, spacing: 5) {
                                Text(task.title).font(.headline)
                                Text(task.project.isEmpty ? (task.isCompleted ? "Erledigt" : "Offen") : task.project).foregroundStyle(.secondary)
                                Text(TimeFormat.short(store.seconds(for: task.id))).font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                            Button("Wiederherstellen") { store.restoreTask(task) }.buttonStyle(.bordered)
                        }.fokusCard()
                    }
                }
            }.padding(32).frame(maxWidth: 840).frame(maxWidth: .infinity)
        }
    }
}
