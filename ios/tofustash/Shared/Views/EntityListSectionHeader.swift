import SwiftUI

struct EntityListSectionHeader: View {
    let title: String

    var body: some View {
        Text(title)
            .font(.body.weight(.bold))
            .foregroundStyle(.black)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.top, 10)
            .padding(.trailing, 16)
            .padding(.bottom, 6)
            .textCase(nil)
    }
}
