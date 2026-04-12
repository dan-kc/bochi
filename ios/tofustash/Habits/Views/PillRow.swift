import SwiftUI

// A horizontal row of tappable pill buttons — like a flexWrap row of chips
// or a horizontal ScrollView of filter buttons in React Native.
//
// Each pill can be "set" (orange tint) or "unset" (secondary/gray).
// Used for the form's action row: Tags, Difficulty, Frequency.
struct PillRow: View {
    let pills: [PillItem]

    var body: some View {
        // ScrollView(.horizontal) is like overflow-x: auto with flex-direction: row.
        // showsIndicators: false hides the scroll bar.
        ScrollView(.horizontal, showsIndicators: false) {
            // HStack is a horizontal flex container — like flexDirection: "row".
            HStack(spacing: 8) {
                ForEach(pills) { pill in
                    Button {
                        pill.action?()
                    } label: {
                        Label(pill.label, systemImage: pill.icon)
                            .font(.subheadline)
                    }
                    // .bordered gives a pill/chip-like background shape.
                    // .tint sets the color — orange when the field is set.
                    .buttonStyle(.bordered)
                    .tint(pill.isSet ? .orange : .secondary)
                }
            }
        }
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
