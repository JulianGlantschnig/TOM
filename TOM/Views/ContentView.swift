import SwiftData
import SwiftUI

enum SidebarItem: Hashable {
    case today, week, all, stats
    case folder(Folder)
    case project(Project)
}

struct ContentView: View {
    @Environment(\.modelContext) private var context
    @Environment(TimerController.self) private var timer
    @Environment(\.openSettings) private var openSettings
    @Query(sort: \Project.sortIndex) private var projects: [Project]
    @Query(sort: \Folder.sortIndex) private var folders: [Folder]

    @State private var selection: SidebarItem? = {
        #if DEBUG
        switch UserDefaults.standard.string(forKey: "demoPage") {
        case "stats": return .stats
        case "all": return .all
        default: break
        }
        #endif
        return .today
    }()
    @State private var editingProject: Project?
    @State private var newProjectFolder: Folder??
    @State private var deletingProject: Project?
    @State private var editingFolder: Folder?
    @State private var creatingFolder = false
    @State private var deletingFolder: Folder?
    @State private var dropTarget: PersistentIdentifier?
    @AppStorage("archiveExpanded") private var archiveExpanded = false

    private var activeProjects: [Project] { projects.filter { !$0.isArchived } }
    private var looseProjects: [Project] { activeProjects.filter { $0.folder == nil } }
    private var activeFolders: [Folder] { folders.filter { !$0.isArchived } }
    private var archivedFolders: [Folder] { folders.filter(\.isArchived) }
    /// Archivierte Projekte, die nicht schon mit ihrem ganzen Ordner im Archiv stehen.
    private var archivedProjects: [Project] { projects.filter { $0.isArchived && !($0.folder?.isArchived ?? false) } }

    private func activeProjects(in folder: Folder) -> [Project] {
        activeProjects.filter { $0.folder?.persistentModelID == folder.persistentModelID }
    }

    var body: some View {
        NavigationSplitView {
            List(selection: $selection) {
                Section("Zeiten") {
                    Label("Heute", systemImage: "sun.max").tag(SidebarItem.today)
                    Label("Diese Woche", systemImage: "calendar").tag(SidebarItem.week)
                    Label("Alle Einträge", systemImage: "list.bullet").tag(SidebarItem.all)
                    Label("Auswertung", systemImage: "chart.bar.xaxis").tag(SidebarItem.stats)
                }
                Section("Projekte") {
                    ForEach(activeFolders) { folder in
                        DisclosureGroup(isExpanded: Binding(
                            get: { folder.isExpanded },
                            set: { folder.isExpanded = $0 }
                        )) {
                            let children = activeProjects(in: folder)
                            ForEach(children) { project in
                                projectRow(project)
                            }
                            .onMove { reorder(children, from: $0, to: $1) }
                        } label: {
                            folderRow(folder)
                        }
                    }
                    ForEach(looseProjects) { project in
                        projectRow(project)
                    }
                    .onMove { reorder(looseProjects, from: $0, to: $1) }
                }
                if !archivedProjects.isEmpty || !archivedFolders.isEmpty {
                    // Standardmäßig zugeklappt, damit alte Projekte nicht im Weg sind.
                    Section(isExpanded: $archiveExpanded) {
                        ForEach(archivedFolders) { folder in
                            DisclosureGroup {
                                ForEach(projects.filter { $0.folder?.persistentModelID == folder.persistentModelID }) { project in
                                    projectRow(project)
                                }
                            } label: {
                                folderRow(folder)
                            }
                        }
                        ForEach(archivedProjects) { project in
                            projectRow(project)
                        }
                    } header: {
                        Text("Archiv (\(archivedFolders.count + archivedProjects.count))")
                    }
                }
            }
            .navigationSplitViewColumnWidth(min: 210, ideal: 250)
            .safeAreaInset(edge: .bottom) {
                HStack {
                    Menu {
                        Button("Neues Projekt") { newProjectFolder = .some(nil) }
                        Button("Neuer Ordner") { creatingFolder = true }
                    } label: {
                        Label("Neu", systemImage: "plus")
                    }
                    .menuStyle(.borderlessButton)
                    .fixedSize()
                    Spacer()
                    Button {
                        openSettings()
                    } label: {
                        Image(systemName: "gearshape")
                            .font(.system(size: 13))
                    }
                    .buttonStyle(.borderless)
                    .help("Einstellungen (⌘,)")
                    .accessibilityLabel("Einstellungen")
                }
                .padding(12)
            }
        } detail: {
            switch selection {
            case .today: EntriesView(scope: .today)
            case .week: EntriesView(scope: .week)
            case .all, .none: EntriesView(scope: .all)
            case .stats: StatsView()
            case .folder(let folder): ScopeDetailView(scope: .folder(folder)).id(selection)
            case .project(let project): ScopeDetailView(scope: .project(project)).id(selection)
            }
        }
        .frame(minWidth: 860, minHeight: 560)
        .sheet(item: $editingProject) { ProjectEditor(project: $0) }
        .sheet(isPresented: Binding(get: { newProjectFolder != nil }, set: { if !$0 { newProjectFolder = nil } })) {
            ProjectEditor(project: nil, folder: newProjectFolder ?? nil)
        }
        .sheet(item: $editingFolder) { FolderEditor(folder: $0) }
        .sheet(isPresented: $creatingFolder) { FolderEditor(folder: nil) }
        .confirmationDialog(
            "„\(deletingProject?.name ?? "")“ löschen?",
            isPresented: Binding(get: { deletingProject != nil }, set: { if !$0 { deletingProject = nil } }),
            presenting: deletingProject
        ) { project in
            Button("Projekt und alle Einträge löschen", role: .destructive) { delete(project) }
        } message: { project in
            Text("\(project.entries.count) Einträge gehen dabei verloren. Wenn du die Zeiten behalten willst, archiviere das Projekt stattdessen.")
        }
        .confirmationDialog(
            "Ordner „\(deletingFolder?.name ?? "")“ löschen?",
            isPresented: Binding(get: { deletingFolder != nil }, set: { if !$0 { deletingFolder = nil } }),
            presenting: deletingFolder
        ) { folder in
            Button("Ordner löschen", role: .destructive) { delete(folder) }
        } message: { _ in
            Text("Die Projekte darin und ihre Zeiten bleiben erhalten, sie stehen danach ohne Ordner in der Liste.")
        }
        .onAppear {
            #if DEBUG
            // Demo-Fenster sollen beim Anschauen keine Tastatureingaben abfangen.
            if DemoData.isEnabled {
                if UserDefaults.standard.string(forKey: "demoPage") == "folder" { selection = folders.first.map { .folder($0) } }
                if UserDefaults.standard.string(forKey: "demoPage") == "budget" { selection = projects.first { $0.budgetHours != nil }.map { .project($0) } }
                // Das echte Einstellungsfenster, nur dort zeigt SwiftUI die Tabs in der Titelleiste.
                if UserDefaults.standard.string(forKey: "demoSettingsTab") != nil { openSettings() }
                return
            }
            #endif
            DockIcon.windowIsOpen = true
            DockIcon.update()
        }
        .onDisappear {
            DockIcon.windowIsOpen = false
            DockIcon.update()
        }
    }

