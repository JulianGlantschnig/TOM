import ServiceManagement
import SwiftData
import SwiftUI

/// Einstellungen in Tabs, wie bei macOS-Apps üblich.
struct SettingsView: View {
    @State private var tab: String = {
        #if DEBUG
        if let tab = UserDefaults.standard.string(forKey: "demoSettingsTab") { return tab }
        #endif
        return "general"
    }()

    var body: some View {
        TabView(selection: $tab) {
            Tab("Allgemein", systemImage: "gearshape", value: "general") { GeneralSettings() }
            Tab("Leerlauf", systemImage: "moon.zzz", value: "idle") { IdleSettings() }
            Tab("Erkennung", systemImage: "eye", value: "detection") { DetectionSettings() }
            Tab("Daten", systemImage: "externaldrive", value: "data") { DataSettings() }
            Tab("Unterstützen", systemImage: "cup.and.saucer", value: "support") { SupportSettings() }
        }
        .frame(width: 500)
    }
}

/// Gemeinsamer Rahmen: gruppiertes Formular, Höhe passt sich dem Inhalt an.
private struct SettingsPane<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        Form { content }
            .formStyle(.grouped)
            .scrollDisabled(true)
            .fixedSize(horizontal: false, vertical: true)
    }
}

private struct Footnote: View {
    let text: Text
    init(_ key: LocalizedStringKey) { text = Text(key) }
    init(verbatim string: String) { text = Text(string) }

    var body: some View {
        text
            .font(.caption)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
    }
}

// MARK: - Allgemein

private struct GeneralSettings: View {
    @AppStorage(Prefs.menuBarStyle) private var menuBarStyle: MenuBarStyle = .iconMinutes
    @AppStorage(Prefs.showInDock) private var showInDock = true
    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled
    @State private var loginError: String?

    var body: some View {
        SettingsPane {
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
                            loginError = String(localized: "Das hat nicht geklappt: \(error.localizedDescription)")
                        }
                    }
                if let loginError {
                    Text(loginError).font(.caption).foregroundStyle(.red)
                }
                Picker("Menüleiste zeigt", selection: $menuBarStyle) {
                    ForEach(MenuBarStyle.allCases) { Text($0.title).tag($0) }
                }
                Toggle(isOn: $showInDock) {
                    Text("Im Dock anzeigen")
                    Text("Solange die Übersicht offen ist. Ausgeschaltet bleibt TOM nur in der Menüleiste.")
                }
                .onChange(of: showInDock) { DockIcon.update() }
                LabeledContent("Timer starten oder stoppen", value: "⌃⌥T")
            }
        }
    }
}

// MARK: - Leerlauf

private struct IdleSettings: View {
    @AppStorage(Prefs.idleDetection) private var idleDetection = true
    @AppStorage(Prefs.idleMinutes) private var idleMinutes = 10
    @Environment(\.modelContext) private var context
    @Query(filter: #Predicate<Project> { !$0.isArchived }, sort: \Project.sortIndex)
    private var projects: [Project]

    var body: some View {
        SettingsPane {
            Section {
                Toggle("Leerlauf erkennen", isOn: $idleDetection)
                    .onChange(of: idleDetection) { _, enabled in
                        // „Nie“ gab es früher als Zeitangabe, beim Einschalten einen sinnvollen Wert setzen.
                        if enabled, idleMinutes == 0 { idleMinutes = 10 }
                    }
                Picker("Nachfragen nach", selection: $idleMinutes) {
                    Text("5 Minuten").tag(5)
                    Text("10 Minuten").tag(10)
                    Text("15 Minuten").tag(15)
                    Text("30 Minuten").tag(30)
                    Text("1 Stunde").tag(60)
                }
                .disabled(!idleDetection)
            } footer: {
                Footnote("Läuft ein Timer, während du nicht am Mac bist oder der Laptop zugeklappt ist, fragt TOM danach, ob die Zeit abgezogen werden soll.")
            }

            if !projects.isEmpty {
                Section {
                    ForEach(projects) { project in
                        Toggle(isOn: Binding(
                            get: { !project.ignoresIdle },
                            set: { project.ignoresIdle = !$0; try? context.save() }
                        )) {
                            HStack(spacing: 8) {
                                ProjectIcon(project: project, size: 12)
                                Text(project.name)
                            }
                        }
                    }
                    .disabled(!idleDetection)
                } header: {
                    Text("Nachfragen bei diesen Projekten")
                } footer: {
                    Footnote("Schalte Projekte aus, bei denen du vom Mac weg bist und die Zeit trotzdem zählt, zum Beispiel Unterricht oder Dreharbeiten. Dort läuft der Timer auch mit zugeklapptem Laptop einfach weiter.")
                }
            }
        }
    }
}

// MARK: - Erkennung

private struct DetectionSettings: View {
    @AppStorage(Prefs.detectActivity) private var detectActivity = true
    @AppStorage(Prefs.readWindowTitles) private var readWindowTitles = false
    @State private var hasTitleAccess = ActivityTracker.hasTitleAccess

