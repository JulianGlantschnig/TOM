import AppKit
import SwiftUI

/// Ein Programm, das in einem Eintrag verwendet wurde. `seconds` ist 0, wenn es von Hand gewählt wurde.
struct ToolUsage: Codable, Hashable, Identifiable {
    /// Bundle-ID, damit sich das echte App-Icon finden lässt.
    var bundleID: String
    var name: String
    var seconds: TimeInterval = 0

    var id: String { name }
}

extension TimeEntry {
    var tools: [ToolUsage] {
        get {
            guard !toolsJSON.isEmpty else { return [] }
            return (try? JSONDecoder().decode([ToolUsage].self, from: Data(toolsJSON.utf8))) ?? []
        }
        set {
            let sorted = newValue.sorted { $0.seconds != $1.seconds ? $0.seconds > $1.seconds : $0.name < $1.name }
            toolsJSON = sorted.isEmpty ? "" : (try? String(decoding: JSONEncoder().encode(sorted), as: UTF8.self)) ?? ""
        }
    }

    /// Zeit pro Tool. Von Hand gewählte Tools ohne gemessene Zeit teilen sich die Dauer des Eintrags.
    func toolTimes(now: Date = .now) -> [String: TimeInterval] {
        let tools = tools
        guard !tools.isEmpty else { return [:] }
        if tools.allSatisfy({ $0.seconds == 0 }) {
            let share = duration(now: now) / Double(tools.count)
            return Dictionary(tools.map { ($0.name, share) }, uniquingKeysWith: +)
        }
        return Dictionary(tools.map { ($0.name, $0.seconds) }, uniquingKeysWith: +)
    }
}

/// Findet die installierten Programme und ihre Icons.
@MainActor
enum ToolCatalog {
    struct App: Identifiable, Hashable {
        let bundleID: String
        let name: String
        let url: URL
        var id: String { name }
        var usage: ToolUsage { ToolUsage(bundleID: bundleID, name: name) }
    }

    /// Kreativ- und Arbeitsprogramme, die im Menü zuerst angeboten werden, sofern installiert.
    private static let preferred = [
        "Figma", "DaVinci Resolve", "Adobe InDesign", "Adobe Illustrator", "Adobe Photoshop",
        "Adobe Premiere Pro", "Adobe After Effects", "Adobe Audition", "Adobe Lightroom Classic",
        "Adobe Media Encoder", "Adobe Bridge", "Adobe Acrobat", "Final Cut Pro", "Logic Pro", "Blender",
        "Cinema 4D", "Affinity Designer", "Affinity Photo", "Affinity Publisher", "Sketch", "Framer", "Spline",
        "Microsoft Word", "Microsoft PowerPoint", "Microsoft Excel", "Microsoft OneNote", "Pages", "Keynote",
        "Numbers", "Notion", "Obsidian", "Zotero", "reMarkable", "Fade In", "Miro", "Canva",
        "Visual Studio Code", "Cursor", "Xcode", "Zen", "Safari", "Google Chrome", "Arc", "Firefox",
    ]

    /// Alle installierten Programme, nach Name eindeutig (neueste Adobe-Version gewinnt).
    nonisolated static let installed: [App] = {
        let fm = FileManager.default
        let roots = [
            URL(filePath: "/Applications"), URL(filePath: "/System/Applications"),
            fm.homeDirectoryForCurrentUser.appending(path: "Applications"),
        ]
        var found: [String: App] = [:]
        func add(_ url: URL) {
            guard let bundle = Bundle(url: url), let id = bundle.bundleIdentifier else { return }
            let name = displayName(url.deletingPathExtension().lastPathComponent)
            if let existing = found[name], existing.url.lastPathComponent > url.lastPathComponent { return }
            found[name] = App(bundleID: id, name: name, url: url)
        }
        for root in roots {
            for item in (try? fm.contentsOfDirectory(at: root, includingPropertiesForKeys: nil)) ?? [] {
                if item.pathExtension == "app" {
                    add(item)
                } else {
                    // Adobe und Blackmagic legen ihre Apps in eigene Ordner.
                    for inner in (try? fm.contentsOfDirectory(at: item, includingPropertiesForKeys: nil)) ?? []
                    where inner.pathExtension == "app" {
                        add(inner)
                    }
                }
            }
        }
        return found.values.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }()

