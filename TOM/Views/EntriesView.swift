import SwiftData
import SwiftUI

struct EntriesView: View {
    let scope: EntryScope

    @Environment(\.modelContext) private var context
    @Environment(TimerController.self) private var timer
    @Query(sort: \TimeEntry.start, order: .reverse) private var allEntries: [TimeEntry]
    @Query(sort: \Project.sortIndex) private var projects: [Project]
    @Query(sort: \Folder.sortIndex) private var folders: [Folder]

    @State private var selection = Set<PersistentIdentifier>()
    @State private var sortOrder = [KeyPathComparator(\TimeEntry.start, order: .reverse)]
    @State private var editingEntry: TimeEntry?
    @State private var creatingEntry = false
    @State private var exportDocument: CSVDocument?
    @State private var pendingMerge: [[TimeEntry]]?

    private var entries: [TimeEntry] {
        allEntries.filter { scope.contains($0, now: timer.now) }
    }

    private var title: String { scope.title }

    private var scopedProject: Project? { scope.project }

    var body: some View {
        let entries = entries
        let total = entries.reduce(0) { $0 + $1.duration(now: timer.now) }

        Group {
            if entries.isEmpty {
                ContentUnavailableView {
                    Label("Noch keine Zeiten", systemImage: "clock")
                } description: {
                    Text("Starte einen Timer über das Symbol in der Menüleiste oder trag eine Zeit von Hand nach.")
                } actions: {
                    Button("Zeit nachtragen") { creatingEntry = true }
                }
            } else {
                EntriesTable(
                    entries: entries.sorted(using: sortOrder),
                    showsProject: scopedProject == nil,
                    showsAmount: entries.contains { $0.project?.hourlyRate != nil },
                    selection: $selection,
                    sortOrder: $sortOrder
                )
                .contextMenu(forSelectionType: PersistentIdentifier.self) { ids in
                    if ids.count == 1 {
                        Button("Bearbeiten …") { editingEntry = entry(for: ids.first) }
                        if let one = entry(for: ids.first), canResume(one) {
                            Button("Fortsetzen") { timer.resume(one) }
                        }
                    }
                    moveMenu(ids)
                    let groups = mergeGroups(for: ids)
                    Button(mergeTitle(ids: ids, groups: groups)) { pendingMerge = groups }
                        .disabled(groups.isEmpty)
                    Divider()
                    Button("Löschen", role: .destructive) { delete(ids) }
                } primaryAction: { ids in
                    editingEntry = entry(for: ids.first)
                }
                .onDeleteCommand { delete(selection) }
            }
        }
        .navigationTitle(title)
        .navigationSubtitle("Gesamt \(Fmt.hoursMinutes(total))")
        .toolbar {
            if let project = scopedProject, !project.isArchived {
                Button {
                    timer.isRunning(project) ? timer.stop() : timer.start(project)
                } label: {
                    Label(
                        timer.isRunning(project) ? String(localized: "Timer stoppen") : String(localized: "Timer starten"),
                        systemImage: timer.isRunning(project) ? "stop.fill" : "play.fill"
                    )
                }
                .help(timer.isRunning(project) ? String(localized: "Timer stoppen") : String(localized: "Timer für dieses Projekt starten"))
            }
            Button {
                creatingEntry = true
            } label: {
                Label("Zeit nachtragen", systemImage: "plus")
            }
            .help("Zeit nachtragen")
            Button {
                exportDocument = CSVDocument(entries: entries)
            } label: {
                Label("Als CSV exportieren", systemImage: "square.and.arrow.up")
            }
            .help("Diese Einträge als CSV exportieren")
            .disabled(entries.isEmpty)
        }
        .confirmationDialog(
            mergeQuestion,
            isPresented: Binding(get: { pendingMerge != nil }, set: { if !$0 { pendingMerge = nil } }),
            presenting: pendingMerge
        ) { groups in
            let worked = groups.joined().reduce(0) { $0 + $1.duration() }
            let spanned = groups.reduce(0) { sum, group in
                sum + ((group.compactMap(\.end).max() ?? .now).timeIntervalSince(group[0].start))
            }
            Button("Nur Arbeitszeit behalten (\(Fmt.hoursMinutes(worked)))") { merge(groups, includeBreaks: false) }
            Button("Von Beginn bis Ende, mit Pausen (\(Fmt.hoursMinutes(spanned)))") { merge(groups, includeBreaks: true) }
        } message: { _ in
            Text("Die zusammengeführte Zeile beginnt beim ersten Start. Pro Tag und Projekt bleibt eine Zeile, die Notizen werden untereinander übernommen.")
        }
        .sheet(item: $editingEntry) { EntryEditor(entry: $0, defaultProject: nil) }
        .sheet(isPresented: $creatingEntry) { EntryEditor(entry: nil, defaultProject: scopedProject) }
        .fileExporter(
            isPresented: Binding(get: { exportDocument != nil }, set: { if !$0 { exportDocument = nil } }),
            document: exportDocument,
            contentType: .commaSeparatedText,
            defaultFilename: "TOM \(title) \(Date.now.formatted(.iso8601.year().month().day()))"
        ) { _ in }
    }

