import Foundation
import SwiftUI

/// Welche Einträge eine Ansicht zeigt.
enum EntryScope: Hashable {
    case today, week, all
    case folder(Folder)
    case project(Project)

    var title: String {
        switch self {
        case .today: "Heute"
        case .week: "Diese Woche"
        case .all: "Alle Einträge"
        case .folder(let folder): folder.name
        case .project(let project): project.name
        }
    }

    var project: Project? {
        if case .project(let project) = self { project } else { nil }
    }

    func contains(_ entry: TimeEntry, now: Date) -> Bool {
        let cal = Calendar.current
        switch self {
        case .today: return entry.start >= cal.startOfDay(for: now)
        case .week: return entry.start >= cal.startOfWeek(for: now)
        case .all: return true
        case .folder(let folder): return entry.project?.folder?.persistentModelID == folder.persistentModelID
        case .project(let project): return entry.project?.persistentModelID == project.persistentModelID
        }
    }
}
