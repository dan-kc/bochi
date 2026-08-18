import Foundation

// Small enum that lets the same tags UI work for either feature without
// introducing a generic store protocol hierarchy.
enum TagAssignmentTarget: Equatable {
    case task(RecordID)
    case recurringTask(RecordID)
    case reward(RecordID)

    var entityId: RecordID {
        switch self {
        case .task(let id), .recurringTask(let id), .reward(let id):
            return id
        }
    }
}
