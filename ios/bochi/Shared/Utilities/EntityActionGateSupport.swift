import Foundation

nonisolated enum EntityActionGateReason: Equatable, Identifiable {
    case locked(summary: String?)
    case hidden

    var id: String {
        switch self {
        case .locked(let summary):
            return "locked:\(summary ?? "")"
        case .hidden:
            return "hidden"
        }
    }

    func actionTitle(defaultTitle: String) -> String {
        switch self {
        case .locked:
            return "Locked"
        case .hidden:
            return "Hidden"
        }
    }

    func message(entityName: String, actionName: String) -> String {
        switch self {
        case .locked(let summary):
            if let summary {
                return "\(entityName) is locked for \(summary). Claiming it now skips the boundary you set for yourself."
            }
            return "\(entityName) is locked because its requirements are not finished. Claiming it now skips the boundary you set for yourself."
        case .hidden:
            return "\(entityName) is hidden, which usually means you wanted it out of the way. Claiming it now may make that easier to ignore."
        }
    }
}

nonisolated enum EntityActionGateSupport {
    static func reason(
        isLocked: Bool,
        lockoutSummary: String? = nil,
        isHidden: Bool
    ) -> EntityActionGateReason? {
        if isLocked {
            return .locked(summary: lockoutSummary)
        }

        if isHidden {
            return .hidden
        }

        return nil
    }

    static func actionTitle(
        defaultTitle: String,
        reason: EntityActionGateReason?
    ) -> String {
        reason?.actionTitle(defaultTitle: defaultTitle) ?? defaultTitle
    }
}
