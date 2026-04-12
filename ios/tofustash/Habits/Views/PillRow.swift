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
                        pill.action()
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
struct PillItem: Identifiable {
    let id: String
    let label: String
    let icon: String          // SF Symbol name (like Material Icon names in React)
    let isSet: Bool           // true = orange, false = gray
    let action: () -> Void    // called when tapped — like onClick in React
}

// Pure data version of PillItem (no closure) for unit testing pill-building logic.
// In React terms, this separates the "what to render" data from the "what to do on click"
// handler, so the data part can be tested without needing a UI.
struct PillItemData: Identifiable {
    let id: String
    let label: String
    let icon: String
    let isSet: Bool
}
