import SwiftUI

// A horizontal row of tappable pill buttons — like a flexWrap row of chips
// or a horizontal ScrollView of filter buttons in React Native.
//
// Each pill can be "set" (orange tint) or "unset" (secondary/gray).
// Used for the form's action row: Tags, Difficulty, Frequency.
struct PillRow: View {
    let pills: [PillItem]
    var leadingInset: CGFloat = 0

    var body: some View {
        // ScrollView(.horizontal) is like overflow-x: auto with flex-direction: row.
        // showsIndicators: false hides the scroll bar.
        ScrollView(.horizontal, showsIndicators: false) {
            // HStack is a horizontal flex container — like flexDirection: "row".
            HStack(spacing: 8) {
                ForEach(pills) { pill in
                    PillButton(pill: pill)
                }
            }
            .padding(.leading, leadingInset)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct PillButton: View {
    let pill: PillItem

    private var tintColor: Color {
        guard !pill.isSet else { return .orange }
        return .secondary
    }

    var body: some View {
        Button {
            pill.action?()
        } label: {
            Label(pill.label, systemImage: pill.icon)
                .font(.subheadline)
                .contentTransition(.identity)
        }
        .buttonStyle(.bordered)
        .tint(tintColor)
    }
}

// Represents a single pill in the row. Identifiable so ForEach can diff.
// `action` is optional so the same type works for both rendering (with action)
// and unit testing pill-building logic (without action). In React terms,
// this is like having an optional onClick prop on a button component.
struct PillItem: Identifiable {
    let id: String
    let label: String
    let icon: String          // SF Symbol name (like Material Icon names in React)
    let isSet: Bool           // true = orange, false = gray
    var action: (() -> Void)? = nil  // called when tapped — like onClick in React
}
