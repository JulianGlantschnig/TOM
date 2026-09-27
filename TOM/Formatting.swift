import AppKit
import SwiftUI

enum Prefs {
    /// Nachfragen, wenn der Mac während eines Timers unbenutzt war.
    static let idleDetection = "idleDetection"
    /// Minuten ohne Eingabe, bis nachgefragt wird. 0 stammt aus älteren Versionen und heißt aus.
    static let idleMinutes = "idleMinutes"
    /// Früher ein Schalter für Sekunden, jetzt nur noch zum Übernehmen alter Einstellungen.
    static let showSecondsInMenuBar = "showSecondsInMenuBar"
    /// Was die Menüleiste zeigt, siehe `MenuBarStyle`.
    static let menuBarStyle = "menuBarStyle"
    /// Dock-Symbol zeigen, solange das Übersichtsfenster offen ist.
    static let showInDock = "showInDock"
    /// Hell, dunkel oder wie das System, siehe `AppAppearance`.
    static let appearance = "appearance"
    /// Aufrunden beim Export auf volle N Minuten. 0 = exakt.
    static let roundingMinutes = "roundingMinutes"
    static let currency = "currency"
    /// Merkt sich die App im Vordergrund und schlägt daraus eine Notiz vor.
    static let detectActivity = "detectActivity"
    /// Liest zusätzlich die Fenstertitel mit (braucht die Freigabe für Bildschirmaufnahme).
    static let readWindowTitles = "readWindowTitles"
    /// Kommt eine App nach vorne, die einem Projekt zugeordnet ist, startet TOM dieses Projekt.
    static let appTriggers = "appTriggers"
    /// Vorher nachfragen statt direkt zu starten.
    static let appTriggersAsk = "appTriggersAsk"

    static func registerDefaults() {
        UserDefaults.standard.register(defaults: [
            idleDetection: true,
            idleMinutes: 10,
            menuBarStyle: legacyMenuBarStyle.rawValue,
            showInDock: true,
            appearance: AppAppearance.system.rawValue,
            roundingMinutes: 0,
            currency: "€",
            detectActivity: true,
            readWindowTitles: false,
            appTriggers: false,
            appTriggersAsk: true,
        ])
    }

    /// Wer früher Sekunden ausdrücklich eingeschaltet hatte, behält sie. Sonst gilt h:mm.
    private static var legacyMenuBarStyle: MenuBarStyle {
        UserDefaults.standard.object(forKey: showSecondsInMenuBar) as? Bool == true ? .iconSeconds : .iconMinutes
    }

    static var rounding: Int { UserDefaults.standard.integer(forKey: roundingMinutes) }
    static var currencySymbol: String { UserDefaults.standard.string(forKey: currency) ?? "€" }
}

/// Anzeige in der Menüleiste, solange ein Timer läuft.
enum MenuBarStyle: String, CaseIterable, Identifiable {
    case iconMinutes, iconSeconds, minutes, icon

    var id: Self { self }

    var title: String {
        switch self {
        case .iconMinutes: String(localized: "Symbol und Zeit (1:05)")
        case .iconSeconds: String(localized: "Symbol und Zeit mit Sekunden (1:05:09)")
        case .minutes: String(localized: "Nur Zeit (1:05)")
        case .icon: String(localized: "Nur Symbol")
        }
    }

    var showsIcon: Bool { self != .minutes }
    var showsTime: Bool { self != .icon }
    var showsSeconds: Bool { self == .iconSeconds }
}

/// Erscheinungsbild der ganzen App, also Menü, Übersicht und Einstellungen gemeinsam.
enum AppAppearance: String, CaseIterable, Identifiable {
    case system, light, dark

    var id: Self { self }

    var title: String {
        switch self {
        case .system: String(localized: "Wie System")
        case .light: String(localized: "Hell")
        case .dark: String(localized: "Dunkel")
        }
    }

    @MainActor
    static func apply() {
        let stored = UserDefaults.standard.string(forKey: Prefs.appearance)
        NSApplication.shared.appearance = switch AppAppearance(rawValue: stored ?? "") ?? .system {
        case .system: nil
        case .light: NSAppearance(named: .aqua)
        case .dark: NSAppearance(named: .darkAqua)
        }
    }
}

