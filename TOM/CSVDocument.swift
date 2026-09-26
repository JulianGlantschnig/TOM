import SwiftUI
import UniformTypeIdentifiers

/// CSV, die Excel und Numbers direkt richtig öffnen: bei Dezimalkomma (z. B. Deutsch) mit Semikolon getrennt, sonst mit Komma.
struct CSVDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.commaSeparatedText] }

    var text: String

    @MainActor
    init(entries: [TimeEntry]) {
        let rounding = Prefs.rounding
        let now = Date.now
        var rows = [[
            String(localized: "Datum"), String(localized: "Beginn"), String(localized: "Ende"), String(localized: "Dauer"), String(localized: "Stunden"), String(localized: "Projekt"), String(localized: "Tools"), String(localized: "Notiz"), String(localized: "Stundensatz"), String(localized: "Betrag"),
        ]]

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
                entry.tools.map(\.name).joined(separator: ", "),
                entry.note,
                rate.map(Fmt.money) ?? "",
                rate.map { Fmt.money($0 * duration / 3600) } ?? "",
            ])
        }

        let separator = Fmt.locale.decimalSeparator == "," ? ";" : ","
        text = "\u{FEFF}" + rows.map { $0.map { Self.escape($0, separator: separator) }.joined(separator: separator) }.joined(separator: "\r\n")
    }

    init(configuration: ReadConfiguration) throws {
        text = String(decoding: configuration.file.regularFileContents ?? Data(), as: UTF8.self)
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: Data(text.utf8))
    }

    private static func escape(_ field: String, separator: String) -> String {
        guard field.contains(where: { (separator + "\"\n\r").contains($0) }) else { return field }
        return "\"" + field.replacingOccurrences(of: "\"", with: "\"\"") + "\""
    }
}
