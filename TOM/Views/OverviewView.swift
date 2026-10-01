import Charts
import SwiftData
import SwiftUI

/// Ordner oder Projekt: Umschalter zwischen Diagramm und Tabelle, wie in Tim.
struct ScopeDetailView: View {
    enum Mode: Hashable { case chart, list }

    let scope: EntryScope
    @State private var mode: Mode
    @State private var editingProject: Project?
    @State private var editingFolder: Folder?

    init(scope: EntryScope) {
        self.scope = scope
        if case .folder = scope { _mode = State(initialValue: .chart) } else { _mode = State(initialValue: .list) }
        #if DEBUG
        if UserDefaults.standard.string(forKey: "demoPage") == "budget" { _mode = State(initialValue: .chart) }
        #endif
    }

    var body: some View {
        Group {
            switch mode {
            case .chart: OverviewView(scope: scope)
            case .list: EntriesView(scope: scope)
            }
        }
        .toolbar {
            ToolbarItem(placement: .navigation) {
                Picker("Ansicht", selection: $mode) {
                    Label("Diagramm", systemImage: "chart.bar.fill").tag(Mode.chart)
                    Label(String(localized: "Einträge"), systemImage: "list.bullet").tag(Mode.list)
                }
                .pickerStyle(.segmented)
                .labelStyle(.iconOnly)
                .help("Zwischen Diagramm und Einträgen wechseln")
            }
            ToolbarItem(placement: .primaryAction) {
                Button {
                    switch scope {
                    case .project(let project): editingProject = project
                    case .folder(let folder): editingFolder = folder
                    default: break
                    }
                } label: {
                    Label(scope.project == nil ? String(localized: "Ordner bearbeiten") : String(localized: "Projekteinstellungen"), systemImage: "slider.horizontal.3")
                }
                .help(scope.project == nil ? String(localized: "Name und Farbe des Ordners ändern") : String(localized: "Name, Farbe, Symbol, Stundensatz und Archiv"))
            }
        }
        .sheet(item: $editingProject) { ProjectEditor(project: $0) }
        .sheet(item: $editingFolder) { FolderEditor(folder: $0) }
    }
}

struct OverviewView: View {
    let scope: EntryScope

    @Environment(TimerController.self) private var timer
    @Query(sort: \TimeEntry.start) private var allEntries: [TimeEntry]
    @State private var range: StatsRange = .all

    private struct Slice: Identifiable {
        let project: Project?
        let duration: TimeInterval
        var id: String { name }
        var name: String { project?.name ?? String(localized: "Ohne Projekt") }
        var color: Color { project?.color ?? .gray }
    }

    private struct DayBar: Identifiable {
        let day: Date
        let label: String
        let project: String
        let hours: Double
        var id: String { label + project }
    }

