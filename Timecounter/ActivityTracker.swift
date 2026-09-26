import AppKit
import CoreGraphics

/// Merkt sich, solange ein Timer läuft, welche App (und welches Fenster) vorne ist,
/// und macht daraus einen Vorschlag für die Notiz. Nichts davon verlässt den Mac.
///
/// Den App-Namen darf jede App ohne Rückfrage lesen. Fenstertitel anderer Apps gibt macOS
/// nur mit der Freigabe „Bildschirm- und Systemaudioaufnahme“ heraus, ohne sie bleibt es beim App-Namen.
@MainActor
@Observable
final class ActivityTracker {
    struct AppUsage {
        let name: String
        let bundleID: String
        var seconds: TimeInterval = 0
        var titles: [String: TimeInterval] = [:]
    }

    private(set) var apps: [String: AppUsage] = [:]

    @ObservationIgnored private var lastSample: Date?

    /// Alle 5 Sekunden nachsehen reicht und kostet praktisch nichts.
    private static let interval: TimeInterval = 5
    /// Länger ohne Eingabe zählt nicht als Arbeit in der App davor.
    private static let idleLimit: TimeInterval = 180
    private static let ignoredBundleIDs: Set<String> = [
        Bundle.main.bundleIdentifier ?? "", "com.apple.loginwindow", "com.apple.ScreenSaver.Engine",
    ]

    static var isEnabled: Bool { UserDefaults.standard.bool(forKey: Prefs.detectActivity) }
    static var readsTitles: Bool { UserDefaults.standard.bool(forKey: Prefs.readWindowTitles) }
    static var hasTitleAccess: Bool { CGPreflightScreenCaptureAccess() }

    func reset() {
        apps = [:]
        lastSample = nil
    }

    func sample(at date: Date) {
        guard let last = lastSample else {
            lastSample = date
            return
        }
        let elapsed = date.timeIntervalSince(last)
        guard elapsed >= Self.interval else { return }
        lastSample = date

        let anyInput = CGEventType(rawValue: ~0)!
        guard
            CGEventSource.secondsSinceLastEventType(.combinedSessionState, eventType: anyInput) < Self.idleLimit,
            let app = NSWorkspace.shared.frontmostApplication,
            !Self.ignoredBundleIDs.contains(app.bundleIdentifier ?? ""),
            let rawName = app.localizedName,
            let bundleID = app.bundleIdentifier
        else { return }
        let name = ToolCatalog.displayName(rawName)

        // Nach Schlaf oder Hänger nicht die ganze Lücke der aktuellen App zuschlagen.
        let seconds = min(elapsed, Self.interval * 2)
        var usage = apps[name] ?? AppUsage(name: name, bundleID: bundleID)
        usage.seconds += seconds
        if Self.readsTitles, let title = Self.frontWindowTitle(pid: app.processIdentifier, appName: name) {
            usage.titles[title, default: 0] += seconds
        }
        apps[name] = usage
    }

    /// Die meistgenutzten Apps, für die kurze Anzeige im Menü.
    var topAppNames: [String] {
        ranked.prefix(3).map(\.name)
    }

    /// Die Apps, in denen wirklich gearbeitet wurde, mit gemessener Zeit.
    var tools: [ToolUsage] {
        let ranked = ranked
        let total = ranked.reduce(0) { $0 + $1.seconds }
        let relevant = ranked.filter { $0.seconds >= max(60, total * 0.05) }
        return (relevant.isEmpty ? Array(ranked.prefix(1)) : relevant)
            .map { ToolUsage(bundleID: $0.bundleID, name: $0.name, seconds: $0.seconds) }
    }

    /// Notizvorschlag, eine Zeile pro App, z. B. „Figma (40 min): Screens Kapitel 3, Navigation“.
    var suggestion: String {
        let ranked = ranked
        let total = ranked.reduce(0) { $0 + $1.seconds }
        let relevant = ranked.filter { $0.seconds >= max(60, total * 0.05) }
        let chosen = relevant.isEmpty ? Array(ranked.prefix(1)) : Array(relevant.prefix(4))
        return chosen.map { app in
            let head = app.seconds >= 60 ? "\(app.name) (\(Fmt.hoursMinutes(app.seconds)))" : app.name
            let titles = app.titles
                .filter { $0.value >= 15 }
                .sorted { $0.value > $1.value }
                .prefix(3)
                .map(\.key)
            return titles.isEmpty ? head : head + ": " + titles.joined(separator: ", ")
        }
        .joined(separator: "\n")
    }

    private var ranked: [AppUsage] {
        apps.values.sorted { $0.seconds > $1.seconds }
    }

    // MARK: - Fenstertitel

    private static func frontWindowTitle(pid: pid_t, appName: String) -> String? {
        guard
            hasTitleAccess,
            let windows = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]]
        else { return nil }
        // Die Liste ist von vorne nach hinten sortiert, das erste normale Fenster der App ist das aktive.
        for window in windows {
            guard
                window[kCGWindowOwnerPID as String] as? pid_t == pid,
                window[kCGWindowLayer as String] as? Int == 0,
                let raw = window[kCGWindowName as String] as? String
            else { continue }
            let title = clean(raw, appName: appName)
            if !title.isEmpty { return title }
        }
        return nil
    }

    /// „Kapitel 3.docx — Pages“ → „Kapitel 3.docx“: den App-Namen aus dem Titel streichen.
    static func clean(_ raw: String, appName: String) -> String {
        var parts = [raw]
        for separator in [" — ", " – ", " - ", " | "] {
            parts = parts.flatMap { $0.components(separatedBy: separator) }
        }
        parts = parts.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
        let app = appName.lowercased()
        let isAppName = { (part: String) in
            let lower = part.lowercased()
            return lower.contains(app) || (lower.count >= 3 && app.contains(lower))
        }
        let kept = parts.filter { !isAppName($0) }
        let title = kept.joined(separator: " – ")
        return title.count > 70 ? String(title.prefix(69)) + "…" : title
    }
}