    // MARK: - Zeilen

    private func folderRow(_ folder: Folder) -> some View {
        let shown = folder.isArchived ? folder.projects : activeProjects(in: folder)
        let total = shown.flatMap(\.entries).reduce(0) { $0 + $1.duration() }
        return HStack(spacing: 8) {
            Image(systemName: "folder.fill")
                .foregroundStyle(folder.color)
            Text(folder.name).lineLimit(1)
            Spacer()
            Text(Fmt.clock(total, seconds: false))
                .font(.callout)
                .monospacedDigit()
                .foregroundStyle(.secondary)
        }
        .tag(SidebarItem.folder(folder))
        .contextMenu {
            Button("Neues Projekt in diesem Ordner …") { newProjectFolder = .some(folder) }
            Button("Ordner bearbeiten …") { editingFolder = folder }
            Button(folder.isArchived ? String(localized: "Ordner aus dem Archiv holen") : String(localized: "Ordner archivieren")) {
                setArchived(folder.projects, !folder.isArchived)
            }
            .disabled(folder.projects.isEmpty)
            Divider()
            Button("Ordner löschen …", role: .destructive) { deletingFolder = folder }
        }
    }

    private func projectRow(_ project: Project) -> some View {
        HStack(spacing: 8) {
            ProjectIcon(project: project, size: 12)
            Text(project.name).lineLimit(1)
            Spacer()
            if timer.isRunning(project) {
                Image(systemName: "timer")
                    .foregroundStyle(project.color)
            }
        }
        .overlay {
            if dropTarget == project.persistentModelID {
                RoundedRectangle(cornerRadius: 5)
                    .strokeBorder(project.color, lineWidth: 1.5)
                    .padding(-3)
            }
        }
        .tag(SidebarItem.project(project))
        // Einträge aus der Tabelle hierher ziehen, um sie in dieses Projekt zu verschieben.
        .dropDestination(for: String.self) { items, _ in
            let moved = EntryDrag.entries(from: items, in: context)
            guard !moved.isEmpty, !project.isArchived else { return false }
            for entry in moved { entry.project = project }
            try? context.save()
            return true
        } isTargeted: { targeted in
            if targeted {
                dropTarget = project.persistentModelID
            } else if dropTarget == project.persistentModelID {
                dropTarget = nil
            }
        }
        .contextMenu {
            Button(timer.isRunning(project) ? String(localized: "Timer stoppen") : String(localized: "Timer starten")) {
                timer.isRunning(project) ? timer.stop() : timer.start(project)
            }
            Divider()
            Button("Bearbeiten …") { editingProject = project }
            Menu("In Ordner verschieben") {
                ForEach(folders) { folder in
                    Button(folder.name) { move(project, to: folder) }
                        .disabled(project.folder?.persistentModelID == folder.persistentModelID)
                }
                if !folders.isEmpty { Divider() }
                Button("Ohne Ordner") { move(project, to: nil) }
                    .disabled(project.folder == nil)
            }
            Button(project.isArchived ? String(localized: "Aus dem Archiv holen") : String(localized: "Archivieren")) {
                setArchived([project], !project.isArchived)
            }
            Divider()
            Button("Löschen …", role: .destructive) { deletingProject = project }
        }
    }

    // MARK: - Aktionen

    private func reorder(_ list: [Project], from source: IndexSet, to destination: Int) {
        var ordered = list
        ordered.move(fromOffsets: source, toOffset: destination)
        for (index, project) in ordered.enumerated() { project.sortIndex = index }
        try? context.save()
    }

    private func setArchived(_ list: [Project], _ archived: Bool) {
        for project in list {
            if archived, timer.isRunning(project) { timer.stop() }
            project.isArchived = archived
        }
        try? context.save()
    }

    private func move(_ project: Project, to folder: Folder?) {
        project.folder = folder
        folder?.isExpanded = true
        try? context.save()
    }

    private func delete(_ project: Project) {
        if timer.isRunning(project) { timer.stop() }
        if selection == .project(project) { selection = .today }
        context.delete(project)
        try? context.save()
    }

    private func delete(_ folder: Folder) {
        if selection == .folder(folder) { selection = .today }
        for project in folder.projects { project.folder = nil }
        context.delete(folder)
        try? context.save()
    }
}
