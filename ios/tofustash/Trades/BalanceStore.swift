import Foundation

@Observable
@MainActor
final class BalanceStore {
    private let databaseURL: URL
    private let database = AppDatabase.shared

    private(set) var currentOwnerID: String
    private(set) var balance: Int = 0

    init(
        storageURL: URL? = nil,
        initialOwnerID: String = "local-device"
    ) {
        self.databaseURL = storageURL ?? AppStorageLocation.databaseURL()
        self.currentOwnerID = initialOwnerID
        _ = try? database.connection(at: databaseURL)
        self.balance = loadBalance(ownerID: initialOwnerID)
    }

    func setCurrentOwner(_ ownerID: String) {
        currentOwnerID = ownerID
        balance = loadBalance(ownerID: ownerID)
    }

    func addTofu(_ amount: Int) {
        setBalance(balance + amount)
    }

    func subtractTofu(_ amount: Int) {
        setBalance(balance - amount)
    }

    func setBalance(_ value: Int) {
        do {
            try database.execute(
                """
                INSERT INTO balance_projections (owner_id, balance, updated_at)
                VALUES (?, ?, ?)
                ON CONFLICT(owner_id) DO UPDATE SET
                    balance = excluded.balance,
                    updated_at = excluded.updated_at
                """,
                bindings: [
                    .text(currentOwnerID),
                    .int(Int64(value)),
                    .double(Date().timeIntervalSince1970)
                ],
                at: databaseURL
            )
        } catch {
            assertionFailure("Failed to set balance: \(error)")
        }
        balance = value
    }

    func refresh() {
        balance = loadBalance(ownerID: currentOwnerID)
    }

    private func loadBalance(ownerID: String) -> Int {
        do {
            return try database.queryOne(
                "SELECT balance FROM balance_projections WHERE owner_id = ?",
                bindings: [.text(ownerID)],
                at: databaseURL
            ) { row in
                SQLiteColumn.int(row, index: 0)
            } ?? 0
        } catch {
            assertionFailure("Failed to load balance: \(error)")
            return 0
        }
    }
}