/// TOM lebt in der Menüleiste. Ins Dock kommt es nur, solange die Übersicht offen ist und es gewünscht ist.
@MainActor
enum DockIcon {
    static var windowIsOpen = false

    static func update() {
        let visible = windowIsOpen && UserDefaults.standard.bool(forKey: Prefs.showInDock)
        NSApp.setActivationPolicy(visible ? .regular : .accessory)
        // Beim Wechsel verliert die App sonst den Fokus und das Fenster rutscht nach hinten.
        if windowIsOpen { NSApp.activate(ignoringOtherApps: true) }
    }
}

enum Fmt {
    static var locale: Locale { .autoupdatingCurrent }

    /// 1:05:09 oder 1:05, mit `padHours` 01:05
    static func clock(_ interval: TimeInterval, seconds: Bool = true, padHours: Bool = false) -> String {
        let total = max(0, Int(interval))
        let h = total / 3600, m = (total % 3600) / 60, s = total % 60
        let hours = padHours ? String(format: "%02d", h) : "\(h)"
        return seconds ? hours + String(format: ":%02d:%02d", m, s) : hours + String(format: ":%02d", m)
    }

    /// 23.09.26
    static func shortDate(_ date: Date) -> String {
        date.formatted(.dateTime.day(.twoDigits).month(.twoDigits).year(.twoDigits).locale(locale))
    }

    /// 14:00:00
    static func timeWithSeconds(_ date: Date) -> String {
        date.formatted(.dateTime.hour(.twoDigits(amPM: .omitted)).minute(.twoDigits).second(.twoDigits).locale(locale))
    }

    /// Erste Zeile einer Notiz, mit „…“, wenn noch mehr folgt.
    static func firstLine(_ text: String) -> String {
        let lines = text.split(whereSeparator: \.isNewline).map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        guard let first = lines.first else { return "" }
        return lines.count > 1 ? first + " …" : first
    }

    /// „3 h 05 min“ bzw. „12 min“
    static func hoursMinutes(_ interval: TimeInterval) -> String {
        let minutes = max(0, Int(interval)) / 60
        let h = minutes / 60, m = minutes % 60
        return h == 0 ? "\(m) min" : String(format: "%d h %02d min", h, m)
    }

    static func decimalHours(_ interval: TimeInterval) -> String {
        (interval / 3600).formatted(.number.precision(.fractionLength(2)).locale(locale))
    }

    static func money(_ value: Double) -> String {
        value.formatted(.number.precision(.fractionLength(2)).locale(locale)) + " " + Prefs.currencySymbol
    }

    static func day(_ date: Date) -> String {
        let cal = Calendar.current
        if cal.isDateInToday(date) { return String(localized: "Heute") }
        if cal.isDateInYesterday(date) { return String(localized: "Gestern") }
        return date.formatted(.dateTime.weekday(.wide).day().month(.wide).year().locale(locale))
    }

    static func time(_ date: Date) -> String {
        date.formatted(.dateTime.hour(.twoDigits(amPM: .omitted)).minute(.twoDigits).locale(locale))
    }

    /// Rundet eine Dauer auf volle `minutes` Minuten auf.
    static func rounded(_ interval: TimeInterval, toMinutes minutes: Int) -> TimeInterval {
        guard minutes > 0 else { return interval }
        let step = Double(minutes * 60)
        return (interval / step).rounded(.up) * step
    }
}

extension Color {
    init(hex: String) {
        var string = hex.trimmingCharacters(in: .whitespaces)
        if string.hasPrefix("#") { string.removeFirst() }
        var value: UInt64 = 0
        Scanner(string: string).scanHexInt64(&value)
        self.init(
            red: Double((value >> 16) & 0xFF) / 255,
            green: Double((value >> 8) & 0xFF) / 255,
            blue: Double(value & 0xFF) / 255
        )
    }
}

extension Calendar {
    func startOfWeek(for date: Date) -> Date {
        dateInterval(of: .weekOfYear, for: date)?.start ?? startOfDay(for: date)
    }
}
