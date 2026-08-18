import Foundation
import SwiftUI

@Observable
@MainActor
final class OmniSearchStore {
    static let animation = Animation.spring(response: 0.32, dampingFraction: 0.86)
    static let collapseClearDelay: Duration = .milliseconds(340)

    var text = ""
    var isPresented = false
    var preferences = EntityListPreferences(hiddenStatusFilters: [.completed])

    var trimmedText: String {
        text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    init() {
        Task.detached(priority: .utility) {
            OmniSearchSupport.warmUpMatcher()
        }
    }

    func present() {
        withAnimation(Self.animation) {
            isPresented = true
        }
    }

    func collapse() {
        withAnimation(Self.animation) {
            isPresented = false
        }

        Task { @MainActor [weak self] in
            try? await Task.sleep(for: Self.collapseClearDelay)
            guard let self, !self.isPresented else { return }
            self.text = ""
        }
    }

    func toggleStatus(_ status: EntityListStatusFilter) {
        withAnimation(.default) {
            if let index = preferences.hiddenStatusFilters.firstIndex(of: status) {
                preferences.hiddenStatusFilters.remove(at: index)
            } else {
                preferences.hiddenStatusFilters.append(status)
                preferences.hiddenStatusFilters.sort { $0.rawValue < $1.rawValue }
            }
        }
    }

    func toggleTag(_ tagID: RecordID) {
        withAnimation(.default) {
            if let index = preferences.hiddenTagIDs.firstIndex(of: tagID) {
                preferences.hiddenTagIDs.remove(at: index)
            } else {
                preferences.hiddenTagIDs.append(tagID)
                preferences.hiddenTagIDs.sort { $0.rawValue < $1.rawValue }
            }
        }
    }
}
