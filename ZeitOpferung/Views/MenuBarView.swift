import SwiftData
import SwiftUI

struct MenuBarView: View {
    @Environment(TimerController.self) private var timer

    var body: some View {
        let today = Calendar.current.startOfDay(for: timer.now)
        MenuContent(dayStart: today)
            .id(today)
            .frame(width: 320)
    }
}

private struct MenuContent: View {
    @Environment(TimerController.self) private var timer
    @Environment(\.modelContext) private var context
    @Environment(\.openWindow) private var openWindow
    @Environment(\.openSettings) private var openSettings

    @Query(filter: #Predicate<Project> { !$0.isArchived }, sort: \Project.sortIndex)
    private var projects: [Project]
    @Query(sort: \Folder.sortIndex) private var folders: [Folder]
    @Query private var todayEntries: [TimeEntry]

    @State private var newProjectName = ""

    init(dayStart: Date) {
        _todayEntries = Query(filter: #Predicate<TimeEntry> { $0.start >= dayStart })
    }

    private var todayTotal: TimeInterval {
        todayEntries.reduce(0) { $0 + $1.duration(now: timer.now) }
    }

    private func todayTotal(for project: Project) -> TimeInterval {
        todayEntries
            .filter { $0.project?.persistentModelID == project.persistentModelID }
            .reduce(0) { $0 + $1.duration(now: timer.now) }
    }

    var body: some View {
        VStack(spacing: 0) {
            Group {
                if let entry = timer.running {
                    RunningCard(entry: entry)
                } else {
                    IdleCard(todayTotal: todayTotal)
                }
            }
            .padding(16)

            Divider()

            ScrollView {
                VStack(spacing: 2) {
                    ForEach(folders) { folder in
                        let children = projects.filter { $0.folder?.persistentModelID == folder.persistentModelID }
                        if !children.isEmpty {
                            FolderHeader(folder: folder, today: children.reduce(0) { $0 + todayTotal(for: $1) })
                            ForEach(children) { project in
                                ProjectRow(project: project, today: todayTotal(for: project), indent: 14)
                            }
                        }
                    }
                    ForEach(projects.filter { $0.folder == nil }) { project in
                        ProjectRow(project: project, today: todayTotal(for: project))
                    }
                    TextField("Neues Projekt …", text: $newProjectName)
                        .textFieldStyle(.plain)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 7)
                        .onSubmit(addProject)
                }
                .padding(6)
            }
            .frame(maxHeight: 300)
            .fixedSize(horizontal: false, vertical: true)

            Divider()

            HStack(spacing: 14) {
                Button("Übersicht öffnen") {
                    openWindow(id: "main")
                    NSApp.activate(ignoringOtherApps: true)
                }
                Spacer()
                Button {
                    openSettings()
                    NSApp.activate(ignoringOtherApps: true)
                } label: {
                    Image(systemName: "gearshape")
                }
                .help("Einstellungen")
                Button {
                    NSApp.terminate(nil)
                } label: {
                    Image(systemName: "power")
                }
                .help("ZeitOpferung beenden")
            }
            .buttonStyle(.borderless)
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
        }
    }

    private func addProject() {
        let name = newProjectName.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else { return }
        let index = (projects.map(\.sortIndex).max() ?? -1) + 1
        let color = ProjectPalette.colors[index % ProjectPalette.colors.count].hex
        context.insert(Project(name: name, colorHex: color, sortIndex: index))
        try? context.save()
        newProjectName = ""
    }
}

/// Die laufende Zeit ist das eine laute Element der App: groß, in Projektfarbe.
private struct RunningCard: View {
    @Environment(TimerController.self) private var timer
    @AppStorage(Prefs.detectActivity) private var detectActivity = true
    @Bindable var entry: TimeEntry

