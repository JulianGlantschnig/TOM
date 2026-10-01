import SwiftUI

/// Wie viel vom vereinbarten Budget schon verbraucht ist. Ab der Vorwarnung orange, ab dem Budget rot.
struct BudgetBar: View {
    let project: Project
    let now: Date
    var compact = false

    var body: some View {
        if let budget = project.budgetHours, budget > 0 {
            let total = project.totalTime(now: now)
            let share = total / (budget * 3600)
            let color: Color = switch project.budgetLevel(now: now) {
            case 2: .red
            case 1: .orange
            default: project.color
            }
            VStack(alignment: .leading, spacing: compact ? 4 : 6) {
                HStack(alignment: .firstTextBaseline) {
                    if !compact {
                        Text("Budget")
                            .font(.caption.weight(.medium))
                            .foregroundStyle(.secondary)
                    }
                    Text("\(Fmt.hoursMinutes(total)) von \(Fmt.budgetHours(budget))")
                        .foregroundStyle(compact ? .secondary : .primary)
                    Spacer(minLength: 8)
                    Text(share >= 1
                        ? String(localized: "\(Fmt.hoursMinutes(total - budget * 3600)) drüber")
                        : String(localized: "noch \(Fmt.hoursMinutes(budget * 3600 - total))"))
                        .foregroundStyle(share >= 1 ? Color.red : Color.secondary)
                }
                .font(compact ? .caption : .callout)
                .monospacedDigit()

                GeometryReader { geometry in
                    ZStack(alignment: .leading) {
                        Capsule().fill(.quaternary)
                        Capsule()
                            .fill(color)
                            .frame(width: geometry.size.width * min(share, 1))
                        if let warn = project.budgetWarnHours, warn < budget {
                            Rectangle()
                                .fill(.primary.opacity(0.35))
                                .frame(width: 1.5)
                                .offset(x: geometry.size.width * warn / budget)
                                .help(String(localized: "Vorwarnung bei \(Fmt.budgetHours(warn))"))
                        }
                    }
                }
                .frame(height: compact ? 4 : 8)
                .clipShape(Capsule())
            }
            .animation(.default, value: share >= 1)
        }
    }
}
