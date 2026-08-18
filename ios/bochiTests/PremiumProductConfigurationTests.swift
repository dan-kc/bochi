import Testing
@testable import bochi

@MainActor
struct PremiumProductConfigurationTests {

    // Behaviour: the premium modal should request the same three products that
    // are configured in the local StoreKit file, in the display order users see.
    @Test func productIDsMatchStoreKitConfiguration() {
        #expect(
            PremiumProductConfiguration.productIDs(environment: [:]) == [
                "monthly.membership",
                "annual.membership",
                "lifetime.membership"
            ]
        )
    }

    // Behaviour: schemes can still override product IDs without changing the
    // app code, but each override is scoped to a single premium option.
    @Test func productIDEnvironmentOverridesAreScopedByKind() {
        let environment = [
            "BOCHI_PREMIUM_MONTHLY_PRODUCT_ID": "override.monthly",
            "BOCHI_PREMIUM_YEARLY_PRODUCT_ID": "override.yearly",
            "BOCHI_PREMIUM_LIFETIME_PRODUCT_ID": "override.lifetime"
        ]

        #expect(PremiumProductConfiguration.productID(for: .monthly, environment: environment) == "override.monthly")
        #expect(PremiumProductConfiguration.productID(for: .yearly, environment: environment) == "override.yearly")
        #expect(PremiumProductConfiguration.productID(for: .lifetime, environment: environment) == "override.lifetime")
    }

    // Behaviour: the App Store purchase flow must tell users the subscription
    // length and price cadence before they choose a recurring premium option.
    @Test func subscriptionDisclosuresDescribeRenewingOptions() {
        #expect(
            PremiumProductConfiguration.disclosure(for: "monthly.membership", environment: [:])
            == PremiumProductDisclosure(
                lengthText: "1 month auto-renewable subscription",
                priceUnitText: "per month",
                renewalText: "Renews automatically until canceled."
            )
        )
        #expect(
            PremiumProductConfiguration.disclosure(for: "annual.membership", environment: [:])
            == PremiumProductDisclosure(
                lengthText: "1 year auto-renewable subscription",
                priceUnitText: "per year",
                renewalText: "Renews automatically until canceled."
            )
        )
    }

    // Behaviour: the lifetime product is shown alongside subscriptions, but
    // should not imply that it renews.
    @Test func lifetimeDisclosureDescribesOneTimePurchase() {
        #expect(
            PremiumProductConfiguration.disclosure(for: "lifetime.membership", environment: [:])
            == PremiumProductDisclosure(
                lengthText: "Lifetime access",
                priceUnitText: "one-time purchase",
                renewalText: nil
            )
        )
    }
}
