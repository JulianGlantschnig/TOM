import AppKit
import Carbon.HIToolbox
import CoreGraphics
import SwiftData
import SwiftUI

/// Startet und stoppt Zeiteinträge, tickt jede Sekunde und erkennt Leerlauf.
@MainActor
@Observable
final class TimerController {
    private(set) var running: TimeEntry?
    private(set) var now: Date = .now
    /// Welche Apps während des laufenden Timers vorne waren.
    let activity = ActivityTracker()

    @ObservationIgnored private let context: ModelContext
    @ObservationIgnored private var ticker: Timer?
    @ObservationIgnored private var hotKey: HotKey?
    @ObservationIgnored private var idleSince: Date?
    @ObservationIgnored private var isShowingAlert = false

    init(context: ModelContext) {
        self.context = context
        refresh()

        let ticker = Timer(timeInterval: 1, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick() }
        }
        ticker.tolerance = 0.05
        RunLoop.main.add(ticker, forMode: .common)
        self.ticker = ticker

        // ⌃⌥T startet das zuletzt genutzte Projekt bzw. stoppt den laufenden Timer.
        hotKey = HotKey(keyCode: UInt32(kVK_ANSI_T), modifiers: UInt32(controlKey | optionKey)) { [weak self] in
            self?.toggle()
        }

        NotificationCenter.default.addObserver(
            forName: NSWorkspace.willSleepNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, self.idleSince == nil, let entry = self.running, Self.asksAboutIdle(for: entry) else { return }
                self.idleSince = .now
            }
        }
    }

    var elapsed: TimeInterval { running?.duration(now: now) ?? 0 }

    func isRunning(_ project: Project) -> Bool {
        running?.project?.persistentModelID == project.persistentModelID
    }

    func start(_ project: Project) {
        let startDate = Date.now
        if let current = running {
            if current.project?.persistentModelID == project.persistentModelID { return }
            finish(current, at: startDate)
        }
        let entry = TimeEntry(start: startDate, project: project)
        context.insert(entry)
        save()
        running = entry
        now = startDate
        idleSince = nil
        activity.reset()
    }

    func stop() {
        guard let current = running else { return }
        finish(current, at: .now)
        save()
    }

    /// Pausierten Eintrag wieder aufmachen. Er läuft bei seiner bisherigen Dauer weiter,
    /// die Zeit seit dem Stoppen zählt als Pause nicht mit.
    func resume(_ entry: TimeEntry) {
        guard let end = entry.end else { return }
        let resumeDate = Date.now
        if let current = running { finish(current, at: resumeDate) }
        entry.pause += max(0, resumeDate.timeIntervalSince(end))
        entry.end = nil
        save()
        running = entry
        now = resumeDate
        idleSince = nil
        activity.reset()
    }

    func toggle() {
        if running != nil {
            stop()
        } else if let project = lastUsedProject() {
            start(project)
        }
    }

    /// Das Projekt des letzten Eintrags, sonst das erste aktive Projekt.
    func lastUsedProject() -> Project? {
        var descriptor = FetchDescriptor<TimeEntry>(sortBy: [SortDescriptor(\.start, order: .reverse)])
        descriptor.fetchLimit = 20
        let recent = (try? context.fetch(descriptor)) ?? []
        if let project = recent.compactMap(\.project).first(where: { !$0.isArchived }) {
            return project
        }
        let projects = FetchDescriptor<Project>(
            predicate: #Predicate { !$0.isArchived },
            sortBy: [SortDescriptor(\.sortIndex)]
        )
        return try? context.fetch(projects).first
    }

    // MARK: - Intern

    private func finish(_ entry: TimeEntry, at date: Date) {
        entry.end = max(date, entry.start)
        if ActivityTracker.isEnabled {
            entry.tools = Self.combine(entry.tools, activity.tools)
            // Selbst geschriebene Notizen haben Vorrang, der Vorschlag füllt nur eine leere.
            if entry.note.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                entry.note = activity.suggestion
            }
        }
        activity.reset()
        // Versehentliche Klicks nicht als Eintrag behalten.
        if entry.duration() < 3 {
            context.delete(entry)
        }
        if running?.persistentModelID == entry.persistentModelID {
            running = nil
        }
        idleSince = nil
    }

    /// Von Hand gewählte und erkannte Tools zusammenlegen, Zeiten gleicher Programme addieren.
    static func combine(_ lists: [ToolUsage]...) -> [ToolUsage] {
        var result: [ToolUsage] = []
        for tool in lists.joined() {
            if let index = result.firstIndex(where: { $0.name == tool.name }) {
                result[index].seconds += tool.seconds
            } else {
                result.append(tool)
            }
        }
        return result
    }

    private func refresh() {
        var descriptor = FetchDescriptor<TimeEntry>(
            predicate: #Predicate { $0.end == nil },
            sortBy: [SortDescriptor(\.start, order: .reverse)]
        )
        descriptor.fetchLimit = 1
        let current = try? context.fetch(descriptor).first
        if current?.persistentModelID != running?.persistentModelID {
            running = current
            activity.reset()
        }
    }

    private func tick() {
        refresh()
        if running != nil {
            now = .now
            if ActivityTracker.isEnabled { activity.sample(at: now) }
        } else if !Calendar.current.isDate(now, inSameDayAs: .now) {
            // Ohne laufenden Timer tickt `now` nicht mit, sonst bliebe „Heute erfasst“ nach Mitternacht auf gestern stehen.
            now = .now
        }
        checkIdle()
        checkBudget()
    }

    private func save() {
        try? context.save()
    }

    // MARK: - Leerlauf

    private func checkIdle() {
        guard !isShowingAlert else { return }
        let minutes = UserDefaults.standard.integer(forKey: Prefs.idleMinutes)
        guard minutes > 0, let entry = running, Self.asksAboutIdle(for: entry) else {
            idleSince = nil
            return
        }
        let threshold = TimeInterval(minutes * 60)
        let anyInput = CGEventType(rawValue: ~0)!
        let idle = CGEventSource.secondsSinceLastEventType(.combinedSessionState, eventType: anyInput)

        if idle >= threshold {
            if idleSince == nil { idleSince = Date.now.addingTimeInterval(-idle) }
        } else if let since = idleSince, idle < 5 {
            idleSince = nil
            if Date.now.timeIntervalSince(since) >= threshold {
                presentIdleAlert(for: entry, since: max(since, entry.start))
            }
        }
    }

    /// Leerlauf-Nachfrage ist global abschaltbar und pro Projekt, z. B. für Unterricht oder Dreharbeiten.
    static func asksAboutIdle(for entry: TimeEntry) -> Bool {
        UserDefaults.standard.bool(forKey: Prefs.idleDetection) && !(entry.project?.ignoresIdle ?? false)
    }

    private func presentIdleAlert(for entry: TimeEntry, since: Date) {
        isShowingAlert = true
        defer { isShowingAlert = false }

        let alert = NSAlert()
        alert.messageText = String(localized: "Du warst \(Fmt.hoursMinutes(Date.now.timeIntervalSince(since))) nicht am Mac")
        alert.informativeText = String(localized: "Der Timer für „\(entry.project?.name ?? String(localized: "Ohne Projekt"))“ ist seit \(Fmt.time(since)) Uhr weitergelaufen. Was soll mit dieser Zeit passieren?")
        alert.addButton(withTitle: String(localized: "Abziehen und weiterlaufen"))
        alert.addButton(withTitle: String(localized: "Abziehen und stoppen"))
        alert.addButton(withTitle: String(localized: "Zeit behalten"))
        NSApp.activate(ignoringOtherApps: true)

        switch alert.runModal() {
        case .alertFirstButtonReturn:
            let project = entry.project
            finish(entry, at: since)
            save()
            if let project { start(project) }
        case .alertSecondButtonReturn:
            finish(entry, at: since)
            save()
        default:
            break
        }
    }
}

