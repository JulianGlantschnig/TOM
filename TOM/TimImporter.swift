import Foundation
import SwiftData

/// Übernimmt Aufgaben und Zeiten aus Tim (neat.software). Tim speichert alles als JSON in seinen Einstellungen.
/// Jede Tim-Aufgabe wird zu einem Projekt. Bereits importierte Einträge werden übersprungen.
enum TimImporter {
    struct Summary {
        var newProjects = 0
        var newFolders = 0
        var importedEntries = 0
        var skippedEntries = 0

        var description: String {
            "\(importedEntries) Einträge übernommen, \(newProjects) Projekte und \(newFolders) Ordner neu angelegt"
                + (skippedEntries > 0 ? ", \(skippedEntries) schon vorhanden oder noch laufend" : "")
        }
    }

    enum ImportError: LocalizedError {
        case notFound
        case unreadable

        var errorDescription: String? {
            switch self {
            case .notFound: "Keine Tim-Daten gefunden. Ist Tim auf diesem Mac installiert?"
            case .unreadable: "Die Tim-Daten konnten nicht gelesen werden. Erlaube TOM den Zugriff auf Daten anderer Apps und versuch es nochmal."
            }
        }
    }

    static var preferencesURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appending(path: "Library/Containers/neat.software.Tim/Data/Library/Preferences/neat.software.Tim.plist")
    }

    private struct TimData: Decodable {
        let groups: [String: TimGroup]?
        let nodes: [TimNode]?
        let tasks: [String: TimTask]
    }

    private struct TimGroup: Decodable {
        let title: String
        let color: String?
    }

    private struct TimNode: Decodable {
        let id: String
        let parent: String?
    }

    private struct TimTask: Decodable {
        let title: String
        let color: String?
        let records: [TimRecord]?
    }

    private struct TimRecord: Decodable {
        /// Millisekunden seit 1970
        let start: Double
        let end: Double?
        let note: String?
    }

    private static let colorMap: [String: String] = [
        "Blue": "#3B5BDB", "Indigo": "#3B5BDB",
        "Green": "#4C9A6A", "Mint": "#4C9A6A",
        "Orange": "#D99A2B", "Yellow": "#D99A2B", "Brown": "#D99A2B",
        "Red": "#C2334D",
        "Pink": "#7A4FB5", "Purple": "#7A4FB5",
        "Teal": "#1F8A99", "Cyan": "#1F8A99",
        "Gray": "#6B7280", "Grey": "#6B7280",
    ]

    @MainActor
    static func run(context: ModelContext, from url: URL = preferencesURL) throws -> Summary {
        guard FileManager.default.fileExists(atPath: url.path) else { throw ImportError.notFound }
        guard
            let data = try? Data(contentsOf: url),
            let plist = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any],
            let json = plist["Tim_Data"] as? Data,
            let tim = try? JSONDecoder().decode(TimData.self, from: json)
        else { throw ImportError.unreadable }

        var summary = Summary()
        var projects = try context.fetch(FetchDescriptor<Project>())
        var folders = try context.fetch(FetchDescriptor<Folder>())
        var nextIndex = (projects.map(\.sortIndex).max() ?? -1) + 1
        let parentOf = Dictionary((tim.nodes ?? []).compactMap { node in node.parent.map { (node.id, $0) } }, uniquingKeysWith: { first, _ in first })

        // Tim-Gruppen werden zu Ordnern.
        func folder(forGroup id: String) -> Folder? {
            guard let group = tim.groups?[id] else { return nil }
            let name = group.title.trimmingCharacters(in: .whitespacesAndNewlines)
            if let existing = folders.first(where: { $0.name.localizedCaseInsensitiveCompare(name) == .orderedSame }) {
                return existing
            }
            let hex = group.color.flatMap { colorMap[$0] } ?? ProjectPalette.colors[2].hex
            let new = Folder(name: name, colorHex: hex, sortIndex: (folders.map(\.sortIndex).max() ?? -1) + 1)
            context.insert(new)
            folders.append(new)
            summary.newFolders += 1
            return new
        }

        for (taskID, task) in tim.tasks.sorted(by: { $0.value.title < $1.value.title }) {
            let name = task.title.trimmingCharacters(in: .whitespacesAndNewlines)
            let project: Project
            if let existing = projects.first(where: { $0.name.localizedCaseInsensitiveCompare(name) == .orderedSame }) {
                project = existing
            } else {
                let hex = task.color.flatMap { colorMap[$0] } ?? ProjectPalette.colors[nextIndex % ProjectPalette.colors.count].hex
                project = Project(name: name, colorHex: hex, sortIndex: nextIndex)
                context.insert(project)
                projects.append(project)
                nextIndex += 1
                summary.newProjects += 1
            }
            if project.folder == nil, let groupID = parentOf[taskID] {
                project.folder = folder(forGroup: groupID)
            }

            for record in task.records ?? [] {
                // Laufende Tim-Timer nicht übernehmen, die sind noch nicht fertig.
                guard let endMillis = record.end else {
                    summary.skippedEntries += 1
                    continue
                }
                let start = Date(timeIntervalSince1970: record.start / 1000)
                let end = Date(timeIntervalSince1970: endMillis / 1000)
                if project.entries.contains(where: { abs($0.start.timeIntervalSince(start)) < 1 }) {
                    summary.skippedEntries += 1
                    continue
                }
                let note = (record.note ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                context.insert(TimeEntry(start: start, end: end, note: note, project: project))
                summary.importedEntries += 1
            }
        }

        try context.save()
        return summary
    }
}