    /// Die bekannten Programme, die auf diesem Mac installiert sind.
    static var suggested: [App] {
        preferred.compactMap { name in installed.first { $0.name == name } }
    }

    /// „Adobe InDesign 2026“ → „Adobe InDesign“, damit Versionen zusammen zählen.
    nonisolated static func displayName(_ raw: String) -> String {
        raw.replacing(/\s+(19|20)\d\d$/, with: "")
    }

    private static var iconCache: [String: NSImage] = [:]

    static func icon(for tool: ToolUsage) -> NSImage? {
        if let cached = iconCache[tool.name] { return cached }
        let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: tool.bundleID)
            ?? installed.first { $0.name == tool.name }?.url
        guard let url else { return nil }
        let icon = NSWorkspace.shared.icon(forFile: url.path)
        icon.size = NSSize(width: 32, height: 32)
        iconCache[tool.name] = icon
        return icon
    }

    /// Kleine Kopie für Menüeinträge.
    static func menuIcon(for tool: ToolUsage) -> NSImage? {
        guard let icon = icon(for: tool)?.copy() as? NSImage else { return nil }
        icon.size = NSSize(width: 16, height: 16)
        return icon
    }

    /// Mehrere Icons nebeneinander als ein Bild, denn Menü-Beschriftungen zeigen nur ein einziges Bild.
    static func strip(for tools: [ToolUsage], size: CGFloat = 16, spacing: CGFloat = 3) -> NSImage? {
        let icons = tools.compactMap { icon(for: $0) }
        guard !icons.isEmpty else { return nil }
        let width = CGFloat(icons.count) * size + CGFloat(icons.count - 1) * spacing
        return NSImage(size: NSSize(width: width, height: size), flipped: false) { _ in
            for (index, icon) in icons.enumerated() {
                let x = CGFloat(index) * (size + spacing)
                icon.draw(in: NSRect(x: x, y: 0, width: size, height: size))
            }
            return true
        }
    }

    /// Lässt eine beliebige App aus dem Programme-Ordner wählen.
    static func pickOtherApp() -> ToolUsage? {
        let panel = NSOpenPanel()
        panel.directoryURL = URL(filePath: "/Applications")
        panel.allowedContentTypes = [.application]
        panel.prompt = "Als Tool hinzufügen"
        guard panel.runModal() == .OK, let url = panel.url, let id = Bundle(url: url)?.bundleIdentifier else { return nil }
        return ToolUsage(bundleID: id, name: displayName(url.deletingPathExtension().lastPathComponent))
    }
}

/// Echtes App-Icon, als Ersatz ein neutrales Symbol.
struct ToolIcon: View {
    let tool: ToolUsage
    var size: CGFloat = 16

    var body: some View {
        if let icon = ToolCatalog.icon(for: tool) {
            Image(nsImage: icon)
                .resizable()
                .interpolation(.high)
                .frame(width: size, height: size)
        } else {
            Image(systemName: "app.dashed")
                .font(.system(size: size * 0.8))
                .frame(width: size, height: size)
                .foregroundStyle(.secondary)
        }
    }
}

/// Icons der verwendeten Tools. Ein Klick öffnet die Auswahl, in der sich Tools an- und abwählen lassen.
struct ToolsMenu: View {
    @Binding var tools: [ToolUsage]
    var maxIcons = 5
    var showsEmptyLabel = false

