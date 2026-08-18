import SwiftUI

struct EntityListSectionHeader: View {
    @Environment(\.bochiTheme) private var theme
    @Environment(\.entityListColorStrategy) private var colorStrategy

    let title: String
    var role: BochiThemeRole = .neutral

    var body: some View {
        Text(title)
            .font(.body.weight(.bold))
            .foregroundStyle(colorStrategy.primaryText(for: .neutral, theme: theme))
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.top, 10)
            .padding(.trailing, 16)
            .padding(.bottom, 6)
            .textCase(nil)
    }
}
