import SwiftData
import SwiftUI

@main
struct TOMApp: App {
    private let container: ModelContainer
    @State private var timer: TimerController

    init() {
        Prefs.registerDefaults()
        #if DEBUG
        if !DemoData.isEnabled { Persistence.backupIfNewVersion() }
        let container = DemoData.isEnabled ? DemoData.makeContainer() : Persistence.makeContainer()
        #else
        Persistence.backupIfNewVersion()
        let container = Persistence.makeContainer()
        #endif
        self.container = container
        if CommandLine.arguments.contains("-importTim") {
            do {
                print("Tim-Import:", try TimImporter.run(context: container.mainContext).description)
            } catch {
                print("Tim-Import fehlgeschlagen:", error.localizedDescription)
            }
        }
        let timer = TimerController(context: container.mainContext)
        _timer = State(initialValue: timer)
        #if DEBUG
        if DemoData.isEnabled {
            DispatchQueue.main.async { DemoData.presentWindows(timer: timer, container: container) }
        }
        #endif
    }

    var body: some Scene {
        MenuBarExtra {
            MenuBarView()
                .environment(timer)
                .modelContainer(container)
        } label: {
            MenuBarLabel()
                .environment(timer)
        }
        .menuBarExtraStyle(.window)

        Window("TOM", id: "main") {
            ContentView()
                .environment(timer)
                .modelContainer(container)
        }
        .defaultSize(width: 1120, height: 680)
        .defaultLaunchBehavior(.suppressed)

        // Projekt-Einstellungen direkt aus dem Menü heraus, ohne erst die Übersicht zu öffnen.
        WindowGroup("Projekt bearbeiten", id: "project-editor", for: PersistentIdentifier.self) { $id in
            ProjectEditorWindow(id: id)
                .environment(timer)
                .modelContainer(container)
        }
        .windowResizability(.contentSize)
        .defaultLaunchBehavior(.suppressed)
        .restorationBehavior(.disabled)

        Settings {
            SettingsView()
                .modelContainer(container)
        }

    }
}

/// Zeigt die aktive Laufzeit direkt in der Menüleiste, in der gewählten Variante.
struct MenuBarLabel: View {
    @Environment(TimerController.self) private var timer
    @AppStorage(Prefs.menuBarStyle) private var style: MenuBarStyle = .iconMinutes

    var body: some View {
        if timer.running != nil, style.showsTime {
            let clock = Fmt.clock(timer.elapsed, seconds: style.showsSeconds)
            if style.showsIcon {
                Text("\(Image(systemName: timer.running?.project?.iconName ?? "timer")) \(clock)")
                    .monospacedDigit()
            } else {
                Text(clock).monospacedDigit()
            }
        } else {
            Image(systemName: timer.running?.project?.iconName ?? "timer")
        }
    }
}

private struct ProjectEditorWindow: View {
    let id: PersistentIdentifier?
    @Environment(\.modelContext) private var context

    var body: some View {
        if let id, let project = context.model(for: id) as? Project {
            ProjectEditor(project: project)
        }
    }
}
