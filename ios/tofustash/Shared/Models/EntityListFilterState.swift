import SwiftUI

struct EntityListSearchState: Equatable, Sendable {
    // Behaviour: each entity tab owns its own transient search session so a
    // user can move around the app or open sheets without losing that tab's
    // in-progress query and expanded search chrome.
    var text = ""
    var isPresented = false

    var trimmedText: String {
        text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var hasQuery: Bool {
        !trimmedText.isEmpty
    }
}

struct EntityListFilterState: Equatable, Sendable {
    let preferences: EntityListPreferences
    let search: EntityListSearchState
}

enum EntityListSearchChrome {
    static let animation = Animation.spring(response: 0.32, dampingFraction: 0.86)

    static func present(_ state: inout EntityListSearchState) {
        withAnimation(animation) {
            state.isPresented = true
        }
    }

    static func collapse(_ state: inout EntityListSearchState, clearText: Bool = true) {
        if clearText {
            state.text = ""
        } else {
            state.text = state.trimmedText
        }

        withAnimation(animation) {
            state.isPresented = false
        }
    }
}
