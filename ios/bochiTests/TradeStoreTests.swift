import Foundation
import Testing
@testable import bochi

// Tests for TradeStore — tracks recurringTask completion/reward purchase history and
// exposes timestamp lists for pricing calculations.
@MainActor
struct TradeStoreTests {

    private func makeStorageURL(_ name: String = "trades") -> URL {
        TestHelpers.makeTemporaryFileURL(name)
    }

    private func makeSUT(storageURL: URL? = nil) -> TradeStore {
        TradeStore(storageURL: storageURL ?? makeStorageURL())
    }

    private func makeBalanceStore(storageURL: URL) -> BalanceStore {
        BalanceStore(storageURL: storageURL)
    }

    private func expectedVaultInterestMicroAmounts(initialBalance: Int, completedHours: Int) -> [Int] {
        var balance = VaultAmount.microUnits(forWholeBochi: initialBalance)
        var amounts: [Int] = []

        for _ in 0..<completedHours {
            let interest = Int(floor(Double(balance) * TradeStore.hourlyVaultInterestRate))
            if interest > 0 {
                amounts.append(interest)
                balance += interest
            }
        }

        return amounts
    }

    // Behaviour: Before the user completes any recurringTasks, there is no trade history.
    @Test("Initial store has no trades")
    func initiallyEmpty() {
        let sut = makeSUT()
        #expect(sut.trades.isEmpty)
    }

    // Behaviour: Completing a recurringTask records a trade with the correct recurringTask and price amount.
    @Test("addTrade appends a trade with the correct recurringTaskId and amount")
    func addTradeAppends() {
        let sut = makeSUT()
        sut.addRecurringTaskTrade(recurringTaskId: "recurringTask-1", amount: 250)
        #expect(sut.trades.count == 1)
        #expect(sut.trades[0].recurringTaskId == "recurringTask-1")
        #expect(sut.trades[0].rewardId == nil)
        #expect(sut.trades[0].amount == 250)
    }

    // Behaviour: Two completions of the same recurringTask create two distinct history entries.
    @Test("addTrade generates a unique ID for each trade")
    func uniqueIds() {
        let sut = makeSUT()
        sut.addRecurringTaskTrade(recurringTaskId: "h1", amount: 100)
        sut.addRecurringTaskTrade(recurringTaskId: "h1", amount: 200)
        #expect(sut.trades[0].id != sut.trades[1].id)
    }

    // Behaviour: RecurringTask pricing only sees completion timestamps for the selected
    // recurringTask, in chronological order.
    @Test("recurringTaskTradeDates returns matching recurringTask completion timestamps")
    func recurringTaskTradeDatesAreScopedAndOrdered() {
        let sut = makeSUT()
        let firstDate = Date(timeIntervalSince1970: 1_700_000_000)
        let secondDate = Date(timeIntervalSince1970: 1_700_000_100)

        sut.addRecurringTaskTradeWithDate(recurringTaskId: "h1", amount: 100, createdAt: firstDate)
        sut.addRecurringTaskTradeWithDate(recurringTaskId: "h1", amount: 200, createdAt: secondDate)

        #expect(sut.recurringTaskTradeDates(recurringTaskId: "h1") == [firstDate, secondDate])
    }

    // Behaviour: Another recurringTask's completions do not lower this recurringTask's reward.
    @Test("recurringTaskTradeDates excludes trades for other recurringTasks")
    func recurringTaskTradeDatesExcludeOtherRecurringTasks() {
        let sut = makeSUT()
        sut.addRecurringTaskTrade(recurringTaskId: "h1", amount: 100)
        sut.addRecurringTaskTrade(recurringTaskId: "h2", amount: 200)
        #expect(sut.recurringTaskTradeDates(recurringTaskId: "h1").count == 1)
    }

    // Behaviour: Old completions still remain in history because the pricing
    // curve now fades them continuously instead of dropping them at a hard cutoff.
    @Test("recurringTaskTradeDates keeps older completion timestamps")
    func recurringTaskTradeDatesKeepOlderTrades() {
        let sut = makeSUT()
        let olderDate = Date(timeIntervalSinceNow: -10 * 86400)
        let freshDate = Date()

        sut.addRecurringTaskTradeWithDate(recurringTaskId: "h1", amount: 100, createdAt: olderDate)
        sut.addRecurringTaskTradeWithDate(recurringTaskId: "h1", amount: 200, createdAt: freshDate)

        #expect(sut.recurringTaskTradeDates(recurringTaskId: "h1").count == 2)
    }

