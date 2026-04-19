import Foundation
import Testing
@testable import tofustash

struct OwnerScopedRecordSupportTests {
    private struct TestRecord: OwnerScopedRecord {
        let id: RecordID
        let createdAt: Date
        let updatedAt: Date
        let payload: String
    }

    // Behaviour: when a signed-in user migrates local data into their account,
    // the newest version of each record should win instead of duplicating rows.
    @Test func migrateRecordsMergesAndReturnsMigratedIDs() {
        let createdAt = Date(timeIntervalSince1970: 100)
        let older = TestRecord(id: "shared", createdAt: createdAt, updatedAt: Date(timeIntervalSince1970: 200), payload: "older")
        let newer = TestRecord(id: "shared", createdAt: createdAt, updatedAt: Date(timeIntervalSince1970: 300), payload: "newer")

        var recordsByOwner: [String: [TestRecord]] = [
            "local": [newer],
            "user": [older]
        ]

        let migratedIDs = OwnerScopedRecordSupport.migrateRecords(
            from: "local",
            to: "user",
            recordsByOwner: &recordsByOwner
        )

        #expect(migratedIDs == ["shared"])
        #expect(recordsByOwner["local"] == [])
        #expect(recordsByOwner["user"]?.map(\.payload) == ["newer"])
    }

    // Behaviour: normalized persisted data should keep a stable row order so
    // the list does not appear to reshuffle after reload.
    @Test func normalizePersistedRecordsCanonicalizesIDsAndSortsStably() {
        let first = TestRecord(id: RecordID(rawValue: "B"), createdAt: Date(timeIntervalSince1970: 10), updatedAt: Date(timeIntervalSince1970: 10), payload: "first")
        let second = TestRecord(id: RecordID(rawValue: "A"), createdAt: Date(timeIntervalSince1970: 10), updatedAt: Date(timeIntervalSince1970: 11), payload: "second")

        let normalized = OwnerScopedRecordSupport.normalizePersistedRecords(
            ["owner": [first, second]]
        ) { record in
            TestRecord(
                id: RecordID(rawValue: record.id.rawValue),
                createdAt: record.createdAt,
                updatedAt: record.updatedAt,
                payload: record.payload
            )
        }

        #expect(normalized["owner"]?.map(\.id.rawValue) == ["a", "b"])
    }

    // Behaviour: sortable action amounts should disappear for incomplete rows
    // so list sorting only compares actionable entities.
    @Test func sortableAmountReturnsNilWhenEntityCannotAct() {
        #expect(EntityActionSupport.sortableAmount(isActionable: false) { 42 } == nil)
        #expect(EntityActionSupport.sortableAmount(isActionable: true) { 42 } == 42)
    }
}
