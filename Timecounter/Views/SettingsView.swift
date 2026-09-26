import ServiceManagement
import SwiftUI

struct SettingsView: View {
    @AppStorage(Prefs.idleMinutes) private var idleMinutes = 10
    @AppStorage(Prefs.showSecondsInMenuBar) private var showSeconds = true
    @AppStorage(Prefs.roundingMinutes) private var roundingMinutes = 0
    @AppStorage(Prefs.currency) private var currency = "€"
    @AppStorage(Prefs.detectActivity) private var detectActivity = true
    @AppStorage(Prefs.readWindowTitles) private var readWindowTitles = false
    @State private var hasTitleAccess = ActivityTracker.hasTitleAccess
    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled
    @State private var loginError: String?
    @State private var importResult: String?
    @Environment(\.modelContext) private var context

    var body: some View {
        Form {
            Section {
                Toggle("Beim Anmelden automatisch starten", isOn: $launchAtLogin)
                    .onChange(of: launchAtLogin) { _, enabled in
                        do {
                            if enabled {
                                try SMAppService.mainApp.register()
                            } else {
                                try SMAppService.mainApp.unregister()
                            }
                            loginError = nil
                        } catch {
                            loginError = "Das hat nicht geklappt: \(error.localizedDescription)"
                        }
                    }
                if let loginError {
                    Text(loginError).font(.caption).foregroundStyle(.red)
                }
                Toggle("Sekunden in der Menüleiste zeigen", isOn: $showSeconds)
                LabeledContent("Timer starten oder stoppen", value: "⌃⌥T")
            }

            Section {
                Picker("Nachfragen, wenn ich weg war", selection: $idleMinutes) {
                    Text("Nie").tag(0)
                    Text("nach 5 Minuten").tag(5)
                    Text("nach 10 Minuten").tag(10)
                    Text("nach 15 Minuten").tag(15)
                    Text("nach 30 Minuten").tag(30)
                }
            } footer: {
                Text("Läuft ein Timer, während du nicht am Mac bist, kannst du die Zeit danach abziehen.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section {
                Toggle("Tätigkeit automatisch erkennen", isOn: $detectActivity)
                Toggle("Auch Fenstertitel mitlesen", isOn: $readWindowTitles)
                    .disabled(!detectActivity)
                    .onChange(of: readWindowTitles) { _, enabled in
                        // Fragt beim ersten Mal nach und trägt Timecounter in die Liste der Systemeinstellungen ein.
                        if enabled, !ActivityTracker.hasTitleAccess { CGRequestScreenCaptureAccess() }
                        hasTitleAccess = ActivityTracker.hasTitleAccess
                    }
                if detectActivity, readWindowTitles, !hasTitleAccess {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Für Fenstertitel braucht Timecounter die Freigabe „Bildschirm- und Systemaudioaufnahme“. Timecounter nimmt nichts auf, macOS gibt die Titel nur mit dieser Freigabe heraus. Danach Timecounter einmal neu starten.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                        Button("Systemeinstellungen öffnen") {
                            NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture")!)
                        }
                    }
                }
            } footer: {
                Text("Während ein Timer läuft, merkt sich Timecounter, welche App vorne ist. Daraus wird beim Stoppen eine Notiz wie „Figma (40 min): Screens Kapitel 3“, aber nur, wenn du selbst nichts geschrieben hast. Du kannst sie jederzeit ändern. Nichts davon verlässt diesen Mac.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section {
                Picker("Beim Export aufrunden", selection: $roundingMinutes) {
                    Text("Nicht runden").tag(0)
                    Text("auf 5 Minuten").tag(5)
                    Text("auf 6 Minuten").tag(6)
                    Text("auf 15 Minuten").tag(15)
                    Text("auf 30 Minuten").tag(30)
                }
                TextField("Währung", text: $currency)
            }

            Section {
                LabeledContent("Zeiten aus Tim") {
                    Button("Importieren") {
                        do {
                            importResult = try TimImporter.run(context: context).description
                        } catch {
                            importResult = error.localizedDescription
                        }
                    }
                }
                if let importResult {
                    Text(importResult).font(.caption).foregroundStyle(.secondary)
                }
                LabeledContent("Datenordner") {
                    Button("Im Finder zeigen") {
                        NSWorkspace.shared.open(Persistence.storeDirectory)
                    }
                }
            } footer: {
                Text("Der Import übernimmt jede Tim-Aufgabe als Projekt und kann gefahrlos wiederholt werden. Alle Zeiten liegen nur auf diesem Mac. Kopiere den Datenordner, um ein Backup zu machen.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            hasTitleAccess = ActivityTracker.hasTitleAccess
        }
        .frame(width: 460)
        .fixedSize(horizontal: false, vertical: true)
    }
}