    var body: some View {
        Menu {
            let chosen = Set(tools.map(\.name))
            if !tools.isEmpty {
                Section("Verwendet") {
                    ForEach(tools) { tool in
                        toggle(tool, isOn: true)
                    }
                }
            }
            Section("Tools") {
                ForEach(ToolCatalog.suggested.filter { !chosen.contains($0.name) }) { app in
                    toggle(app.usage, isOn: false)
                }
            }
            Divider()
            Button("Andere App wählen …") {
                if let tool = ToolCatalog.pickOtherApp(), !tools.contains(where: { $0.name == tool.name }) {
                    tools.append(tool)
                }
            }
            if !tools.isEmpty {
                Button("Alle entfernen") { tools = [] }
            }
        } label: {
            label
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .help(helpText)
    }

    @ViewBuilder
    private var label: some View {
        if tools.isEmpty {
            if showsEmptyLabel {
                Label("Tools wählen", systemImage: "plus.circle")
            } else {
                // Menü-Beschriftungen ignorieren SwiftUI-Farben, deshalb ein fertig eingefärbtes Symbol.
                Image(nsImage: Self.faintPlus)
            }
        } else {
            let extra = tools.count - maxIcons
            if let strip = ToolCatalog.strip(for: Array(tools.prefix(maxIcons))) {
                if extra > 0 {
                    Label { Text("+\(extra)") } icon: { Image(nsImage: strip) }
                } else {
                    Image(nsImage: strip)
                }
            } else {
                Text(tools.map(\.name).joined(separator: ", "))
            }
        }
    }

    private func toggle(_ tool: ToolUsage, isOn: Bool) -> some View {
        Toggle(isOn: Binding(
            get: { isOn },
            set: { on in
                if on { tools.append(tool) } else { tools.removeAll { $0.name == tool.name } }
            }
        )) {
            if let icon = ToolCatalog.menuIcon(for: tool) {
                Label { Text(isOn && tool.seconds >= 60 ? "\(tool.name) · \(Fmt.hoursMinutes(tool.seconds))" : tool.name) } icon: { Image(nsImage: icon) }
            } else {
                Text(tool.name)
            }
        }
    }

    private static let faintPlus: NSImage = {
        let config = NSImage.SymbolConfiguration(pointSize: 10, weight: .medium)
            .applying(.init(paletteColors: [.tertiaryLabelColor]))
        return NSImage(systemSymbolName: "plus", accessibilityDescription: "Tools wählen")?
            .withSymbolConfiguration(config) ?? NSImage()
    }()

    private var helpText: String {
        guard !tools.isEmpty else { return "Tools für diesen Eintrag wählen" }
        return tools.map { $0.seconds >= 60 ? "\($0.name): \(Fmt.hoursMinutes($0.seconds))" : $0.name }.joined(separator: "\n")
    }
}

/// Wie viel Zeit in welchem Programm steckt, mit Balken relativ zum meistgenutzten Tool.
struct ToolTotalsView: View {
    let entries: [TimeEntry]
    let now: Date
    var limit = 6

    var body: some View {
        let totals = Self.totals(entries, now: now)
        let longest = totals.first?.seconds ?? 0
        if !totals.isEmpty {
            VStack(alignment: .leading, spacing: 7) {
                Text("Tools")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
                ForEach(totals.prefix(limit)) { tool in
                    HStack(spacing: 8) {
                        ToolIcon(tool: tool, size: 18)
                        Text(tool.name)
                            .lineLimit(1)
                            .frame(width: 150, alignment: .leading)
                        GeometryReader { proxy in
                            Capsule()
                                .fill(.secondary.opacity(0.35))
                                .frame(width: max(3, proxy.size.width * (longest > 0 ? tool.seconds / longest : 0)), height: 5)
                                .frame(maxHeight: .infinity)
                        }
                        .frame(height: 18)
                        Text(Fmt.clock(tool.seconds, seconds: false, padHours: true))
                            .monospacedDigit()
                            .frame(width: 48, alignment: .trailing)
                    }
                    .font(.callout)
                }
                if totals.count > limit {
                    Text("und \(totals.count - limit) weitere")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    static func totals(_ entries: [TimeEntry], now: Date) -> [ToolUsage] {
        var seconds: [String: TimeInterval] = [:]
        var bundleIDs: [String: String] = [:]
        for entry in entries {
            for tool in entry.tools { bundleIDs[tool.name] = tool.bundleID }
            for (name, time) in entry.toolTimes(now: now) { seconds[name, default: 0] += time }
        }
        return seconds
            .map { ToolUsage(bundleID: bundleIDs[$0.key] ?? "", name: $0.key, seconds: $0.value) }
            .sorted { $0.seconds > $1.seconds }
    }
}
