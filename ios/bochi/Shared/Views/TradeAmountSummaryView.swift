import SwiftUI

struct TradeAmountSummaryView: View {
    var title: String? = nil
    let amount: Int
    var polarity: BochiActionButton.Polarity? = nil
    let amountColor: Color
    let titleColor: Color
    var originalAmount: Int? = nil
    var adjustmentCaptions: [String] = []

    var body: some View {
        VStack(spacing: 8) {
            if let title, !title.isEmpty {
                Text(title)
                    .font(.subheadline)
                    .foregroundStyle(titleColor)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }

            PointsAmountLabel(text: amountText(for: amount), iconSize: 52)
                .font(.system(size: 64, weight: .bold, design: .rounded))
                .foregroundStyle(amountColor)
                .contentTransition(.numericText())

            if let originalAmount {
                PointsAmountLabel(text: "Base \(amountText(for: originalAmount))", iconSize: 13)
                    .font(.caption)
                    .foregroundStyle(titleColor)
            }

            ForEach(adjustmentCaptions, id: \.self) { caption in
                Text(caption)
                    .font(.caption)
                    .foregroundStyle(titleColor)
            }
        }
        .frame(maxWidth: .infinity)
    }

    private func amountText(for amount: Int) -> String {
        guard let polarity else { return "\(amount)" }
        return "\(polarity.prefix)\(abs(amount))"
    }
}
