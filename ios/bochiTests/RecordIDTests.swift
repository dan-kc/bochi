import Foundation
import Testing
@testable import bochi

struct RecordIDTests {
    // Behaviour: when sync echoes back the same UUID in lowercase, the app must
    // treat it as the same record that Swift created locally in uppercase.
    @Test func initLowercasesUUIDStrings() {
        #expect(
            RecordID("A0B1C2D3-E4F5-6789-ABCD-EF0123456789").rawValue
            == "a0b1c2d3-e4f5-6789-abcd-ef0123456789"
        )
    }

    // Behaviour: merging a locally-created recurringTask with the server echo should
    // keep one visible row because both ids collapse to the same canonical form.
    @Test func syncRecurringTaskModelNormalizesReturnedID() {
        let record = SyncRecurringTaskRecord(
            id: "A0B1C2D3-E4F5-6789-ABCD-EF0123456789",
            name: "Pushups",
            description: "",
            createdAt: "2026-04-19T12:00:00.000000",
            updatedAt: "2026-04-19T12:00:00.000000",
            deletedAt: nil,
            minDailyFrequency: nil,
            basePrice: 100
        )

        let model = record.toModel()
        #expect(model?.id == RecordID("a0b1c2d3-e4f5-6789-abcd-ef0123456789"))
    }
}
