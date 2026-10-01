import Foundation
import SwiftData
import SwiftUI

@Model
final class Project {
    var name: String = ""
    var colorHex: String = ProjectPalette.colors[0].hex
    /// Optionaler Stundensatz, falls die Zeit verrechnet wird.
    var hourlyRate: Double?
    var isArchived: Bool = false
    var createdAt: Date = Date()
    var sortIndex: Int = 0
    var folder: Folder?
    /// SF-Symbol-Name, `nil` zeigt nur den Farbpunkt.
    var iconName: String?
    /// Für Arbeit abseits des Macs (Unterricht, Dreharbeiten): keine Leerlauf-Nachfrage.
    var ignoresIdle: Bool = false
    /// Apps, bei denen TOM dieses Projekt starten soll, als JSON, siehe `triggerApps`.
    var triggerAppsJSON: String = ""
    /// Mit dem Kunden vereinbarte Stunden, `nil` heißt kein Budget.
    var budgetHours: Double?
    /// Ab hier warnt TOM vor, z. B. bei 25 von 30 Stunden.
    var budgetWarnHours: Double?
    /// Welcher Budget-Hinweis schon kam, siehe `budgetLevel`. Verhindert, dass er jede Sekunde wiederkommt.
    var budgetAlertLevel: Int = 0

    @Relationship(deleteRule: .cascade, inverse: \TimeEntry.project)
    var entries: [TimeEntry] = []

    init(name: String, colorHex: String, hourlyRate: Double? = nil, sortIndex: Int = 0) {
        self.name = name
        self.colorHex = colorHex
        self.hourlyRate = hourlyRate
        self.sortIndex = sortIndex
    }

    var color: Color { Color(hex: colorHex) }

    /// Alle Zeiten des Projekts, egal aus welchem Zeitraum.
    func totalTime(now: Date) -> TimeInterval {
        entries.reduce(0) { $0 + $1.duration(now: now) }
    }

    /// 0 unter der Vorwarnung, 1 ab der Vorwarnung, 2 ab dem vereinbarten Budget.
    func budgetLevel(now: Date) -> Int {
        guard let budget = budgetHours else { return 0 }
        let hours = totalTime(now: now) / 3600
        if hours >= budget { return 2 }
        if let warn = budgetWarnHours, hours >= warn { return 1 }
        return 0
    }
}

/// Ordner fasst mehrere Projekte zusammen, z. B. „Diplomarbeit“.
@Model
final class Folder {
    var name: String = ""
    var colorHex: String = ProjectPalette.colors[2].hex
    var sortIndex: Int = 0
    var isExpanded: Bool = true
    var createdAt: Date = Date()

    /// Beim Löschen des Ordners bleiben die Projekte erhalten.
    @Relationship(deleteRule: .nullify, inverse: \Project.folder)
    var projects: [Project] = []

    init(name: String, colorHex: String, sortIndex: Int = 0) {
        self.name = name
        self.colorHex = colorHex
        self.sortIndex = sortIndex
    }

    var color: Color { Color(hex: colorHex) }

    /// Ein Ordner gilt als archiviert, wenn alle seine Projekte im Archiv sind.
    var isArchived: Bool { !projects.isEmpty && projects.allSatisfy(\.isArchived) }
}

@Model
final class TimeEntry {
    var start: Date = Date()
    /// `nil`, solange der Timer läuft.
    var end: Date?
    var note: String = ""
    var project: Project?
    /// Verwendete Programme als JSON, siehe `tools`.
    var toolsJSON: String = ""

    init(start: Date, end: Date? = nil, note: String = "", project: Project?) {
        self.start = start
        self.end = end
        self.note = note
        self.project = project
    }

    var isRunning: Bool { end == nil }

    func duration(now: Date = .now) -> TimeInterval {
        max(0, (end ?? now).timeIntervalSince(start))
    }
}

enum ProjectPalette {
    struct Swatch: Identifiable {
        let name: String
        let hex: String
        var id: String { hex }
    }

    static let colors: [Swatch] = [
        Swatch(name: "Tintenblau", hex: "#3B5BDB"),
        Swatch(name: "Salbei", hex: "#4C9A6A"),
        Swatch(name: "Ocker", hex: "#D99A2B"),
        Swatch(name: "Karmin", hex: "#C2334D"),
        Swatch(name: "Pflaume", hex: "#7A4FB5"),
        Swatch(name: "Petrol", hex: "#1F8A99"),
        Swatch(name: "Moos", hex: "#7A8B3A"),
        Swatch(name: "Graphit", hex: "#6B7280"),
    ]
}