    private func entry(for id: PersistentIdentifier?) -> TimeEntry? {
        allEntries.first { $0.persistentModelID == id }
    }

    // MARK: - Verschieben und Fortsetzen

    /// Einträge in ein anderes Projekt schieben, nach Ordnern gegliedert wie in der Seitenleiste.
    @ViewBuilder
    private func moveMenu(_ ids: Set<PersistentIdentifier>) -> some View {
        let active = projects.filter { !$0.isArchived }
        let current = Set(allEntries.filter { ids.contains($0.persistentModelID) }.compactMap { $0.project?.persistentModelID })
        Menu(ids.count == 1 ? String(localized: "In Projekt verschieben") : String(localized: "\(ids.count) Einträge verschieben nach")) {
            ForEach(folders) { folder in
                let children = active.filter { $0.folder?.persistentModelID == folder.persistentModelID }
                if !children.isEmpty {
                    Section(folder.name) {
                        ForEach(children) { project in
                            Button(project.name) { move(ids, to: project) }
                                .disabled(current == [project.persistentModelID])
                        }
                    }
                }
            }
            let loose = active.filter { $0.folder == nil }
            if !loose.isEmpty {
                Section {
                    ForEach(loose) { project in
                        Button(project.name) { move(ids, to: project) }
                            .disabled(current == [project.persistentModelID])
                    }
                }
            }
        }
    }

    private func move(_ ids: Set<PersistentIdentifier>, to project: Project) {
        for entry in allEntries where ids.contains(entry.persistentModelID) {
            entry.project = project
        }
        try? context.save()
    }

    /// Nur der zuletzt beendete Eintrag von heute lässt sich fortsetzen, die Zeit seit dem Stoppen zählt dann mit.
    private func canResume(_ entry: TimeEntry) -> Bool {
        guard let end = entry.end, Calendar.current.isDateInToday(end), timer.running == nil else { return false }
        return !allEntries.contains { ($0.end ?? .distantFuture) > end }
    }

    // MARK: - Zusammenführen

    private struct MergeKey: Hashable {
        let day: Date
        let project: PersistentIdentifier?
    }

    /// Einträge, die zu einer Zeile pro Tag und Projekt verschmelzen würden.
    /// Bei nur einer markierten Zeile zählen alle Einträge desselben Tages und Projekts dazu.
    private func mergeGroups(for ids: Set<PersistentIdentifier>) -> [[TimeEntry]] {
        let cal = Calendar.current
        let picked: [TimeEntry]
        if ids.count == 1, let one = entry(for: ids.first) {
            picked = entries.filter {
                cal.isDate($0.start, inSameDayAs: one.start) && $0.project?.persistentModelID == one.project?.persistentModelID
            }
        } else {
            picked = entries.filter { ids.contains($0.persistentModelID) }
        }
        // Laufende Timer bleiben unangetastet.
        return Dictionary(grouping: picked.filter { !$0.isRunning }) {
            MergeKey(day: cal.startOfDay(for: $0.start), project: $0.project?.persistentModelID)
        }
        .values
        .filter { $0.count > 1 }
        .map { $0.sorted { $0.start < $1.start } }
        .sorted { $0[0].start < $1[0].start }
    }

    private func mergeTitle(ids: Set<PersistentIdentifier>, groups: [[TimeEntry]]) -> String {
        if ids.count == 1, let day = groups.first?.first?.start {
            return String(localized: "Alle Zeilen vom \(Fmt.shortDate(day)) zusammenführen …")
        }
        return groups.count > 1 ? String(localized: "Pro Tag zusammenführen …") : String(localized: "Zusammenführen …")
    }

    private var mergeQuestion: String {
        let groups = pendingMerge ?? []
        let count = groups.joined().count
        return groups.count == 1
            ? String(localized: "\(count) Einträge zu einer Zeile zusammenführen?")
            : String(localized: "\(count) Einträge zu \(groups.count) Zeilen zusammenführen?")
    }

    private func merge(_ groups: [[TimeEntry]], includeBreaks: Bool) {
        for group in groups {
            guard let first = group.first else { continue }
            let worked = group.reduce(0) { $0 + $1.duration() }
            let lastEnd = group.compactMap(\.end).max() ?? first.start
            var seen = Set<String>()
            let notes = group
                .map { $0.note.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty && seen.insert($0).inserted }

            first.end = includeBreaks ? lastEnd : first.start.addingTimeInterval(worked)
            first.note = notes.joined(separator: "\n")
            first.tools = TimerController.combine(group.flatMap(\.tools))
            group.dropFirst().forEach(context.delete)
        }
        try? context.save()
        selection = Set(groups.compactMap { $0.first?.persistentModelID })
    }

    private func delete(_ ids: Set<PersistentIdentifier>) {
        for entry in allEntries where ids.contains(entry.persistentModelID) {
            context.delete(entry)
        }
        try? context.save()
        selection.subtract(ids)
    }
}

