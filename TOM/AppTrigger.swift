import AppKit
import SwiftData
import SwiftUI

/// Kommt eine App nach vorne, die einem Projekt zugeordnet ist, startet TOM dieses Projekt
/// oder fragt mit einem kleinen Hinweis oben rechts nach. Nur aktiv, wenn in den Einstellungen eingeschaltet.
@MainActor
final class AppTrigger {
    private let context: ModelContext
    private let timer: TimerController
    private var observer: NSObjectProtocol?
    private var panel: NSPanel?
    private var hideTask: Task<Void, Never>?
    /// Abgelehnte Projekte bleiben eine Weile still, damit der Hinweis nicht bei jedem App-Wechsel kommt.
    private var quietUntil: [PersistentIdentifier: Date] = [:]

    private static let quietPeriod: TimeInterval = 20 * 60
    private static let visibleFor: Duration = .seconds(12)

    static var isEnabled: Bool { UserDefaults.standard.bool(forKey: Prefs.appTriggers) }
    static var asks: Bool { UserDefaults.standard.bool(forKey: Prefs.appTriggersAsk) }

    init(context: ModelContext, timer: TimerController) {
        self.context = context
        self.timer = timer
        observer = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main
        ) { [weak self] note in
            let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
            let bundleID = app?.bundleIdentifier
            let name = app?.localizedName.map(ToolCatalog.displayName)
            MainActor.assumeIsolated { self?.activated(bundleID, appName: name ?? "") }
        }
    }

    private func activated(_ bundleID: String?, appName: String) {
        guard Self.isEnabled, let bundleID, bundleID != Bundle.main.bundleIdentifier,
              let project = project(for: bundleID), !timer.isRunning(project)
        else { return }
        if let until = quietUntil[project.persistentModelID], until > .now { return }

        // Läuft schon ein anderes Projekt, wird nie ungefragt gewechselt.
        if Self.asks || timer.running != nil {
            ask(project, appName: appName, switching: timer.running != nil)
        } else {
            timer.start(project)
        }
    }

    /// Das erste aktive Projekt, dem die App zugeordnet ist.
    private func project(for bundleID: String) -> Project? {
        let descriptor = FetchDescriptor<Project>(
            predicate: #Predicate { !$0.isArchived && $0.triggerAppsJSON != "" },
            sortBy: [SortDescriptor(\.sortIndex)]
        )
        let projects = (try? context.fetch(descriptor)) ?? []
        return projects.first { $0.triggerApps.contains { $0.bundleID == bundleID } }
    }

    // MARK: - Hinweis

    private func ask(_ project: Project, appName: String, switching: Bool) {
        let prompt = AppTriggerPrompt(project: project, appName: appName, switching: switching) { [weak self] start in
            guard let self else { return }
            if start {
                self.timer.start(project)
            } else {
                self.quietUntil[project.persistentModelID] = Date.now.addingTimeInterval(Self.quietPeriod)
            }
            self.hide()
        }
        show(prompt)
    }

    private func show(_ content: AppTriggerPrompt) {
        let panel = panel ?? {
            // Nicht aktivierend: die App, in der du gerade arbeitest, behält den Fokus.
            let panel = PromptPanel(
                contentRect: .zero,
                styleMask: [.nonactivatingPanel, .borderless],
                backing: .buffered, defer: true
            )
            panel.level = .floating
            panel.isFloatingPanel = true
            panel.hidesOnDeactivate = false
            panel.backgroundColor = .clear
            panel.isOpaque = false
            panel.hasShadow = true
            panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
            self.panel = panel
            return panel
        }()
        let host = NSHostingController(rootView: content)
        let size = host.sizeThatFits(in: NSSize(width: 400, height: 200))
        panel.contentViewController = host
        if let screen = NSScreen.main {
            let frame = screen.visibleFrame
            panel.setFrame(NSRect(x: frame.maxX - size.width - 12, y: frame.maxY - size.height - 12,
                                  width: size.width, height: size.height), display: true)
        }
        panel.orderFrontRegardless()

        hideTask?.cancel()
        hideTask = Task { [weak self] in
            try? await Task.sleep(for: Self.visibleFor)
            guard !Task.isCancelled else { return }
            self?.hide()
        }
    }

    private func hide() {
        hideTask?.cancel()
        panel?.orderOut(nil)
    }
}

/// Randlose Panels nehmen sonst keine Klicks an. Key werden heißt hier nicht, dass TOM aktiv wird.
private final class PromptPanel: NSPanel {
    override var canBecomeKey: Bool { true }
}

private struct AppTriggerPrompt: View {
    let project: Project
    let appName: String
    let switching: Bool
    let answer: (Bool) -> Void

    var body: some View {
        HStack(spacing: 12) {
            ProjectIcon(project: project, size: 20)
            VStack(alignment: .leading, spacing: 2) {
                Text(switching ? "Zu \(project.name) wechseln?" : "\(project.name) starten?")
                    .font(.headline)
                    .lineLimit(1)
                Text("Du arbeitest in \(appName)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 8)
            Button("Nein") { answer(false) }
                .buttonStyle(PromptButtonStyle(fill: .secondary.opacity(0.18), text: .primary))
            // Das Panel wird nie aktiv, deshalb eigene Farben statt `.borderedProminent`, das inaktiv grau wird.
            Button(switching ? "Wechseln" : "Starten") { answer(true) }
                .buttonStyle(PromptButtonStyle(fill: project.color, text: .white))
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .frame(width: 400)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(.separator.opacity(0.5)))
    }
}

private struct PromptButtonStyle<Fill: ShapeStyle>: ButtonStyle {
    let fill: Fill
    let text: Color

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.callout.weight(.medium))
            .foregroundStyle(text)
            .padding(.horizontal, 12)
            .padding(.vertical, 5)
            .background(fill, in: Capsule())
            .opacity(configuration.isPressed ? 0.7 : 1)
    }
}