    var body: some View {
        let color = entry.project?.color ?? .secondary
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                ProjectIcon(project: entry.project, size: 12)
                Text(entry.project?.name ?? "Ohne Projekt")
                    .font(.subheadline.weight(.medium))
                    .lineLimit(1)
                Spacer()
                Text("seit \(Fmt.time(entry.start))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            HStack(alignment: .center) {
                Text(Fmt.clock(timer.elapsed))
                    .font(.system(size: 42, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(color)
                    .contentTransition(.numericText())
                Spacer()
                Button {
                    timer.stop()
                } label: {
                    Image(systemName: "stop.fill")
                        .font(.system(size: 15, weight: .bold))
                        .frame(width: 40, height: 40)
                        .background(color.opacity(0.15), in: Circle())
                        .foregroundStyle(color)
                }
                .buttonStyle(.plain)
                .help("Timer stoppen (⌃⌥T)")
            }

            TextField("Woran arbeitest du gerade?", text: $entry.note, axis: .vertical)
                .textFieldStyle(.plain)
                .lineLimit(1...3)
                .font(.callout)

            if detectActivity, entry.note.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                ActivityHint(activity: timer.activity) { entry.note = $0 }
            }
        }
    }
}

/// Zeigt, was gerade erkannt wird. Der Vorschlag lässt sich übernehmen und danach frei umschreiben.
private struct ActivityHint: View {
    let activity: ActivityTracker
    let apply: (String) -> Void

    var body: some View {
        let names = activity.topAppNames
        HStack(spacing: 6) {
            Image(systemName: "eye")
            Text(names.isEmpty ? "Erkennt, woran du arbeitest …" : "Erkannt: " + names.joined(separator: ", "))
                .lineLimit(1)
                .truncationMode(.tail)
            Spacer(minLength: 6)
            if !names.isEmpty {
                Button("Als Notiz übernehmen") { apply(activity.suggestion) }
                    .buttonStyle(.link)
                    .foregroundStyle(.tint)
                    .fixedSize()
            }
        }
        .font(.caption)
        .foregroundStyle(.secondary)
        .help(names.isEmpty
            ? "Beim Stoppen wird daraus eine Notiz, falls du selbst nichts schreibst."
            : "Vorschlag:\n\(activity.suggestion)\n\nWird beim Stoppen automatisch eingetragen, falls du selbst nichts schreibst.")
    }
}

private struct IdleCard: View {
    let todayTotal: TimeInterval

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Heute erfasst")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Text(Fmt.hoursMinutes(todayTotal))
                .font(.system(size: 30, weight: .semibold, design: .rounded))
                .monospacedDigit()
            Text("Klick auf ein Projekt startet den Timer. ⌃⌥T geht von überall.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct FolderHeader: View {
    let folder: Folder
    let today: TimeInterval

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "folder.fill")
                .foregroundStyle(folder.color)
            Text(folder.name)
                .fontWeight(.medium)
                .lineLimit(1)
            Spacer()
            if today > 0 {
                Text(Fmt.clock(today, seconds: false))
                    .monospacedDigit()
            }
            Color.clear.frame(width: 14)
        }
        .font(.callout)
        .foregroundStyle(.secondary)
        .padding(.horizontal, 10)
        .padding(.top, 8)
        .padding(.bottom, 2)
    }
}

private struct ProjectRow: View {
    @Environment(TimerController.self) private var timer
    let project: Project
    let today: TimeInterval
    var indent: CGFloat = 0
    @State private var isHovering = false

    var body: some View {
        let running = timer.isRunning(project)
        Button {
            running ? timer.stop() : timer.start(project)
        } label: {
            HStack(spacing: 10) {
                ProjectIcon(project: project, size: 13)
                Text(project.name)
                    .lineLimit(1)
                    .fontWeight(running ? .semibold : .regular)
                Spacer()
                if today > 0 {
                    Text(Fmt.clock(today, seconds: false))
                        .font(.callout)
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                }
                Image(systemName: running ? "stop.fill" : "play.fill")
                    .font(.caption)
                    .foregroundStyle(running ? project.color : .secondary)
                    .opacity(running || isHovering ? 1 : 0)
                    .frame(width: 14)
            }
            .padding(.leading, indent)
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .contentShape(Rectangle())
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(running ? project.color.opacity(0.12) : (isHovering ? Color.primary.opacity(0.06) : .clear))
            )
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
    }
}