/// Tabelle im Stil von Tim: eine Zeile pro Eintrag, alle Spalten sortierbar.
private struct EntriesTable: View {
    @Environment(TimerController.self) private var timer
    @Environment(\.modelContext) private var context
    let entries: [TimeEntry]
    let showsProject: Bool
    let showsAmount: Bool
    @Binding var selection: Set<PersistentIdentifier>
    @Binding var sortOrder: [KeyPathComparator<TimeEntry>]

    var body: some View {
        Table(of: TimeEntry.self, selection: $selection, sortOrder: $sortOrder) {
            if showsProject {
                TableColumn("Projekt", value: \.projectName) { entry in
                    HStack(spacing: 7) {
                        ProjectIcon(project: entry.project, size: 11)
                        Text(entry.projectName).lineLimit(1)
                    }
                }
                .width(min: 110, ideal: 150, max: 240)
            }

            TableColumn("Startdatum", value: \.start) { entry in
                Text(Fmt.shortDate(entry.start))
            }
            .width(min: 66, ideal: 72, max: 90)

            TableColumn("Beginn", value: \.start) { entry in
                Text(Fmt.timeWithSeconds(entry.start))
            }
            .width(min: 60, ideal: 66, max: 84)

            TableColumn("Enddatum", value: \.endForSorting) { entry in
                Text(entry.end.map(Fmt.shortDate) ?? "")
            }
            .width(min: 66, ideal: 72, max: 90)

            TableColumn("Ende", value: \.endForSorting) { entry in
                if let end = entry.end {
                    Text(Fmt.timeWithSeconds(end))
                } else {
                    Text("läuft").foregroundStyle(entry.project?.color ?? .accentColor)
                }
            }
            .width(min: 60, ideal: 66, max: 84)

            TableColumn("Dauer", value: \.storedDuration) { entry in
                Text(Fmt.clock(entry.duration(now: timer.now), seconds: entry.isRunning, padHours: true))
                    .fontWeight(entry.isRunning ? .semibold : .regular)
                    .foregroundStyle(entry.isRunning ? (entry.project?.color ?? .accentColor) : .primary)
            }
            .width(min: 68, ideal: 74, max: 90)

            if showsAmount {
                TableColumn("Betrag", value: \.amountForSorting) { entry in
                    Text(entry.amount(now: timer.now).map(Fmt.money) ?? "")
                        .foregroundStyle(.secondary)
                }
                .width(min: 60, ideal: 76, max: 110)
            }

            TableColumn("Tools", value: \.toolsSortKey) { entry in
                ToolsMenu(tools: toolsBinding(for: entry))
            }
            .width(min: 60, ideal: 96, max: 180)

            TableColumn("Notiz", value: \.note) { entry in
                Text(Fmt.firstLine(entry.note))
                    .foregroundStyle(.secondary)
                    .help(entry.note)
            }
            .width(min: 140, ideal: 220)
        } rows: {
            // Zeilen lassen sich auf ein Projekt in der Seitenleiste ziehen.
            ForEach(entries) { entry in
                TableRow(entry).draggable(EntryDrag.payload(for: entry))
            }
        }
        .monospacedDigit()
    }

    /// Beim laufenden Eintrag zeigt die Spalte schon, was gerade erkannt wird.
    private func toolsBinding(for entry: TimeEntry) -> Binding<[ToolUsage]> {
        Binding(
            get: {
                guard entry.isRunning, timer.running?.persistentModelID == entry.persistentModelID else { return entry.tools }
                return TimerController.combine(entry.tools, timer.activity.tools)
            },
            set: { newValue in
                // Beim laufenden Eintrag nur die von Hand gewählten speichern, der Rest kommt beim Stoppen dazu.
                let detected = entry.isRunning ? Set(timer.activity.tools.map(\.name)) : []
                let stored = Set(entry.tools.map(\.name))
                entry.tools = newValue.filter { !detected.contains($0.name) || stored.contains($0.name) }
                try? context.save()
            }
        )
    }
}

private extension TimeEntry {
    var projectName: String { project?.name ?? String(localized: "Ohne Projekt") }
    var endForSorting: Date { end ?? .distantFuture }
    var toolsSortKey: String { tools.first?.name ?? "" }
    var storedDuration: TimeInterval { duration() }
    var amountForSorting: Double { amount(now: .now) ?? 0 }

    func amount(now: Date) -> Double? {
        project?.hourlyRate.map { $0 * duration(now: now) / 3600 }
    }
}

/// Einträge per Drag & Drop verschieben. Übertragen wird die ID als Text mit eigenem Präfix.
enum EntryDrag {
    private static let prefix = "tom-entry:"

    static func payload(for entry: TimeEntry) -> String {
        let data = (try? JSONEncoder().encode(entry.persistentModelID)) ?? Data()
        return prefix + data.base64EncodedString()
    }

    static func entries(from items: [String], in context: ModelContext) -> [TimeEntry] {
        items.compactMap { item in
            guard item.hasPrefix(prefix),
                  let data = Data(base64Encoded: String(item.dropFirst(prefix.count))),
                  let id = try? JSONDecoder().decode(PersistentIdentifier.self, from: data)
            else { return nil }
            return context.model(for: id) as? TimeEntry
        }
    }
}
