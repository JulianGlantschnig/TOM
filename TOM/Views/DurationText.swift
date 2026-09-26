import SwiftUI

/// Große Dauer wie „10h 05min“: Einheit klein und dicht an der Zahl, dafür deutlich Luft zwischen Stunden und Minuten.
struct DurationText: View {
    let interval: TimeInterval
    var size: CGFloat = 26

    var body: some View {
        let minutes = max(0, Int(interval)) / 60
        let h = minutes / 60, m = minutes % 60
        HStack(alignment: .firstTextBaseline, spacing: size * 0.32) {
            if h > 0 {
                group("\(h)", "h")
                group(String(format: "%02d", m), "min")
            } else {
                group("\(m)", "min")
            }
        }
        .monospacedDigit()
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Fmt.hoursMinutes(interval))
    }

    private func group(_ number: String, _ unit: String) -> Text {
        Text(number)
            .font(.system(size: size, weight: .semibold, design: .rounded))
            .tracking(-size * 0.03)
        + Text(verbatim: unit)
            .font(.system(size: size * 0.52, weight: .medium, design: .rounded))
            .foregroundStyle(.secondary)
    }
}
