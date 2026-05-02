import SwiftUI

struct SpecialOfferMetaPill: View {
    let offer: SpecialOffer

    var body: some View {
        EntityListMetaPill(
            text: SpecialOfferSupport.badgeText(modifierPercent: offer.modifierPercent),
            isSet: true
        )
    }
}

struct SpecialOfferCaption: View {
    let offer: SpecialOffer

    var body: some View {
        Text(SpecialOfferSupport.badgeText(modifierPercent: offer.modifierPercent))
            .font(.footnote)
            .foregroundStyle(.orange)
    }
}

struct SpecialOfferAmountSummary: View {
    let title: String
    let amount: Int
    let amountColor: Color
    let offer: SpecialOffer?

    init(
        title: String,
        amount: Int,
        amountColor: Color = .primary,
        offer: SpecialOffer? = nil
    ) {
        self.title = title
        self.amount = amount
        self.amountColor = amountColor
        self.offer = offer
    }

    var body: some View {
        VStack(spacing: 4) {
            Text(title)
                .font(.subheadline)
                .foregroundStyle(.secondary)

            HStack(spacing: 4) {
                Text("\(amount)")
                    .font(.title)
                    .fontWeight(.bold)
                    .contentTransition(.numericText())
                Image(systemName: "cube.fill")
            }
            .foregroundStyle(amountColor)

            if let offer {
                SpecialOfferCaption(offer: offer)
            }
        }
        .padding(.top, 8)
    }
}
