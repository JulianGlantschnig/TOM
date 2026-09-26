import SwiftUI
import UniformTypeIdentifiers

/// CSV mit Semikolon und Dezimalkomma, damit Excel und Numbers auf Deutsch sie direkt richtig öffnen.
struct CSVDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.commaSeparatedText] }

    var text: String

    @MainActor
    init(entries: [TimeEntry]) {
        let rounding = Prefs.rounding
        let now = Date.now
        var rows = [["Datum", "Beginn", "Ende", "Dauer", "Stunden", "Projekt", "Notiz", "Stundensatz", "Betrag"]]

        for entry in entries.sorted(by: { $0.start < $1.start }) {
            let end = entry.end ?? now
            let duration = Fmt.rounded(entry.duration(now: now), toMinutes: rounding)
            let rate = entry.project?.hourlyRate
            rows.append([
                entry.start.formatted(.dateTime.day(.twoDigits).month(.twoDigits).year().locale(Fmt.locale)),
                Fmt.time(entry.start),
                Fmt.time(end),
                Fmt.clock(duration, seconds: false),
                Fmt.decimalHours(duration),
                entry.project?.name ?? "",
                entry.note,
                rate.map(Fmt.money) ?? "",
                rate.map { Fmt.money($0 * duration / 3600) } ?? "",
            ])
        }

        text = "\u{FEFF}" + rows.map { $0.map(Self.escape).joined(separator: ";") }.joined(separator: "\r\n")
    }

    init(configuration: ReadConfiguration) throws {
        text = String(decoding: configuration.file.regularFileContents ?? Data(), as: UTF8.self)
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: Data(text.utf8))
    }

    private static func escape(_ field: String) -> String {
        guard field.contains(where: { ";\"\n\r".contains($0) }) else { return field }
        return "\"" + field.replacingOccurrences(of: "\"", with: "\"\"") + "\""
    }
}
