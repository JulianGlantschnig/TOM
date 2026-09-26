import Charts
import SwiftData
import SwiftUI

/// Ordner oder Projekt: Umschalter zwischen Diagramm und Tabelle, wie in Tim.
struct ScopeDetailView: View {
    enum Mode: Hashable { case chart, list }

    let scope: EntryScope
    @State private var mode: Mode

    init(scope: EntryScope) {
        self.scope = scope
        if case .folder = scope { _mode = State(initialValue: .chart) } else { _mode = State(initialValue: .list) }
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
                    Label("Einträge", systemImage: "list.bullet").tag(Mode.list)
                }
                .pickerStyle(.segmented)
                .labelStyle(.iconOnly)
                .help("Zwischen Diagramm und Einträgen wechseln")
            }
        }
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
        var name: String { project?.name ?? "Ohne Projekt" }
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
                    ForEach(StatsRange.allCases) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.menu)
                .help("Zeitraum wählen")
            }
        }
    }

    private var emptyHint: String {
        switch scope {
        case .folder: "Leg ein Projekt in diesem Ordner an und starte den Timer, oder wähl oben einen längeren Zeitraum."
        default: "Starte den Timer für dieses Projekt, oder wähl oben einen längeren Zeitraum."
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
            ("Aktive Projekte", "\(slices.count)")
        } else {
            ("Einträge", "\(entries.count)")
        }
        let items = [
            first,
            ("Aktive Tage", "\(activeDays)"),
            ("Gesamtzeit", Fmt.clock(total, seconds: false, padHours: true)),
            ("Ø pro Tag", activeDays == 0 ? "–" : Fmt.clock(total / Double(activeDays), seconds: false, padHours: true)),
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
                    innerRadius: .ratio(0.52),
                    angularInset: 1.5
                )
                .cornerRadius(4)
                .foregroundStyle(slice.color)
                // Anteil direkt ins Segment schreiben, bei sehr schmalen Segmenten weglassen.
                .annotation(position: .overlay) {
                    if total > 0, slice.duration / total >= 0.06 {
                        Text(share(slice))
                            .font(.system(size: 12, weight: .bold, design: .rounded))
                            .monospacedDigit()
                            .foregroundStyle(.white)
                            .shadow(color: .black.opacity(0.25), radius: 1, y: 0.5)
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
            sums[cal.startOfDay(for: entry.start), default: [:]][entry.project?.name ?? "Ohne Projekt", default: 0] += entry.duration(now: timer.now)
        }
        return sums.flatMap { day, byProject in
            let label = Fmt.shortDate(day) + "\n" + day.formatted(.dateTime.weekday(.abbreviated).locale(Fmt.locale))
            return byProject.map { DayBar(day: day, label: label, project: $0.key, hours: $0.value / 3600) }
        }
    }
}
