import Foundation

@Observable
@MainActor
final class SpecialOfferStore {
    private let databaseURL: URL
    private let database = AppDatabase.shared

    private(set) var currentOwnerID: String
    private(set) var offers: [SpecialOffer] = []

    init(
        storageURL: URL? = nil,
        initialOwnerID: String = "local-device"
    ) {
        self.databaseURL = storageURL ?? AppStorageLocation.databaseURL()
        self.currentOwnerID = initialOwnerID
        _ = try? database.connection(at: databaseURL)
        self.offers = loadOffers(ownerID: initialOwnerID)
    }

    func setCurrentOwner(_ ownerID: String) {
        currentOwnerID = ownerID
        offers = loadOffers(ownerID: ownerID)
    }

    func activeOffers(now: Date = Date()) -> [SpecialOffer] {
        offers.filter { $0.isActive(at: now) }
    }

    func activeOffer(
        for entityKind: SpecialOfferEntityKind,
        entityID: RecordID,
        now: Date = Date()
    ) -> SpecialOffer? {
        activeOffers(now: now).first {
            $0.entityKind == entityKind && $0.entityID == entityID
        }
    }

    func mergeOffers(_ remoteOffers: [SpecialOffer]) {
        guard !remoteOffers.isEmpty else { return }
        replaceOffers(OwnerScopedRecordSupport.mergeRecords(local: offers, remote: remoteOffers))
    }

    func replaceOffers(_ authoritativeOffers: [SpecialOffer]) {
        let sorted = OwnerScopedRecordSupport.sorted(authoritativeOffers)
        do {
            try persistReplacedOffers(sorted)
        } catch {
            assertionFailure("Failed to replace special offers: \(error)")
        }
    }

    func persistReplacedOffers(_ authoritativeOffers: [SpecialOffer]) throws {
        let sorted = OwnerScopedRecordSupport.sorted(authoritativeOffers)
        try database.transaction(at: databaseURL) { db in
            try self.replaceRows(ownerID: self.currentOwnerID, offers: sorted, on: db)
        }
        offers = sorted
    }

    func purgeDeletedOffers(on databaseHandle: AppDatabaseHandle? = nil) throws {
        if let databaseHandle {
            try database.execute(
                "DELETE FROM special_offers WHERE owner_id = ? AND deleted_at IS NOT NULL",
                bindings: [.text(currentOwnerID)],
                on: databaseHandle
            )
        } else {
            try database.transaction(at: databaseURL) { db in
                try self.purgeDeletedOffers(on: db)
            }
            refreshCurrentOffers()
        }
    }

    private func refreshCurrentOffers() {
        offers = loadOffers(ownerID: currentOwnerID)
    }

    private func loadOffers(ownerID: String) -> [SpecialOffer] {
        do {
            return try database.query(
                """
                SELECT id, entity_kind, entity_id, modifier_percent, created_at, updated_at, deleted_at, expires_at
                FROM special_offers
                WHERE owner_id = ?
                ORDER BY created_at ASC, id ASC
                """,
                bindings: [.text(ownerID)],
                at: databaseURL
            ) { row in
                SpecialOffer(
                    id: RecordID(SQLiteColumn.text(row, index: 0)),
                    entityKind: SpecialOfferEntityKind(rawValue: SQLiteColumn.text(row, index: 1)) ?? .task,
                    entityID: RecordID(SQLiteColumn.text(row, index: 2)),
                    modifierPercent: SQLiteColumn.int(row, index: 3),
                    createdAt: SQLiteColumn.date(row, index: 4),
                    updatedAt: SQLiteColumn.date(row, index: 5),
                    deletedAt: SQLiteColumn.optionalDate(row, index: 6),
                    expiresAt: SQLiteColumn.date(row, index: 7)
                )
            }
        } catch {
            assertionFailure("Failed to load special offers: \(error)")
            return []
        }
    }

    private func replaceRows(
        ownerID: String,
        offers: [SpecialOffer],
        on databaseHandle: AppDatabaseHandle
    ) throws {
        try database.execute(
            "DELETE FROM special_offers WHERE owner_id = ?",
            bindings: [.text(ownerID)],
            on: databaseHandle
        )

        for offer in offers {
            try database.execute(
                """
                INSERT INTO special_offers (
                    id, owner_id, entity_kind, entity_id, modifier_percent, created_at, updated_at, deleted_at, expires_at
                )
                VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
                """,
                bindings: [
                    .text(offer.id.rawValue),
                    .text(ownerID),
                    .text(offer.entityKind.rawValue),
                    .text(offer.entityID.rawValue),
                    .int(Int64(offer.modifierPercent)),
                    .double(offer.createdAt.timeIntervalSince1970),
                    .double(offer.updatedAt.timeIntervalSince1970),
                    offer.deletedAt.map { .double($0.timeIntervalSince1970) } ?? .null,
                    .double(offer.expiresAt.timeIntervalSince1970)
                ],
                on: databaseHandle
            )
        }
    }
}
