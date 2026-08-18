import Foundation

enum EarnListFilterSupport {
    static func toggleTaskGroup(in preferences: inout EntityListPreferences) {
        toggleHiddenStatus(.task, in: &preferences)
    }

    static func toggleTaskCompletion(
        _ status: EntityListStatusFilter,
        in preferences: inout EntityListPreferences
    ) {
        guard status == .completed || status == .incomplete else { return }

        if preferences.hiddenStatusFilters.contains(.task) {
            preferences.hiddenStatusFilters.removeAll { $0 == .task }
            return
        }

        toggleHiddenStatus(status, in: &preferences)
    }

    static func toggleHiddenStatus(
        _ status: EntityListStatusFilter,
        in preferences: inout EntityListPreferences
    ) {
        if let index = preferences.hiddenStatusFilters.firstIndex(of: status) {
            preferences.hiddenStatusFilters.remove(at: index)
        } else {
            preferences.hiddenStatusFilters.append(status)
            preferences.hiddenStatusFilters.sort { $0.rawValue < $1.rawValue }
        }
    }

}
