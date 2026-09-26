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

    @Relationship(deleteRule: .cascade, inverse: \TimeEntry.project)
    var entries: [TimeEntry] = []

    init(name: String, colorHex: String, hourlyRate: Double? = nil, sortIndex: Int = 0) {
        self.name = name
        self.colorHex = colorHex
        self.hourlyRate = hourlyRate
        self.sortIndex = sortIndex
    }

    var color: Color { Color(hex: colorHex) }
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
    static var storeDirectory: URL {
        URL.applicationSupportDirectory.appending(path: "Timecounter", directoryHint: .isDirectory)
    }

    static func makeContainer() -> ModelContainer {
        try? FileManager.default.createDirectory(at: storeDirectory, withIntermediateDirectories: true)
        let config = ModelConfiguration(url: storeDirectory.appending(path: "Timecounter.store"))
        do {
            return try ModelContainer(for: Folder.self, Project.self, TimeEntry.self, configurations: config)
        } catch {
            fatalError("Datenbank konnte nicht geöffnet werden: \(error)")
        }
    }

    /// Legt beim allerersten Start ein paar Projekte für die Diplomarbeit an.
    @MainActor
    static func seedIfNeeded(_ context: ModelContext) {
        let key = "didSeedProjects"
        guard !UserDefaults.standard.bool(forKey: key) else { return }
        UserDefaults.standard.set(true, forKey: key)
        guard (try? context.fetchCount(FetchDescriptor<Project>())) == 0 else { return }

        let names = ["Recherche & Literatur", "Schreiben", "Analyse & Auswertung", "Betreuung & Besprechungen"]
        for (index, name) in names.enumerated() {
            context.insert(Project(name: name, colorHex: ProjectPalette.colors[index].hex, sortIndex: index))
        }
        try? context.save()
    }
}
