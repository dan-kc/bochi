import SwiftUI

struct PointsIcon: View {
    var size: CGFloat = 15

    var body: some View {
        Text("✦")
            .font(.system(size: size, weight: .semibold, design: .rounded))
            .lineLimit(1)
            .minimumScaleFactor(0.7)
            .frame(width: size, height: size)
            .accessibilityHidden(true)
    }
}

struct PointsAmountLabel: View {
    let text: String
    var iconSize: CGFloat = 15

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 0) {
            Text(text)
            PointsIcon(size: iconSize)
        }
        .fixedSize(horizontal: true, vertical: false)
        .accessibilityElement(children: .combine)
    }
}
