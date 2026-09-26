#if DEBUG
import Foundation
import SwiftData
import SwiftUI

/// Start mit `-demo`: Beispieldaten nur im Arbeitsspeicher, echte Daten bleiben unberührt.
enum DemoData {
    static var isEnabled: Bool { CommandLine.arguments.contains("-demo") }

    /// Öffnet Hauptfenster und Popover-Inhalt als normale Fenster, damit man sie ansehen kann.
    @MainActor
    static func presentWindows(timer: TimerController, container: ModelContainer) {
        func show(_ view: some View, title: String, size: CGSize) {
            let window = NSWindow(
                contentRect: CGRect(origin: .zero, size: size),
                styleMask: [.titled, .closable, .resizable, .fullSizeContentView],
                backing: .buffered, defer: false
            )
            window.title = title
            window.isReleasedWhenClosed = false
            window.contentView = NSHostingView(rootView: view.environment(timer).modelContainer(container))
            window.center()
            window.orderFrontRegardless()
            windows.append(window)
        }
        show(ContentView(), title: "Timecounter", size: CGSize(width: 1120, height: 680))
        show(MenuBarView(), title: "Popover-Vorschau", size: CGSize(width: 320, height: 380))
        if UserDefaults.standard.string(forKey: "demoPage") == "editor",
           let project = try? container.mainContext.fetch(FetchDescriptor<Project>(sortBy: [SortDescriptor(\.sortIndex)])).first {
            show(ProjectEditor(project: project), title: "Projekt bearbeiten", size: CGSize(width: 480, height: 520))
        }
    }

    @MainActor private static var windows: [NSWindow] = []

    @MainActor
    static func makeContainer() -> ModelContainer {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try! ModelContainer(for: Folder.self, Project.self, TimeEntry.self, configurations: config)
        let context = container.mainContext

        let names = ["Recherche & Literatur", "Schreiben", "Analyse & Auswertung", "Betreuung & Besprechungen"]
        let projects = names.enumerated().map { index, name in
            Project(name: name, colorHex: ProjectPalette.colors[index].hex, sortIndex: index)
        }
        projects[3].hourlyRate = 45
        for (project, icon) in zip(projects, ["books.vertical", "square.and.pencil", "chart.pie", nil]) {
            project.iconName = icon
        }
        projects.forEach(context.insert)
        let thesis = Folder(name: "Diplomarbeit", colorHex: ProjectPalette.colors[2].hex)
        context.insert(thesis)
        projects[0...2].forEach { $0.folder = thesis }

        let notes = ["Kapitel 2 gegliedert", "Quellen zu Methodik gesichtet", "Interviews transkribiert", "", "Feedback eingearbeitet", "Diagramme erstellt"]
        let cal = Calendar.current
        var generator = SystemRandomNumberGenerator()
        for dayOffset in 1..<40 {
            let day = cal.date(byAdding: .day, value: -dayOffset, to: cal.startOfDay(for: .now))!
            if cal.isDateInWeekend(day) && dayOffset % 3 != 0 { continue }
            var cursor = cal.date(bySettingHour: 8 + Int.random(in: 0...2, using: &generator), minute: 15, second: 0, of: day)!
            for _ in 0..<Int.random(in: 2...4, using: &generator) {
                let length = TimeInterval(Int.random(in: 35...150, using: &generator) * 60)
                let entry = TimeEntry(
                    start: cursor,
                    end: cursor.addingTimeInterval(length),
                    note: notes.randomElement(using: &generator)!,
                    project: projects.randomElement(using: &generator)!
                )
                context.insert(entry)
                cursor = cursor.addingTimeInterval(length + 20 * 60)
            }
        }
        let morning = Date.now.addingTimeInterval(-3 * 3600)
        context.insert(TimeEntry(start: morning, end: morning.addingTimeInterval(5400), note: "Literaturliste ergänzt", project: projects[0]))
        context.insert(TimeEntry(start: Date.now.addingTimeInterval(-2843), note: ActivityTracker.isEnabled ? "" : "Kapitel 3: Methodik", project: projects[1]))
        try? context.save()
        return container
    }
}
#endif
