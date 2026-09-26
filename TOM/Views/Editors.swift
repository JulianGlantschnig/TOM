import SwiftData
import SwiftUI

/// Zeiteintrag bearbeiten oder nachtragen.
struct EntryEditor: View {
    let entry: TimeEntry?

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Query(filter: #Predicate<Project> { !$0.isArchived }, sort: \Project.sortIndex)
    private var projects: [Project]

    @State private var project: Project?
    @State private var start: Date
    @State private var end: Date
    @State private var note: String
    @State private var tools: [ToolUsage]

    init(entry: TimeEntry?, defaultProject: Project?) {
        self.entry = entry
        let now = Date.now
        _project = State(initialValue: entry?.project ?? defaultProject)
        _start = State(initialValue: entry?.start ?? now.addingTimeInterval(-3600))
        _end = State(initialValue: entry?.end ?? now)
        _note = State(initialValue: entry?.note ?? "")
        _tools = State(initialValue: entry?.tools ?? [])
    }

    private var isRunning: Bool { entry?.isRunning ?? false }
    private var isValid: Bool { project != nil && (isRunning || end > start) }

    var body: some View {
        VStack(spacing: 0) {
            Form {
                Picker("Projekt", selection: $project) {
                    if project == nil { Text("Projekt wählen").tag(Project?.none) }
                    ForEach(projects) { project in
                        Text(project.name).tag(Optional(project))
                    }
                    // Archivierte Projekte bleiben für bestehende Einträge wählbar.
                    if let current = entry?.project, current.isArchived {
                        Text("\(current.name) (archiviert)").tag(Optional(current))
                    }
                }
                DatePicker("Beginn", selection: $start)
                if isRunning {
                    LabeledContent("Ende", value: "Timer läuft noch")
                } else {
                    DatePicker("Ende", selection: $end)
                    LabeledContent("Dauer") {
                        Text(end > start ? Fmt.hoursMinutes(end.timeIntervalSince(start)) : "Ende liegt vor dem Beginn")
                            .foregroundStyle(end > start ? Color.primary : Color.red)
                    }
                }
                LabeledContent("Tools") {
                    ToolsMenu(tools: $tools, maxIcons: 8, showsEmptyLabel: true)
                }
                TextField("Notiz", text: $note, prompt: Text("z. B. Kapitel 3 überarbeitet"), axis: .vertical)
                    .lineLimit(3...6)
            }
            .formStyle(.grouped)

            HStack {
                Spacer()
                Button("Abbrechen", role: .cancel) { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button(entry == nil ? "Zeit hinzufügen" : "Änderungen sichern") { save() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(!isValid)
            }
            .padding()
        }
        .frame(width: 440)
        .navigationTitle(entry == nil ? "Zeit nachtragen" : "Eintrag bearbeiten")
    }

    private func save() {
        let target = entry ?? {
            let new = TimeEntry(start: start, project: project)
            context.insert(new)
            return new
        }()
        target.project = project
        target.start = start
        if !isRunning { target.end = end }
        target.note = note.trimmingCharacters(in: .whitespacesAndNewlines)
        target.tools = tools
        try? context.save()
        dismiss()
    }
}

/// Projekt anlegen oder bearbeiten.
struct ProjectEditor: View {
    let project: Project?

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Query private var allProjects: [Project]
    @Query(sort: \Folder.sortIndex) private var folders: [Folder]
    @AppStorage(Prefs.currency) private var currency = "€"

    @State private var name: String
    @State private var colorHex: String
    @State private var iconName: String?
    @State private var ignoresIdle: Bool
    @State private var hourlyRate: Double?
    @State private var folder: Folder?

    init(project: Project?, folder: Folder? = nil) {
        self.project = project
        _folder = State(initialValue: project?.folder ?? folder)
        _name = State(initialValue: project?.name ?? "")
        _colorHex = State(initialValue: project?.colorHex ?? ProjectPalette.colors[0].hex)
        _iconName = State(initialValue: project?.iconName)
        _ignoresIdle = State(initialValue: project?.ignoresIdle ?? false)
        _hourlyRate = State(initialValue: project?.hourlyRate)
    }

    var body: some View {
        VStack(spacing: 0) {
            Form {
                TextField("Name", text: $name, prompt: Text("z. B. Literaturrecherche"))
                LabeledContent("Farbe") {
                    ColorSwatchPicker(selection: $colorHex)
                }
                LabeledContent("Symbol") {
                    IconPicker(selection: $iconName, color: Color(hex: colorHex))
                }
                Picker("Ordner", selection: $folder) {
                    Text("Kein Ordner").tag(Folder?.none)
                    ForEach(folders) { folder in
                        Text(folder.name).tag(Optional(folder))
                    }
                }
                TextField("Stundensatz", value: $hourlyRate, format: .number, prompt: Text("optional, in \(currency)"))
                Toggle(isOn: Binding(get: { !ignoresIdle }, set: { ignoresIdle = !$0 })) {
                    Text("Nachfragen, wenn ich weg war")
                    Text("Ausschalten für Arbeit abseits des Macs, z. B. Unterricht oder Dreharbeiten.")
                }
            }
            .formStyle(.grouped)

            HStack {
                Spacer()
                Button("Abbrechen", role: .cancel) { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button(project == nil ? "Projekt anlegen" : "Änderungen sichern") { save() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            .padding()
        }
        .frame(width: 480)
    }

    private func save() {
        let target = project ?? {
            let index = (allProjects.map(\.sortIndex).max() ?? -1) + 1
            let new = Project(name: "", colorHex: colorHex, sortIndex: index)
            context.insert(new)
            return new
        }()
        target.name = name.trimmingCharacters(in: .whitespaces)
        target.colorHex = colorHex
        target.iconName = iconName
        target.ignoresIdle = ignoresIdle
        target.hourlyRate = hourlyRate.flatMap { $0 > 0 ? $0 : nil }
        target.folder = folder
        folder?.isExpanded = true
        try? context.save()
        dismiss()
    }
}

/// Ordner anlegen oder umbenennen.
struct FolderEditor: View {
    let folder: Folder?

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Query private var allFolders: [Folder]

    @State private var name: String
    @State private var colorHex: String

    init(folder: Folder?) {
        self.folder = folder
        _name = State(initialValue: folder?.name ?? "")
        _colorHex = State(initialValue: folder?.colorHex ?? ProjectPalette.colors[2].hex)
    }

    var body: some View {
        VStack(spacing: 0) {
            Form {
                TextField("Name", text: $name, prompt: Text("z. B. Diplomarbeit"))
                LabeledContent("Farbe") {
                    ColorSwatchPicker(selection: $colorHex)
                }
            }
            .formStyle(.grouped)

            HStack {
                Spacer()
                Button("Abbrechen", role: .cancel) { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button(folder == nil ? "Ordner anlegen" : "Änderungen sichern") { save() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            .padding()
        }
        .frame(width: 440)
    }

    private func save() {
        let target = folder ?? {
            let new = Folder(name: "", colorHex: colorHex, sortIndex: (allFolders.map(\.sortIndex).max() ?? -1) + 1)
            context.insert(new)
            return new
        }()
        target.name = name.trimmingCharacters(in: .whitespaces)
        target.colorHex = colorHex
        try? context.save()
        dismiss()
    }
}

struct ColorSwatchPicker: View {
    @Binding var selection: String

    var body: some View {
        HStack(spacing: 8) {
            ForEach(ProjectPalette.colors) { swatch in
                Button {
                    selection = swatch.hex
                } label: {
                    Circle()
                        .fill(Color(hex: swatch.hex))
                        .frame(width: 20, height: 20)
                        .overlay {
                            if swatch.hex == selection {
                                Circle().strokeBorder(.background, lineWidth: 2.5)
                                Circle().strokeBorder(Color(hex: swatch.hex), lineWidth: 1).padding(-3)
                            }
                        }
                }
                .buttonStyle(.plain)
                .help(swatch.name)
                .accessibilityLabel(swatch.name)
            }
        }
    }
}

/// Raster mit SF Symbols, das erste Feld steht für „kein Symbol“ (nur Farbpunkt).
struct IconPicker: View {
    @Binding var selection: String?
    let color: Color

    private let columns = Array(repeating: GridItem(.fixed(26), spacing: 4), count: 9)

    var body: some View {
        LazyVGrid(columns: columns, spacing: 4) {
            cell(nil) {
                Circle().fill(color).frame(width: 9, height: 9)
            }
            .help("Kein Symbol, nur Farbpunkt")
            ForEach(ProjectIcons.all, id: \.self) { name in
                cell(name) {
                    Image(systemName: name).font(.system(size: 13, weight: .medium))
                }
            }
        }
    }

    private func cell(_ name: String?, @ViewBuilder content: () -> some View) -> some View {
        let isSelected = selection == name
        return Button {
            selection = name
        } label: {
            content()
                .foregroundStyle(isSelected ? color : .secondary)
                .frame(width: 26, height: 26)
                .background(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(isSelected ? color.opacity(0.16) : .clear)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .strokeBorder(isSelected ? color.opacity(0.7) : .clear, lineWidth: 1)
                )
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(name ?? "Kein Symbol")
    }
}
