import Foundation
import Testing
@testable import tofustash

@MainActor
struct SpecialOfferStoreTests {
    private func makeStore() -> SpecialOfferStore {
        SpecialOfferStore(storageURL: TestHelpers.makeTemporaryFileURL("special-offers"))
    }

    // Behaviour: when sync replaces the current offer set, the store should
    // return the active modifier for the matching entity and ignore expired rows.
    @Test func activeOfferLookupIgnoresExpiredOffers() throws {
        let sut = makeStore()
        let now = Date(timeIntervalSince1970: 1_800_000_000)

        sut.replaceOffers([
            SpecialOffer(
                id: "offer-active",
                entityKind: .habit,
                entityID: "habit-1",
                modifierPercent: 30,
                createdAt: now,
                updatedAt: now,
                deletedAt: nil,
                expiresAt: now.addingTimeInterval(86_400)
            ),
            SpecialOffer(
                id: "offer-expired",
                entityKind: .habit,
                entityID: "habit-2",
                modifierPercent: 50,
                createdAt: now.addingTimeInterval(-172_800),
                updatedAt: now.addingTimeInterval(-172_800),
                deletedAt: nil,
                expiresAt: now.addingTimeInterval(-86_400)
            )
        ])

        #expect(sut.activeOffer(for: .habit, entityID: "habit-1", now: now)?.modifierPercent == 30)
        #expect(sut.activeOffer(for: .habit, entityID: "habit-2", now: now) == nil)
    }
}
