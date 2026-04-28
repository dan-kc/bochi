import Foundation

// Small enum that lets the same tags UI work for either feature without
// introducing a generic store protocol hierarchy.
enum TagAssignmentTarget: Equatable {
    case task(RecordID)
    case habit(RecordID)
    case reward(RecordID)

    var entityId: RecordID {
        switch self {
        case .task(let id), .habit(let id), .reward(let id):
            return id
        }
    }
}