/// Symbole zur Auswahl im Projekt-Editor, grob nach Tätigkeit sortiert.
enum ProjectIcons {
    static let all = [
        "book.closed", "books.vertical", "text.book.closed", "doc.text", "doc.richtext", "text.quote",
        "square.and.pencil", "pencil.and.scribble", "highlighter", "quote.opening", "graduationcap", "magnifyingglass",
        "lightbulb", "brain.head.profile", "list.bullet.clipboard", "checklist", "calendar", "flag",
        "person.2", "bubble.left.and.bubble.right", "envelope", "phone", "chart.bar", "chart.pie",
        "function", "flask", "testtube.2", "hammer", "wrench.and.screwdriver", "chevron.left.forwardslash.chevron.right",
        "terminal", "paintbrush", "paintpalette", "pencil.and.ruler", "cube", "photo",
        "camera", "video", "film", "scissors", "mic", "music.note",
        "globe", "link", "printer", "tray.full", "archivebox", "folder",
        "briefcase", "cup.and.saucer", "figure.walk", "star", "sparkles",
    ]
}

enum Persistence {
    /// Wird beim ersten Zugriff festgelegt, nachdem Daten unter einem früheren App-Namen umgezogen sind.
    static let storeDirectory: URL = migrateLegacyStore()

    private static let storeName = "TOM"
    /// Frühere Namen der App, neuester zuerst.
    private static let legacyNames = ["ZeitOpferung", "Timecounter"]

    static func makeContainer() -> ModelContainer {
        try? FileManager.default.createDirectory(at: storeDirectory, withIntermediateDirectories: true)
        // Falls das Umbenennen der Datei nicht geklappt hat, die vorhandene alte Datei weiterverwenden.
        let file = ([storeName] + legacyNames).first {
            FileManager.default.fileExists(atPath: storeDirectory.appending(path: "\($0).store").path)
        } ?? storeName
        let config = ModelConfiguration(url: storeDirectory.appending(path: "\(file).store"))
        do {
            return try ModelContainer(for: Folder.self, Project.self, TimeEntry.self, configurations: config)
        } catch {
            fatalError("Datenbank konnte nicht geöffnet werden: \(error)")
        }
    }

    /// Die App hieß früher „Timecounter“ und „ZeitOpferung“. Ordner und Datenbank einmalig umbenennen.
    /// Klappt das nicht, bleibt alles am alten Ort, damit keine Zeiten verloren gehen.
    private static func migrateLegacyStore() -> URL {
        let fm = FileManager.default
        let base = URL.applicationSupportDirectory
        let current = base.appending(path: storeName, directoryHint: .isDirectory)
        guard !fm.fileExists(atPath: current.path) else { return current }
        guard let legacy = legacyNames
            .map({ base.appending(path: $0, directoryHint: .isDirectory) })
            .first(where: { fm.fileExists(atPath: $0.path) })
        else { return current }
        do {
            try fm.moveItem(at: legacy, to: current)
        } catch {
            return legacy
        }
        for name in legacyNames {
            guard fm.fileExists(atPath: current.appending(path: "\(name).store").path) else { continue }
            for suffix in ["", "-shm", "-wal"] {
                let old = current.appending(path: "\(name).store\(suffix)")
                guard fm.fileExists(atPath: old.path) else { continue }
                try? fm.moveItem(at: old, to: current.appending(path: "\(storeName).store\(suffix)"))
            }
            break
        }
        return current
    }

    /// Kopiert die Datenbank beim ersten Start einer neuen Version in `Backups`, bevor SwiftData sie womöglich umbaut.
    /// Die letzten fünf Sicherungen bleiben liegen, so geht bei einem Update nie etwas verloren.
    static func backupIfNewVersion() {
        let key = "lastLaunchedVersion"
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "?"
        let previous = UserDefaults.standard.string(forKey: key)
        guard previous != version else { return }
        defer { UserDefaults.standard.set(version, forKey: key) }

        let fm = FileManager.default
        let files = ((try? fm.contentsOfDirectory(atPath: storeDirectory.path)) ?? []).filter { $0.contains(".store") }
        guard !files.isEmpty else { return }
        let stamp = Date.now.formatted(.iso8601.year().month().day().dateSeparator(.dash))
        let backups = storeDirectory.appending(path: "Backups", directoryHint: .isDirectory)
        let target = backups.appending(path: "\(stamp) vor \(version)", directoryHint: .isDirectory)
        do {
            try fm.createDirectory(at: target, withIntermediateDirectories: true)
            for file in files {
                try? fm.copyItem(at: storeDirectory.appending(path: file), to: target.appending(path: file))
            }
        } catch { return }

        let old = ((try? fm.contentsOfDirectory(atPath: backups.path)) ?? []).sorted().dropLast(5)
        for name in old { try? fm.removeItem(at: backups.appending(path: name)) }
    }
}