    var body: some View {
        let scoped = allEntries.filter { scope.contains($0, now: timer.now) }
        let interval = range.interval(now: timer.now, earliest: scoped.first?.start)
        let entries = scoped.filter { interval.contains($0.start) }
        let total = entries.reduce(0) { $0 + $1.duration(now: timer.now) }
        let days = Set(entries.map { Calendar.current.startOfDay(for: $0.start) }).sorted()
        let slices = makeSlices(entries)

        VStack(alignment: .leading, spacing: 20) {
            HStack(alignment: .top, spacing: 24) {
                VStack(alignment: .leading, spacing: 16) {
                    header
                    figures(entries: entries, slices: slices, activeDays: days.count, total: total)
                    // Das Budget zählt immer alle Zeiten, unabhängig vom gewählten Zeitraum.
                    if let budgeted, budgeted.budgetHours != nil {
                        BudgetBar(item: budgeted, now: timer.now)
                            .frame(maxWidth: 520)
                    }
                    ToolTotalsView(entries: entries, now: timer.now, limit: 5)
                        .frame(maxWidth: 520)
                }
                Spacer(minLength: 0)
                if !slices.isEmpty {
                    donut(slices, total: total)
                }
            }

            if entries.isEmpty {
                ContentUnavailableView(
                    "Keine Zeiten in diesem Zeitraum",
                    systemImage: "chart.bar",
                    description: Text(emptyHint)
                )
                .frame(maxHeight: .infinity)
            } else {
                barChart(makeBars(entries), slices: slices, dayCount: days.count)
                    .frame(minHeight: 260, maxHeight: .infinity)
            }
        }
        .padding(28)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .navigationTitle(scope.title)
        .navigationSubtitle("")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Picker("Zeitraum", selection: $range) {
                    ForEach(StatsRange.allCases) { Text($0.title).tag($0) }
                }
                .pickerStyle(.menu)
                .help("Zeitraum wählen")
            }
        }
    }

    private var budgeted: (any Budgeted)? {
        switch scope {
        case .project(let project): project
        case .folder(let folder): folder
        default: nil
        }
    }

    private var emptyHint: String {
        switch scope {
        case .folder: String(localized: "Leg ein Projekt in diesem Ordner an und starte den Timer, oder wähl oben einen längeren Zeitraum.")
        default: String(localized: "Starte den Timer für dieses Projekt, oder wähl oben einen längeren Zeitraum.")
        }
    }

    // MARK: - Kopf

    @ViewBuilder
    private var header: some View {
        switch scope {
        case .folder(let folder):
            Label {
                Text(folder.name)
            } icon: {
                Image(systemName: "folder.fill").foregroundStyle(folder.color)
            }
            .font(.system(size: 26, weight: .semibold))
        case .project(let project):
            Label {
                Text(project.name)
            } icon: {
                ProjectIcon(project: project, size: 22)
            }
            .font(.system(size: 26, weight: .semibold))
        default:
            Text(scope.title).font(.system(size: 26, weight: .semibold))
        }
    }

    private func figures(entries: [TimeEntry], slices: [Slice], activeDays: Int, total: TimeInterval) -> some View {
        let first: (String, String) = if case .folder = scope {
            (String(localized: "Aktive Projekte"), "\(slices.count)")
        } else {
            (String(localized: "Einträge"), "\(entries.count)")
        }
        let items = [
            first,
            (String(localized: "Aktive Tage"), "\(activeDays)"),
            (String(localized: "Gesamtzeit"), Fmt.clock(total, seconds: false, padHours: true)),
            (String(localized: "Ø pro Tag"), activeDays == 0 ? "–" : Fmt.clock(total / Double(activeDays), seconds: false, padHours: true)),
        ]
        return HStack(spacing: 0) {
            ForEach(Array(items.enumerated()), id: \.offset) { index, item in
                if index > 0 { Divider().frame(height: 40) }
                VStack(alignment: .leading, spacing: 4) {
                    Text(item.0)
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.secondary)
                    Text(item.1)
                        .font(.system(size: 26, weight: .semibold, design: .rounded))
                        .monospacedDigit()
                        .contentTransition(.numericText())
                }
                .padding(.horizontal, 18)
                .padding(.vertical, 12)
            }
        }
        .background(.quaternary.opacity(0.6), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    // MARK: - Ring

    private func donut(_ slices: [Slice], total: TimeInterval) -> some View {
        func share(_ slice: Slice) -> String {
            (total > 0 ? slice.duration / total : 0).formatted(.percent.precision(.fractionLength(0)))
        }
        return VStack(alignment: .center, spacing: 14) {
            Chart(slices) { slice in
                SectorMark(
                    angle: .value("Dauer", slice.duration),
                    innerRadius: .ratio(Self.innerRatio),
                    angularInset: 1.5
                )
                .cornerRadius(4)
                .foregroundStyle(slice.color)
            }
            // Anteile genau in die Mitte jedes Segments setzen, bei sehr schmalen Segmenten weglassen.
            .chartOverlay { proxy in
                GeometryReader { geometry in
                    if let plot = proxy.plotFrame.map({ geometry[$0] }), total > 0 {
                        let center = CGPoint(x: plot.midX, y: plot.midY)
                        let outer = min(plot.width, plot.height) / 2
                        let radius = outer * (1 + Self.innerRatio) / 2
                        ForEach(Self.midAngles(slices, total: total), id: \.slice.id) { item in
                            if item.slice.duration / total >= 0.06 {
                                Text(share(item.slice))
                                    .font(.system(size: 12, weight: .bold, design: .rounded))
                                    .monospacedDigit()
                                    .foregroundStyle(.white)
                                    .shadow(color: .black.opacity(0.3), radius: 1, y: 0.5)
                                    .fixedSize()
                                    .position(
                                        x: center.x + radius * sin(item.angle),
                                        y: center.y - radius * cos(item.angle)
                                    )
                            }
                        }
                    }
                }
            }
            .chartBackground { _ in
                VStack(spacing: 1) {
                    Text(Fmt.clock(total, seconds: false, padHours: true))
                        .font(.system(size: 17, weight: .semibold, design: .rounded))
                    Text("gesamt")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .monospacedDigit()
            }
            .frame(width: 190, height: 190)

            VStack(alignment: .leading, spacing: 5) {
                ForEach(slices) { slice in
                    HStack(spacing: 6) {
                        ProjectIcon(project: slice.project, size: 11)
                        Text(slice.name).lineLimit(1)
                        Spacer(minLength: 10)
                        Text(share(slice))
                            .foregroundStyle(.secondary)
                            .frame(width: 38, alignment: .trailing)
                        Text(Fmt.clock(slice.duration, seconds: false, padHours: true))
                            .frame(width: 44, alignment: .trailing)
                    }
                    .font(.callout)
                    .monospacedDigit()
                }
            }
            .frame(width: 250)
        }
    }

    private static let innerRatio = 0.52

    /// Winkel der Segmentmitte im Bogenmaß, im Uhrzeigersinn ab 12 Uhr wie in Swift Charts.
    private static func midAngles(_ slices: [Slice], total: TimeInterval) -> [(slice: Slice, angle: Double)] {
        var start = 0.0
        return slices.map { slice in
            let sweep = slice.duration / total * 2 * .pi
            defer { start += sweep }
            return (slice, start + sweep / 2)
        }
    }

    // MARK: - Balken

    private func barChart(_ bars: [DayBar], slices: [Slice], dayCount: Int) -> some View {
        let labels = Array(NSOrderedSet(array: bars.sorted { $0.day < $1.day }.map(\.label))) as! [String]
        // Bei vielen Tagen nur jede n-te Beschriftung zeigen, damit nichts überlappt.
        let step = max(1, Int((Double(labels.count) / 12).rounded(.up)))
        let shownLabels = labels.enumerated().filter { $0.offset % step == 0 }.map(\.element)

        return Chart(bars) { bar in
            BarMark(
                x: .value("Tag", bar.label),
                y: .value("Stunden", bar.hours),
                width: .ratio(dayCount < 4 ? 0.4 : 0.82)
            )
            .foregroundStyle(by: .value("Projekt", bar.project))
            .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
        }
        .chartForegroundStyleScale(domain: slices.map(\.name), range: slices.map(\.color))
        .chartLegend(.hidden)
        .chartXScale(domain: labels, range: .plotDimension(startPadding: 28, endPadding: 28))
        .chartXAxis {
            AxisMarks(values: shownLabels) { value in
                AxisValueLabel {
                    if let label = value.as(String.self) {
                        let parts = label.split(separator: "\n")
                        VStack(spacing: 1) {
                            Text(parts.first.map(String.init) ?? "")
                            Text(parts.last.map(String.init) ?? "").foregroundStyle(.secondary)
                        }
                        .font(.caption)
                        .monospacedDigit()
                    }
                }
            }
        }
        .chartYAxis {
            AxisMarks(position: .leading) { value in
                AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5))
                AxisValueLabel {
                    if let hours = value.as(Double.self) { Text("\(Int(hours)) h") }
                }
            }
        }
    }

    // MARK: - Daten

    private func makeSlices(_ entries: [TimeEntry]) -> [Slice] {
        Dictionary(grouping: entries) { $0.project?.persistentModelID }
            .values
            .map { group in Slice(project: group.first?.project, duration: group.reduce(0) { $0 + $1.duration(now: timer.now) }) }
            .sorted { $0.duration > $1.duration }
    }

    private func makeBars(_ entries: [TimeEntry]) -> [DayBar] {
        let cal = Calendar.current
        var sums: [Date: [String: TimeInterval]] = [:]
        for entry in entries {
            sums[cal.startOfDay(for: entry.start), default: [:]][entry.project?.name ?? String(localized: "Ohne Projekt"), default: 0] += entry.duration(now: timer.now)
        }
        return sums.flatMap { day, byProject in
            let label = Fmt.shortDate(day) + "\n" + day.formatted(.dateTime.weekday(.abbreviated).locale(Fmt.locale))
            return byProject.map { DayBar(day: day, label: label, project: $0.key, hours: $0.value / 3600) }
        }
    }
}
