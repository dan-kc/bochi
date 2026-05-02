import Foundation
import Testing
@testable import tofustash

struct SpecialOfferSnapshotTests {
    // Behaviour: once a view captures a special-offer snapshot for a specific
    // moment, later store churn should not silently change the modifier that
    // same screen uses for prices, badges, and actions.
    @Test func snapshotKeepsResolvedOfferStableAfterStoreChanges() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let initialOffer = SpecialOffer(
            id: "offer-initial",
            entityKind: .reward,
            entityID: "reward-1",
            modifierPercent: -30,
            createdAt: now,
            updatedAt: now,
            deletedAt: nil,
            expiresAt: now.addingTimeInterval(86_400)
        )
        let replacementOffer = SpecialOffer(
            id: "offer-replacement",
            entityKind: .reward,
            entityID: "reward-1",
            modifierPercent: -50,
            createdAt: now.addingTimeInterval(60),
            updatedAt: now.addingTimeInterval(60),
            deletedAt: nil,
            expiresAt: now.addingTimeInterval(172_800)
        )

        let snapshot = SpecialOfferSnapshot(offers: [initialOffer], now: now)
        let updatedSnapshot = SpecialOfferSnapshot(offers: [replacementOffer], now: now)

        #expect(snapshot.activeModifierPercent(for: .reward, entityID: "reward-1") == -30)
        #expect(updatedSnapshot.activeModifierPercent(for: .reward, entityID: "reward-1") == -50)
    }
}
