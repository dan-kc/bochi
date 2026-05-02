import Foundation

struct SpecialOfferSnapshot: Sendable {
    private struct OfferKey: Hashable, Sendable {
        let entityKind: SpecialOfferEntityKind
        let entityID: RecordID
    }

    let now: Date
    private let offersByKey: [OfferKey: SpecialOffer]

    init(offers: [SpecialOffer], now: Date) {
        self.now = now

        var offersByKey: [OfferKey: SpecialOffer] = [:]
        for offer in offers {
            offersByKey[OfferKey(entityKind: offer.entityKind, entityID: offer.entityID)] = offer
        }
        self.offersByKey = offersByKey
    }

    func activeOffer(
        for entityKind: SpecialOfferEntityKind,
        entityID: RecordID
    ) -> SpecialOffer? {
        offersByKey[OfferKey(entityKind: entityKind, entityID: entityID)]
    }

    func activeModifierPercent(
        for entityKind: SpecialOfferEntityKind,
        entityID: RecordID
    ) -> Int? {
        activeOffer(for: entityKind, entityID: entityID)?.modifierPercent
    }

    func hasActiveOffer(
        for entityKind: SpecialOfferEntityKind,
        entityID: RecordID
    ) -> Bool {
        activeOffer(for: entityKind, entityID: entityID) != nil
    }
}