    // Behaviour: Reward pricing only counts past purchases of that same reward,
    // not recurringTask completions or purchases of other rewards.
    @Test("rewardPurchaseDates returns only matching reward purchases")
    func rewardPurchasesAreScopedToReward() {
        let sut = makeSUT()
        sut.addRewardPurchase(rewardId: "reward-1", amount: -250)
        sut.addRewardPurchase(rewardId: "reward-1", amount: -300)
        sut.addRewardPurchase(rewardId: "reward-2", amount: -150)
        sut.addRecurringTaskTrade(recurringTaskId: "recurringTask-1", amount: 100)

        #expect(sut.rewardPurchaseDates(rewardId: "reward-1").count == 2)
    }

    // Behaviour: list rows should be able to ask the ledger once for each
    // reward's latest unresolved purchase instead of rescanning per reward.
    @Test("latest reward purchase projection follows refunds")
    func latestRewardPurchaseProjectionFollowsRefunds() throws {
        let sut = makeSUT()
        let firstDate = Date(timeIntervalSince1970: 1_700_000_000)
        let secondDate = Date(timeIntervalSince1970: 1_700_000_100)

        sut.addRewardPurchase(id: "reward-trade-1", rewardId: "reward-1", amount: -50, createdAt: firstDate, shouldNotifySync: false)
        sut.addRewardPurchase(id: "reward-trade-2", rewardId: "reward-1", amount: -75, createdAt: secondDate, shouldNotifySync: false)
        sut.addRewardPurchase(id: "reward-trade-3", rewardId: "reward-2", amount: -25, createdAt: firstDate, shouldNotifySync: false)

        #expect(sut.latestUnrefundedRewardPurchasesByRewardID()["reward-1"]?.id == "reward-trade-2")
        #expect(sut.latestUnrefundedRewardPurchasesByRewardID()["reward-2"]?.id == "reward-trade-3")

        _ = try #require(
            sut.refundTrade(
                id: "reward-trade-2",
                refundedAt: secondDate.addingTimeInterval(60),
                shouldNotifySync: false
            )
        )

