import Foundation

// Sync flow: reconciliation uses these owner-scoped merge helpers to replace
// server snapshots while preserving selected local records.
// These helpers keep the owner-scoped JSON stores consistent without forcing
// the app into a single giant generic repository type. Each concrete store
// still owns its API and domain rules, but the repeated merge/sort/normalize
// mechanics live in one place.
protocol OwnerScopedRecord: Identifiable, Equatable {
    var id: RecordID { get }
    var createdAt: Date { get }
    var updatedAt: Date { get }
}

enum OwnerScopedRecordSupport {
    static func recordsForOwner<Record>(
        _ recordsByOwner: [String: [Record]],
        ownerID: String
    ) -> [Record] {
        recordsByOwner[ownerID] ?? []
    }

    static func migrateRecords<Record: OwnerScopedRecord>(
        from sourceOwnerID: String,
        to destinationOwnerID: String,
        recordsByOwner: inout [String: [Record]]
    ) -> [RecordID] {
        guard sourceOwnerID != destinationOwnerID else { return [] }

        let source = recordsByOwner[sourceOwnerID] ?? []
        let destination = recordsByOwner[destinationOwnerID] ?? []
        recordsByOwner[destinationOwnerID] = mergeRecords(local: destination, remote: source)
        recordsByOwner[sourceOwnerID] = []
        return source.map(\.id)
    }

    static func mutateRecords<Record: OwnerScopedRecord>(
        currentRecords: [Record],
        ownerID: String,
        recordsByOwner: inout [String: [Record]],
        mutate: (inout [Record]) -> Void
    ) -> [Record] {
        var next = currentRecords
        mutate(&next)
        next = sorted(next)
        recordsByOwner[ownerID] = next
        return next
    }

    static func mergeRecords<Record: OwnerScopedRecord>(
        local: [Record],
        remote: [Record]
    ) -> [Record] {
        var mergedByID = Dictionary(uniqueKeysWithValues: local.map { ($0.id, $0) })

        for incoming in remote {
            if let existing = mergedByID[incoming.id], existing.updatedAt > incoming.updatedAt {
                continue
            }

            mergedByID[incoming.id] = incoming
        }

        return sorted(Array(mergedByID.values))
    }

    static func applyingAuthoritativeRecords<Record: OwnerScopedRecord>(
        local: [Record],
        remote: [Record]
    ) -> [Record] {
        var recordsByID = Dictionary(uniqueKeysWithValues: local.map { ($0.id, $0) })

        for incoming in remote {
            recordsByID[incoming.id] = incoming
        }

        return sorted(Array(recordsByID.values))
    }

    static func normalizePersistedRecords<Record: OwnerScopedRecord>(
        _ recordsByOwner: [String: [Record]],
        canonicalize: (Record) -> Record
    ) -> [String: [Record]] {
        Dictionary(uniqueKeysWithValues: recordsByOwner.map { ownerID, records in
            (ownerID, normalizeRecords(records, canonicalize: canonicalize))
        })
    }

    static func normalizeRecords<Record: OwnerScopedRecord>(
        _ records: [Record],
        canonicalize: (Record) -> Record
    ) -> [Record] {
        var newestByID: [RecordID: Record] = [:]

        for record in records {
            let canonicalRecord = canonicalize(record)

            if let existing = newestByID[canonicalRecord.id], existing.updatedAt > canonicalRecord.updatedAt {
                continue
            }

            newestByID[canonicalRecord.id] = canonicalRecord
        }

        return sorted(Array(newestByID.values))
    }

    static func sorted<Record: OwnerScopedRecord>(_ records: [Record]) -> [Record] {
        records.sorted { lhs, rhs in
            if lhs.createdAt == rhs.createdAt {
                return lhs.id.rawValue < rhs.id.rawValue
            }

            return lhs.createdAt < rhs.createdAt
        }
    }
}
