import Charts
import SwiftData
import SwiftUI

enum StatsRange: String, CaseIterable, Identifiable {
    case week = "Diese Woche"
    case last30 = "Letzte 30 Tage"
    case month = "Dieser Monat"
    case year = "Dieses Jahr"
    case all = "Gesamt"

    var id: Self { self }

    func interval(now: Date, earliest: Date?) -> DateInterval {
        let cal = Calendar.current
        let endOfToday = cal.date(byAdding: .day, value: 1, to: cal.startOfDay(for: now))!
        let start: Date = switch self {
        case .week: cal.startOfWeek(for: now)
        case .last30: cal.date(byAdding: .day, value: -29, to: cal.startOfDay(for: now))!
        case .month: cal.dateInterval(of: .month, for: now)!.start
        case .year: cal.dateInterval(of: .year, for: now)!.start
        case .all: cal.startOfDay(for: earliest ?? now)
        }
        return DateInterval(start: start, end: max(endOfToday, start))
    }
}

struct StatsView: View {
    @Environment(TimerController.self) private var timer
    @Query(sort: \TimeEntry.start) private var allEntries: [TimeEntry]
    @State private var range: StatsRange = .last30

    private struct Bucket: Identifiable {
        let date: Date
        let project: String
        let hours: Double
        var id: String { "\(date.timeIntervalSince1970)-\(project)" }
    }

    private struct ProjectTotal: Identifiable {
        let project: Project?
        let duration: TimeInterval
        var id: String { project?.persistentModelID.hashValue.description ?? "none" }
        var name: String { project?.name ?? "Ohne Projekt" }
        var amount: Double? { project?.hourlyRate.map { $0 * duration / 3600 } }
    }

    var body: some View {
        let interval = range.interval(now: timer.now, earliest: allEntries.first?.start)
        let entries = allEntries.filter { interval.contains($0.start) }
        let total = entries.reduce(0) { $0 + $1.duration(now: timer.now) }
        let workDays = Set(entries.map { Calendar.current.startOfDay(for: $0.start) }).count
        let unit = bucketUnit(for: interval)
        let buckets = makeBuckets(entries, unit: unit)
        let totals = projectTotals(entries)
        let amount = totals.compactMap(\.amount).reduce(0, +)

        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                HStack(alignment: .firstTextBaseline, spacing: 40) {
                    figure(Fmt.hoursMinutes(total), "erfasst")
                    figure(workDays == 0 ? "–" : Fmt.hoursMinutes(total / Double(workDays)), "pro Arbeitstag")
                    figure("\(workDays)", workDays == 1 ? "Arbeitstag" : "Arbeitstage")
                    if amount > 0 {
                        figure(Fmt.money(amount), "verrechenbar")
                    }
                }

                if entries.isEmpty {
                    ContentUnavailableView(
                        "Keine Zeiten in diesem Zeitraum",
                        systemImage: "chart.bar",
                        description: Text("Wähl oben einen längeren Zeitraum.")
                    )
                    .frame(height: 260)
                } else {
                    Chart(buckets) { bucket in
                        BarMark(
                            x: .value("Zeitraum", bucket.date, unit: unit),
                            y: .value("Stunden", bucket.hours)
                        )
                        .foregroundStyle(by: .value("Projekt", bucket.project))
                    }
                    .chartForegroundStyleScale(
                        domain: totals.map(\.name),
                        range: totals.map { $0.project?.color ?? .gray }
                    )
                    .chartYAxisLabel("Stunden")
                    .chartLegend(.hidden)
                    .frame(height: 260)

                    let longest = totals.first?.duration ?? 0
                    VStack(spacing: 0) {
                        ForEach(totals) { item in
                            projectLine(
                                item,
                                share: total > 0 ? item.duration / total : 0,
                                barFraction: longest > 0 ? item.duration / longest : 0,
                                showsAmountColumn: amount > 0
                            )
                            if item.id != totals.last?.id { Divider() }
                        }
                    }
                }
            }
            .padding(28)
            .frame(maxWidth: 900, alignment: .leading)
        }
        .navigationTitle("Auswertung")
        .toolbar {
            Picker("Zeitraum", selection: $range) {
                ForEach(StatsRange.allCases) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.menu)
        }
    }

    private func figure(_ value: String, _ label: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value)
                .font(.system(size: 26, weight: .semibold, design: .rounded))
                .monospacedDigit()
            Text(label)
                .font(.callout)
                .foregroundStyle(.secondary)
        }
    }

    private func projectLine(_ item: ProjectTotal, share: Double, barFraction: Double, showsAmountColumn: Bool) -> some View {
        let color = item.project?.color ?? .gray
        return HStack(spacing: 12) {
            ProjectIcon(project: item.project, size: 13)
            Text(item.name).frame(width: 220, alignment: .leading).lineLimit(1)
            GeometryReader { proxy in
                Capsule()
                    .fill(color.opacity(0.85))
                    .frame(width: max(4, proxy.size.width * barFraction), height: 6)
                    .frame(maxHeight: .infinity)
            }
            .frame(height: 20)
            Text(share.formatted(.percent.precision(.fractionLength(0))))
                .foregroundStyle(.secondary)
                .frame(width: 44, alignment: .trailing)
            Text(Fmt.hoursMinutes(item.duration))
                .frame(width: 96, alignment: .trailing)
            if showsAmountColumn {
                Text(item.amount.map(Fmt.money) ?? "")
                    .foregroundStyle(.secondary)
                    .frame(width: 110, alignment: .trailing)
            }
        }
        .monospacedDigit()
        .padding(.vertical, 8)
    }

    private func bucketUnit(for interval: DateInterval) -> Calendar.Component {
        let days = interval.duration / 86_400
        if days <= 45 { return .day }
        if days <= 200 { return .weekOfYear }
        return .month
    }

    private func makeBuckets(_ entries: [TimeEntry], unit: Calendar.Component) -> [Bucket] {
        let cal = Calendar.current
        var sums: [Date: [String: TimeInterval]] = [:]
        for entry in entries {
            let key = cal.dateInterval(of: unit, for: entry.start)?.start ?? entry.start
            sums[key, default: [:]][entry.project?.name ?? "Ohne Projekt", default: 0] += entry.duration(now: timer.now)
        }
        return sums.flatMap { date, byProject in
            byProject.map { Bucket(date: date, project: $0.key, hours: $0.value / 3600) }
        }
    }

    private func projectTotals(_ entries: [TimeEntry]) -> [ProjectTotal] {
        let grouped = Dictionary(grouping: entries) { $0.project?.persistentModelID }
        return grouped.values
            .map { group in
                ProjectTotal(project: group.first?.project, duration: group.reduce(0) { $0 + $1.duration(now: timer.now) })
            }
            .sorted { $0.duration > $1.duration }
    }
}
