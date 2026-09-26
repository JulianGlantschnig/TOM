import SwiftData
import SwiftUI

@main
struct TimecounterApp: App {
    private let container: ModelContainer
    @State private var timer: TimerController

    init() {
        Prefs.registerDefaults()
        #if DEBUG
        let container = DemoData.isEnabled ? DemoData.makeContainer() : Persistence.makeContainer()
        if !DemoData.isEnabled { Persistence.seedIfNeeded(container.mainContext) }
        #else
        let container = Persistence.makeContainer()
        Persistence.seedIfNeeded(container.mainContext)
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

        Window("Timecounter", id: "main") {
            ContentView()
                .environment(timer)
                .modelContainer(container)
        }
        .defaultSize(width: 1120, height: 680)
        .defaultLaunchBehavior(.suppressed)

        Settings {
            SettingsView()
                .modelContainer(container)
        }

    }
}

/// Zeigt die aktive Laufzeit direkt in der Menüleiste.
struct MenuBarLabel: View {
    @Environment(TimerController.self) private var timer
    @AppStorage(Prefs.showSecondsInMenuBar) private var showSeconds = true

    var body: some View {
        if timer.running != nil {
            Text("\(Image(systemName: timer.running?.project?.iconName ?? "timer")) \(Fmt.clock(timer.elapsed, seconds: showSeconds))")
                .monospacedDigit()
        } else {
            Image(systemName: "timer")
        }
    }
}
