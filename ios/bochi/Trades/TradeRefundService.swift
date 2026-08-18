import Foundation

@MainActor
enum TradeRefundService {
    @discardableResult
    static func refund(
        for trade: Trade,
        tradeStore: TradeStore,
        balanceStore: BalanceStore,
        now: Date = Date()
    ) -> Trade? {
        let refundTrade = tradeStore.refundTrade(id: trade.id, refundedAt: now)
        guard let refundTrade else { return nil }

        balanceStore.refresh()
        return refundTrade
    }
}