        #expect(sut.latestUnrefundedRewardPurchasesByRewardID()["reward-1"]?.id == "reward-trade-1")
    }

    // Behaviour: Completing a task should create trade history tied to that
    // task, without pretending it came from a recurringTask or reward.
    @Test("addTaskTrade stores a task-linked trade")
    func addTaskTradeStoresTaskSource() {
        let sut = makeSUT()
        sut.addTaskTrade(taskId: "task-1", amount: 120)

        #expect(sut.trades.count == 1)
        #expect(sut.trades[0].taskId == "task-1")
        #expect(sut.trades[0].recurringTaskId == nil)
        #expect(sut.trades[0].rewardId == nil)
    }

    // Behaviour: an adjusted trade should keep the trade-time price snapshot
    // across app restart so history is not recalculated from later entity edits.
    @Test("trade adjustment snapshot persists")
    func tradeAdjustmentSnapshotPersists() throws {
        let storageURL = makeStorageURL("trade-adjustment-persistence")
        let sut = makeSUT(storageURL: storageURL)
        sut.addTaskTrade(
            taskId: "task-1",
            amount: 500,
            adjustmentBaseAmount: 100,
            oneTimeAdjustmentMultiplier: 0.5,
            shouldNotifySync: false
        )

        let reloaded = TradeStore(storageURL: storageURL)
        let trade = try #require(reloaded.trades.first)
        #expect(trade.amount == 500)
        #expect(trade.adjustmentBaseAmount == 100)
        #expect(trade.oneTimeAdjustmentMultiplier == 0.5)
    }

    // Behaviour: refunding a trade should append a compensating ledger row
    // instead of mutating the original trade in place.
    @Test("refunding a trade appends a compensating trade and updates balance")
    func refundingTradeCreatesCompensatingEntry() throws {
        let storageURL = makeStorageURL("refundable-trades")
        let tradeStore = makeSUT(storageURL: storageURL)
        let balanceStore = makeBalanceStore(storageURL: storageURL)
        let refundedAt = Date(timeIntervalSince1970: 1_800_000_000)

        tradeStore.addRecurringTaskTrade(id: "trade-1", recurringTaskId: "recurringTask-1", amount: 250, shouldNotifySync: false)
        balanceStore.refresh()
        #expect(balanceStore.balance == 250)

        let refundTrade = try #require(
            tradeStore.refundTrade(id: "trade-1", refundedAt: refundedAt, shouldNotifySync: false)
        )
        balanceStore.refresh()

        let originalTrade = try #require(tradeStore.trades.first(where: { $0.id == "trade-1" }))
        #expect(originalTrade.refundsTradeId == nil)
        #expect(refundTrade.amount == -250)
        #expect(refundTrade.recurringTaskId == "recurringTask-1")
        #expect(refundTrade.refundsTradeId == originalTrade.id)
        #expect(tradeStore.trades.count == 2)
        #expect(balanceStore.balance == 0)
    }

    // Behaviour: refunds should only reverse the latest unresolved trade for a
    // source, so older prices cannot be cherry-picked after later activity.
    @Test("refunding an older trade is rejected when a newer source trade exists")
    func refundingOlderTradeIsRejected() {
        let sut = makeSUT()
        let firstDate = Date(timeIntervalSince1970: 1_700_000_000)
        let secondDate = Date(timeIntervalSince1970: 1_700_000_100)

        sut.addRecurringTaskTrade(id: "recurringTask-trade-1", recurringTaskId: "recurringTask-1", amount: 100, createdAt: firstDate, shouldNotifySync: false)
        sut.addRecurringTaskTrade(id: "recurringTask-trade-2", recurringTaskId: "recurringTask-1", amount: 200, createdAt: secondDate, shouldNotifySync: false)

        let refundTrade = sut.refundTrade(
            id: "recurringTask-trade-1",
            refundedAt: secondDate.addingTimeInterval(60),
            shouldNotifySync: false
        )

        #expect(refundTrade == nil)
        #expect(sut.trades.count == 2)
    }

    // Behaviour: refunds should never appear before the trade they reverse,
    // even if a caller passes an invalid timestamp directly to the store.
    @Test("refunding a trade before its created date is rejected")
    func refundingTradeBeforeOriginalTimeIsRejected() {
        let sut = makeSUT()
        let originalDate = Date(timeIntervalSince1970: 1_700_000_000)

        sut.addRecurringTaskTrade(
            id: "recurringTask-trade-1",
            recurringTaskId: "recurringTask-1",
            amount: 100,
            createdAt: originalDate,
            shouldNotifySync: false
        )

        let refundTrade = sut.refundTrade(
            id: "recurringTask-trade-1",
            refundedAt: originalDate.addingTimeInterval(-1),
            shouldNotifySync: false
        )

        #expect(refundTrade == nil)
        #expect(sut.trades.count == 1)
    }

    // Behaviour: if two source trades share a created timestamp, the latest
    // unresolved one should be chosen using the same updatedAt tie-breaker the
    // backend uses during refund validation.
    @Test("latest task trade prefers the newer updated timestamp when createdAt ties")
    func latestTaskTradeUsesUpdatedAtTieBreaker() throws {
        let sut = makeSUT()
        let createdAt = Date(timeIntervalSince1970: 1_700_000_000)
        let firstUpdatedAt = createdAt
        let secondUpdatedAt = createdAt.addingTimeInterval(5)

        sut.addTaskTrade(
            id: "task-trade-1",
            taskId: "task-1",
            amount: 100,
            createdAt: createdAt,
            updatedAt: firstUpdatedAt,
            shouldNotifySync: false
        )
        sut.addTaskTrade(
            id: "task-trade-2",
            taskId: "task-1",
            amount: 120,
            createdAt: createdAt,
            updatedAt: secondUpdatedAt,
            shouldNotifySync: false
        )

        let latestTrade = try #require(sut.latestTaskTrade(taskId: "task-1", includeRefunded: false))
        #expect(latestTrade.id == "task-trade-2")
    }

    // Behaviour: refund trades should stop influencing pricing and lockout
    // calculations that depend on unresolved source timestamps.
    @Test("refund trades exclude the reversed activity from pricing selectors")
    func refundTradesAreExcludedFromActiveSelectors() {
        let sut = makeSUT()
        let firstDate = Date(timeIntervalSince1970: 1_700_000_000)
        let secondDate = Date(timeIntervalSince1970: 1_700_000_100)

        sut.addRecurringTaskTrade(id: "recurringTask-trade-1", recurringTaskId: "recurringTask-1", amount: 100, createdAt: firstDate, shouldNotifySync: false)
        sut.addRecurringTaskTrade(id: "recurringTask-trade-2", recurringTaskId: "recurringTask-1", amount: 200, createdAt: secondDate, shouldNotifySync: false)
        sut.addRewardPurchase(id: "reward-trade-1", rewardId: "reward-1", amount: -50, createdAt: secondDate, shouldNotifySync: false)

        _ = sut.refundTrade(id: "recurringTask-trade-2", refundedAt: secondDate.addingTimeInterval(60), shouldNotifySync: false)
        _ = sut.refundTrade(id: "reward-trade-1", refundedAt: secondDate.addingTimeInterval(120), shouldNotifySync: false)

        #expect(sut.recurringTaskTradeDates(recurringTaskId: "recurringTask-1") == [firstDate])
        #expect(sut.recurringTaskCompletionCount(recurringTaskId: "recurringTask-1") == 1)
        #expect(sut.rewardPurchaseDates(rewardId: "reward-1").isEmpty)
    }

    // Behaviour: depositing into the vault moves points out of spendable balance
    // and into the vault, and the deposit itself can never be refunded.
    @Test("vault deposits transfer balance and are non-refundable")
    func vaultDepositsTransferBalanceAndAreNotRefundable() throws {
        let storageURL = makeStorageURL("vault-deposit")
        let tradeStore = makeSUT(storageURL: storageURL)
        let balanceStore = makeBalanceStore(storageURL: storageURL)

        tradeStore.addRecurringTaskTrade(id: "earn", recurringTaskId: "recurringTask-1", amount: 1_000, shouldNotifySync: false)
        balanceStore.refresh()
        #expect(balanceStore.balance == 1_000)

        tradeStore.addVaultDeposit(id: "vault-deposit", amount: 400, shouldNotifySync: false)
        balanceStore.refresh()

        let deposit = try #require(tradeStore.trades.first(where: { $0.id == "vault-deposit" }))
        #expect(balanceStore.balance == 600)
        #expect(tradeStore.vaultBalance() == 400)
        #expect(tradeStore.vaultBalanceMicro() == 400_000_000)
        #expect(deposit.tradeKind == .vaultDeposit)
        #expect(deposit.amount == -400)
        #expect(deposit.vaultAmountMicro == 400_000_000)
        #expect(!tradeStore.canRefundTrade(deposit))
    }

    // Behaviour: opening the vault after several completed hours materializes
    // one micro-unit interest trade per completed hour.
    @Test("vault accrues hourly interest")
    func vaultAccruesHourlyInterest() throws {
        let sut = makeSUT()
        let depositDate = Date(timeIntervalSince1970: 1_735_725_600) // 2025-01-01T10:00:00Z
        let checkDate = depositDate.addingTimeInterval((3 * 60 * 60) + (30 * 60))

        sut.addVaultDeposit(id: "vault-deposit", amount: 1_000_000, createdAt: depositDate, shouldNotifySync: false)
        sut.accrueVaultInterestIfNeeded(now: checkDate, shouldNotifySync: false)

        let interestTrades = sut.trades.filter { $0.tradeKind == .vaultInterest }
        let expectedInterestAmounts = expectedVaultInterestMicroAmounts(initialBalance: 1_000_000, completedHours: 3)

        #expect(interestTrades.count == 3)
        #expect(interestTrades.map(\.amount) == [0, 0, 0])
        #expect(interestTrades.map(\.vaultAmountMicro) == expectedInterestAmounts.map { Optional($0) })
        #expect(interestTrades.map(\.vaultInterestHour) == [
            depositDate.addingTimeInterval(60 * 60),
            depositDate.addingTimeInterval(2 * 60 * 60),
            depositDate.addingTimeInterval(3 * 60 * 60)
        ])
        #expect(sut.vaultBalanceMicro() == VaultAmount.microUnits(forWholeBochi: 1_000_000) + expectedInterestAmounts.reduce(0, +))
    }

    // Behaviour: small vault balances should still record hourly
    // micro-interest rows instead of waiting for a whole point.
    @Test("vault creates fractional hourly interest")
    func vaultCreatesFractionalHourlyInterest() throws {
        let sut = makeSUT()
        let depositDate = Date(timeIntervalSince1970: 1_735_725_600) // 2025-01-01T10:00:00Z
        let balance = 213
        let firstInterestHour = depositDate.addingTimeInterval(60 * 60)
        let expectedInterest = Int(floor(Double(VaultAmount.microUnits(forWholeBochi: balance)) * TradeStore.hourlyVaultInterestRate))
        sut.addVaultDeposit(id: "vault-deposit", amount: balance, createdAt: depositDate, shouldNotifySync: false)

        sut.accrueVaultInterestIfNeeded(now: firstInterestHour.addingTimeInterval(-60), shouldNotifySync: false)
        #expect(sut.trades.filter { $0.tradeKind == .vaultInterest }.isEmpty)

        sut.accrueVaultInterestIfNeeded(now: firstInterestHour.addingTimeInterval(60), shouldNotifySync: false)

        let interestTrade = try #require(sut.trades.first { $0.tradeKind == .vaultInterest })
        #expect(expectedInterest > 0)
        #expect(interestTrade.amount == 0)
        #expect(interestTrade.vaultAmountMicro == expectedInterest)
        #expect(interestTrade.vaultInterestHour == firstInterestHour)
        #expect(sut.vaultBalanceMicro() == VaultAmount.microUnits(forWholeBochi: balance) + expectedInterest)
    }

    // Behaviour: vault interest summaries are rolling windows, so the previous
    // completed hour appears in the 24-hour total instead of waiting for a day boundary.
    @Test("vault interest summaries use rolling windows")
    func vaultInterestSummariesUseRollingWindows() throws {
        let sut = makeSUT()
        let now = Date(timeIntervalSince1970: 1_735_822_800) // 2025-01-02T13:00:00Z
        let oldHour = now.addingTimeInterval(-25 * 60 * 60)
        let previousHour = now.addingTimeInterval(-60 * 60)

        sut.addVaultInterest(
            id: "old-interest",
            vaultAmountMicro: 7_000_000,
            vaultInterestHour: oldHour,
            createdAt: oldHour,
            shouldNotifySync: false
        )
        sut.addVaultInterest(
            id: "previous-hour-interest",
            vaultAmountMicro: 11_500,
            vaultInterestHour: previousHour,
            createdAt: previousHour,
            shouldNotifySync: false
        )

        #expect(sut.vaultInterestEarnedMicro(since: now.addingTimeInterval(-24 * 60 * 60), now: now) == 11_500)
        #expect(sut.vaultInterestEarnedMicro(since: now.addingTimeInterval(-7 * 24 * 60 * 60), now: now) == 7_011_500)
    }

    // Behaviour: opening the Trades sheet should keep background interest rows
    // out of sight while still showing user-initiated ledger entries.
    @Test("history trades hide vault interest rows")
    func historyTradesHideVaultInterestRows() {
        let sut = makeSUT()
        let depositDate = Date(timeIntervalSince1970: 1_735_725_600) // 2025-01-01T10:00:00Z
        let interestDate = depositDate.addingTimeInterval(60 * 60)

        sut.addVaultDeposit(
            id: "vault-deposit",
            amount: 500,
            createdAt: depositDate,
            shouldNotifySync: false
        )
        sut.addVaultInterest(
            id: "vault-interest",
            vaultAmountMicro: 10_000,
            vaultInterestHour: interestDate,
            createdAt: interestDate,
            shouldNotifySync: false
        )
        sut.addRewardPurchase(
            id: "reward-purchase",
            rewardId: "reward-1",
            amount: -25,
            createdAt: interestDate.addingTimeInterval(60),
            shouldNotifySync: false
        )

        #expect(sut.trades.contains { $0.id == "vault-interest" })
        #expect(sut.historyTrades().map(\.id) == [RecordID("reward-purchase"), RecordID("vault-deposit")])
    }

    // Behaviour: reopening the app after time away should materialize vault
    // interest during store load, but the Trades sheet should hide those rows.
    @Test("vault interest accrues on store load")
    func vaultInterestAccruesOnStoreLoad() throws {
        let storageURL = makeStorageURL("vault-interest-on-load")
        let depositDate = Date(timeIntervalSince1970: 1_735_725_600) // 2025-01-01T10:00:00Z
        let returnDate = depositDate.addingTimeInterval((2 * 60 * 60) + (15 * 60))
        let initialStore = TradeStore(storageURL: storageURL, accruesVaultInterestOnLoad: false)

        initialStore.addVaultDeposit(
            id: "vault-deposit",
            amount: 1_000_000,
            createdAt: depositDate,
            shouldNotifySync: false
        )

        let reloadedStore = TradeStore(
            storageURL: storageURL,
            vaultInterestAccrualNow: returnDate
        )
        let interestTrades = reloadedStore
            .trades
            .filter { $0.tradeKind == .vaultInterest }

        #expect(interestTrades.count == 2)
        #expect(interestTrades.map(\.vaultInterestHour) == [
            depositDate.addingTimeInterval(60 * 60),
            depositDate.addingTimeInterval(2 * 60 * 60)
        ])
        #expect(reloadedStore.historyTrades().map(\.id) == [
            RecordID("vault-deposit")
        ])
    }

    // Behaviour: signed-in ledgers load after auth switches the owner, so that
    // switch should accrue vault interest before any tab-specific view appears.
    @Test("vault interest accrues when switching owners")
    func vaultInterestAccruesWhenSwitchingOwners() throws {
        let storageURL = makeStorageURL("vault-interest-owner-switch")
        let accountOwnerID = "account-owner"
        let depositDate = Date(timeIntervalSince1970: 1_735_725_600) // 2025-01-01T10:00:00Z
        let returnDate = depositDate.addingTimeInterval((3 * 60 * 60) + (10 * 60))
        let accountStore = TradeStore(
            storageURL: storageURL,
            initialOwnerID: accountOwnerID,
            accruesVaultInterestOnLoad: false
        )

        accountStore.addVaultDeposit(
            id: "account-vault-deposit",
            amount: 1_000_000,
            createdAt: depositDate,
            shouldNotifySync: false
        )

        let appStore = TradeStore(
            storageURL: storageURL,
            initialOwnerID: StorageOwner.local,
            accruesVaultInterestOnLoad: false
        )
        appStore.setCurrentOwner(accountOwnerID, vaultInterestAccrualNow: returnDate)

        let interestTrades = appStore
            .trades
            .filter { $0.tradeKind == .vaultInterest }

        #expect(interestTrades.count == 3)
        #expect(interestTrades.map(\.vaultInterestHour) == [
            depositDate.addingTimeInterval(60 * 60),
            depositDate.addingTimeInterval(2 * 60 * 60),
            depositDate.addingTimeInterval(3 * 60 * 60)
        ])
        #expect(appStore.historyTrades().map(\.id) == [
            RecordID("account-vault-deposit")
        ])
    }

    // Behaviour: refunding a vault reward spend restores the vault balance and
    // makes the once-a-month vault purchase slot available immediately.
    @Test("vault reward refund reopens purchase availability")
    func vaultRewardRefundReopensPurchaseAvailability() throws {
        let sut = makeSUT()
        let spentAt = Date(timeIntervalSince1970: 1_800_000_000)
        let refundedAt = spentAt.addingTimeInterval(600)

        sut.addVaultDeposit(id: "deposit", amount: 1_000, createdAt: spentAt.addingTimeInterval(-60), shouldNotifySync: false)
        sut.addVaultRewardPurchases(
            entries: [(id: "vault-spend", amount: -300, adjustmentBaseAmount: nil)],
            rewardId: "reward-1",
            sourceName: "Saved reward",
            createdAt: spentAt,
            shouldNotifySync: false
        )

        #expect(sut.vaultBalance() == 700)
        #expect(sut.vaultBalanceMicro() == 700_000_000)
        #expect(sut.nextVaultPurchaseAvailableAt(now: spentAt.addingTimeInterval(60)) != nil)

        let refund = try #require(sut.refundTrade(id: "vault-spend", refundedAt: refundedAt, shouldNotifySync: false))

        #expect(sut.vaultBalance() == 1_000)
        #expect(sut.vaultBalanceMicro() == 1_000_000_000)
        #expect(refund.amount == 0)
        #expect(refund.vaultAmountMicro == 300_000_000)
        #expect(sut.nextVaultPurchaseAvailableAt(now: refundedAt) == nil)
    }
}
