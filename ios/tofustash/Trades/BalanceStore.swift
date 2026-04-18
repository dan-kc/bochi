import Foundation

@Observable
@MainActor
final class BalanceStore {
    private struct PersistedState: Codable {
        var balanceByOwner: [String: Int] = [:]
    }

    private let storageURL: URL
    private(set) var currentOwnerID: String
    private var balanceByOwner: [String: Int]

    private(set) var balance: Int = 0

    init(
        storageURL: URL? = nil,
        initialOwnerID: String = "local-device"
    ) {
        self.storageURL = storageURL ?? AppStorageLocation.fileURL(filename: "balances")
        self.currentOwnerID = initialOwnerID
        let persisted = JSONFileStore.load(PersistedState.self, from: self.storageURL, defaultValue: PersistedState())
        self.balanceByOwner = persisted.balanceByOwner
        self.balance = persisted.balanceByOwner[initialOwnerID] ?? 0
    }

    func setCurrentOwner(_ ownerID: String) {
        currentOwnerID = ownerID
        balance = balanceByOwner[ownerID] ?? 0
    }

    func migrateBalance(from sourceOwnerID: String, to destinationOwnerID: String) {
        guard sourceOwnerID != destinationOwnerID else { return }
        let sourceBalance = balanceByOwner[sourceOwnerID] ?? 0
        guard sourceBalance != 0 else { return }

        balanceByOwner[destinationOwnerID] = sourceBalance
        balanceByOwner[sourceOwnerID] = 0
        persist()
        balance = balanceByOwner[currentOwnerID] ?? 0
    }

    func addTofu(_ amount: Int) {
        balance += amount
        balanceByOwner[currentOwnerID] = balance
        persist()
    }

    func subtractTofu(_ amount: Int) {
        balance -= amount
        balanceByOwner[currentOwnerID] = balance
        persist()
    }

    func setBalance(_ value: Int) {
        balance = value
        balanceByOwner[currentOwnerID] = value
        persist()
    }

    private func persist() {
        JSONFileStore.save(PersistedState(balanceByOwner: balanceByOwner), to: storageURL)
    }
}