extension TimerController {
    // MARK: - Budget

    /// Meldet sich einmal bei der Vorwarnung und einmal, wenn das vereinbarte Budget erreicht ist,
    /// für das laufende Projekt und für seinen Ordner.
    private func checkBudget() {
        guard let project = running?.project else { return }
        var candidates: [any Budgeted] = [project]
        if let folder = project.folder { candidates.append(folder) }
        for item in candidates where item.budgetHours != nil {
            guard !isShowingAlert else { return }
            let level = item.budgetLevel(now: now)
            // Zeiten gelöscht oder Budget erhöht: der Hinweis darf später wieder kommen.
            if level < item.budgetAlertLevel {
                item.budgetAlertLevel = level
                try? context.save()
            }
            guard level > item.budgetAlertLevel else { continue }
            item.budgetAlertLevel = level
            try? context.save()
            presentBudgetAlert(for: item, level: level)
        }
    }

    private func presentBudgetAlert(for project: any Budgeted, level: Int) {
        guard let budget = project.budgetHours else { return }
        isShowingAlert = true
        defer { isShowingAlert = false }

        let total = project.totalTime(now: .now)
        let alert = NSAlert()
        if level >= 2 {
            alert.alertStyle = .critical
            alert.messageText = String(localized: "„\(project.name)“ hat das Budget von \(Fmt.budgetHours(budget)) erreicht")
            alert.informativeText = String(localized: "Bisher erfasst: \(Fmt.hoursMinutes(total)). Alles ab jetzt geht über die vereinbarte Zeit hinaus.")
            alert.addButton(withTitle: String(localized: "Timer stoppen"))
            alert.addButton(withTitle: String(localized: "Weiterlaufen"))
        } else {
            alert.messageText = String(localized: "„\(project.name)“: \(Fmt.hoursMinutes(total)) von \(Fmt.budgetHours(budget))")
            alert.informativeText = String(localized: "Noch \(Fmt.hoursMinutes(budget * 3600 - total)) bis zum vereinbarten Budget.")
            alert.addButton(withTitle: String(localized: "OK"))
        }
        NSApp.activate(ignoringOtherApps: true)

        if alert.runModal() == .alertFirstButtonReturn, level >= 2 {
            stop()
        }
    }
}

/// Globaler Tastaturkurzbefehl über die Carbon-API (braucht keine Bedienungshilfen-Rechte).
final class HotKey {
    private var hotKeyRef: EventHotKeyRef?
    private var handlerRef: EventHandlerRef?
    private static var action: (@MainActor () -> Void)?

    init(keyCode: UInt32, modifiers: UInt32, action: @escaping @MainActor () -> Void) {
        HotKey.action = action
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), { _, _, _ in
            MainActor.assumeIsolated { HotKey.action?() }
            return noErr
        }, 1, &spec, nil, &handlerRef)

        let id = EventHotKeyID(signature: OSType(0x5443_4E54), id: 1) // "TCNT"
        RegisterEventHotKey(keyCode, modifiers, id, GetApplicationEventTarget(), 0, &hotKeyRef)
    }

    deinit {
        if let hotKeyRef { UnregisterEventHotKey(hotKeyRef) }
        if let handlerRef { RemoveEventHandler(handlerRef) }
    }
}
