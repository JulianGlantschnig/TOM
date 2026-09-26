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

    private var activeProjects: [Project] { projects.filter { !$0.isArchived } }
    private var looseProjects: [Project] { activeProjects.filter { $0.folder == nil } }
    private var archivedProjects: [Project] { projects.filter(\.isArchived) }

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
                    ForEach(folders) { folder in
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
                if !archivedProjects.isEmpty {
                    Section("Archiv") {
                        ForEach(archivedProjects) { project in
                            projectRow(project)
                        }
                    }
                }
            }
            .navigationSplitViewColumnWidth(min: 210, ideal: 250)
            .safeAreaInset(edge: .bottom) {
                Menu {
                    Button("Neues Projekt") { newProjectFolder = .some(nil) }
                    Button("Neuer Ordner") { creatingFolder = true }
                } label: {
                    Label("Neu", systemImage: "plus")
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
                .frame(maxWidth: .infinity, alignment: .leading)
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
                // Das echte Einstellungsfenster, nur dort zeigt SwiftUI die Tabs in der Titelleiste.
                if UserDefaults.standard.string(forKey: "demoSettingsTab") != nil { openSettings() }
                return
            }
            #endif
            NSApp.setActivationPolicy(.regular)
            NSApp.activate(ignoringOtherApps: true)
        }
        .onDisappear {
            NSApp.setActivationPolicy(.accessory)
        }
    }

    // MARK: - Zeilen

    private func folderRow(_ folder: Folder) -> some View {
        let total = activeProjects(in: folder).flatMap(\.entries).reduce(0) { $0 + $1.duration() }
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
        .tag(SidebarItem.project(project))
        .contextMenu {
            Button(timer.isRunning(project) ? "Timer stoppen" : "Timer starten") {
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
            Button(project.isArchived ? "Aus dem Archiv holen" : "Archivieren") {
                if timer.isRunning(project) { timer.stop() }
                project.isArchived.toggle()
                try? context.save()
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
