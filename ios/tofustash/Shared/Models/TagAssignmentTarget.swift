import Foundation

// Small enum that lets the same tags UI work for either feature without
// introducing a generic store protocol hierarchy.
enum TagAssignmentTarget: Equatable {
    case habit(String)
    case reward(String)

    var entityId: String {
        switch self {
        case .habit(let id), .reward(let id):
            return id
        }
    }
}