    var body: some View {
        SettingsPane {
            Section {
                Toggle("Tätigkeit automatisch erkennen", isOn: $detectActivity)
                Toggle("Auch Fenstertitel mitlesen", isOn: $readWindowTitles)
                    .disabled(!detectActivity)
                    .onChange(of: readWindowTitles) { _, enabled in
                        // Fragt beim ersten Mal nach und trägt TOM in die Liste der Systemeinstellungen ein.
                        if enabled, !ActivityTracker.hasTitleAccess { CGRequestScreenCaptureAccess() }
                        hasTitleAccess = ActivityTracker.hasTitleAccess
                    }
                if detectActivity, readWindowTitles, !hasTitleAccess {
                    VStack(alignment: .leading, spacing: 6) {
                        Footnote("Für Fenstertitel braucht TOM die Freigabe „Bildschirm- und Systemaudioaufnahme“. TOM nimmt nichts auf, macOS gibt die Titel nur mit dieser Freigabe heraus. Danach TOM einmal neu starten.")
                        Button("Systemeinstellungen öffnen") {
                            NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture")!)
                        }
                    }
                }
            } footer: {
                Footnote("Während ein Timer läuft, merkt sich TOM, welche App vorne ist. Daraus werden die Tools des Eintrags und ein Vorschlag für die Notiz, falls du selbst nichts geschrieben hast. Nichts davon verlässt diesen Mac.")
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            hasTitleAccess = ActivityTracker.hasTitleAccess
        }
    }
}

// MARK: - Daten

private struct DataSettings: View {
    @AppStorage(Prefs.roundingMinutes) private var roundingMinutes = 0
    @AppStorage(Prefs.currency) private var currency = "€"
    @State private var importResult: String?
    @Environment(\.modelContext) private var context

    var body: some View {
        SettingsPane {
            Section("Export") {
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
                    Footnote(verbatim: importResult)
                }
                LabeledContent("Datenordner") {
                    Button("Im Finder zeigen") {
                        NSWorkspace.shared.open(Persistence.storeDirectory)
                    }
                }
            } footer: {
                Footnote("Der Import übernimmt jede Tim-Aufgabe als Projekt und kann gefahrlos wiederholt werden. Alle Zeiten liegen nur auf diesem Mac. Kopiere den Datenordner, um ein Backup zu machen.")
            }
        }
    }
}

// MARK: - Unterstützen

private struct SupportSettings: View {
    static let donationURL = URL(string: "https://buymeacoffee.com/GlantschnigJulian")!
    static let projectURL = URL(string: "https://github.com/JulianGlantschnig/TOM")!
    private let ochre = Color(hex: ProjectPalette.colors[2].hex)

    var body: some View {
        VStack(spacing: 18) {
            Image(systemName: "cup.and.saucer.fill")
                .font(.system(size: 44, weight: .regular))
                .foregroundStyle(ochre)
                .padding(22)
                .background(ochre.opacity(0.14), in: Circle())

            VStack(spacing: 6) {
                Text("TOM ist kostenlos")
                    .font(.title2.weight(.semibold))
                Text("Entstanden neben einer Diplomarbeit, gebaut in der Freizeit. Wenn dir TOM Zeit spart, freue ich mich über einen Kaffee.")
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: 340)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Link(destination: Self.donationURL) {
                Label("Kaffee spendieren", systemImage: "heart.fill")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 20)
                    .padding(.vertical, 9)
                    .background(ochre, in: Capsule())
                    .contentShape(Capsule())
            }
            .buttonStyle(.plain)
            .pointerStyle(.link)
            .help("Öffnet buymeacoffee.com im Browser")

            Link("Projekt auf GitHub", destination: Self.projectURL)
                .font(.callout)
        }
        .padding(.horizontal, 32)
        .padding(.vertical, 30)
        .frame(maxWidth: .infinity)
    }
}
