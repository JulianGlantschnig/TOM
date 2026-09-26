import SwiftUI

/// Symbol eines Projekts in seiner Farbe, ohne Symbol ein Farbpunkt.
/// Die Breite ist immer gleich, damit Namen daneben bündig stehen.
struct ProjectIcon: View {
    let project: Project?
    var size: CGFloat = 13

    var body: some View {
        let color = project?.color ?? .secondary
        Group {
            if let name = project?.iconName {
                Image(systemName: name)
                    .font(.system(size: size, weight: .medium))
                    .foregroundStyle(color)
            } else {
                Circle()
                    .fill(color)
                    .frame(width: size * 0.7, height: size * 0.7)
            }
        }
        .frame(width: size * 1.4)
    }
}
