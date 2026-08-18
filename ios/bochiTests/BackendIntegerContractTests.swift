import Foundation
import Testing
@testable import bochi

@MainActor
struct BackendIntegerContractTests {
    // Behaviour: local persistence should reject prices that the backend sync
    // contract cannot store, even if code bypasses the normal form controls.
    @Test func sqliteRejectsTaskBasePriceAboveBackendMaximum() throws {
        let storageURL = TestHelpers.makeTemporaryFileURL("backend-integer-contract")

        do {
            try AppDatabase.shared.execute(
                """
                INSERT INTO tasks (
                    id, owner_id, recurring, name, description, created_at, updated_at,
                    deleted_at, base_price, due_date, min_daily_frequency,
                    lockout_duration_seconds, pinned, hidden, timer_mode, timer_id
                )
                VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                """,
                bindings: [
                    .text("task-1"),
                    .text(StorageOwner.local),
                    .int(0),
                    .text("Too expensive"),
                    .text(""),
                    .double(1),
                    .double(1),
                    .null,
                    .int(Int64(BackendIntegerContract.max) + 1),
                    .null,
                    .null,
                    .null,
                    .int(0),
                    .int(0),
                    .null,
                    .null,
                ],
                at: storageURL
            )
            Issue.record("Expected SQLite to reject a backend-impossible task price.")
        } catch {
            #expect(true)
        }
    }

    // Behaviour: raw ledger writes should not be able to create trades whose
    // amount is outside the signed i32 range accepted by sync.
    @Test func sqliteRejectsTradeAmountAboveBackendMaximum() throws {
        let storageURL = TestHelpers.makeTemporaryFileURL("backend-integer-contract")

        do {
            try AppDatabase.shared.execute(
                """
                INSERT INTO trades (
                    id, owner_id, task_id, recurring_task_id, reward_id, source_name, amount,
                    vault_amount_micro, adjustment_base_amount, one_time_adjustment_multiplier,
                    trade_kind, vault_interest_hour, created_at, updated_at, deleted_at,
                    refunds_trade_id
                )
                VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                """,
                bindings: [
                    .text("trade-1"),
                    .text(StorageOwner.local),
                    .text("task-1"),
                    .null,
                    .null,
                    .text("Task"),
                    .int(Int64(BackendIntegerContract.max) + 1),
                    .null,
                    .null,
                    .null,
                    .text(TradeKind.taskCompletion.rawValue),
                    .null,
                    .double(1),
                    .double(1),
                    .null,
                    .null,
                ],
                at: storageURL
            )
            Issue.record("Expected SQLite to reject a backend-impossible trade amount.")
        } catch {
            #expect(true)
        }
    }
}
