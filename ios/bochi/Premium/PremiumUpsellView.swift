import SwiftUI
import StoreKit

enum PremiumUpsellFeature: String, Identifiable {
    case refunds
    case sorting
    case dependencies
    case reminders
    case lockouts
    case timers
    case adjustments

    var id: String { rawValue }

    var contextDescription: String {
        switch self {
        case .refunds:
            return "Refund completed tasks when plans change or mistakes happen."
        case .sorting:
            return "Sort lists your way so the next best task, recurring task, or reward is easier to find."
        case .dependencies:
            return "Use dependencies to make tasks and rewards unlock only after prerequisite work is done."
        case .reminders:
            return "Add reminders so recurring tasks and tasks come back when they need attention."
        case .lockouts:
            return "Set lockouts to pace recurring tasks and rewards instead of repeating them too soon."
        case .timers:
            return "Use timers to run focused sessions, duration countdowns, and multi-interval routines."
        case .adjustments:
            return "Adjust one trade or an entity's ongoing price when the normal pricing ratios do not capture the full value."
        }
    }
}

struct PremiumFeatureBadge: View {
    @Environment(\.bochiTheme) private var theme
    var body: some View {
        Label("Premium", systemImage: "crown.fill")
            .font(.caption2.weight(.semibold))
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(theme.premiumBackground(), in: Capsule())
            .foregroundStyle(theme.premiumText())
    }
}

struct PremiumUpsellView: View {
    @Environment(\.bochiTheme) private var theme
    @Environment(\.dismiss) private var dismiss
    @Environment(AuthManager.self) private var authManager
    @Environment(PremiumWelcomeStore.self) private var premiumWelcomeStore
    let feature: PremiumUpsellFeature?

    @State private var products: [Product] = []
    @State private var selectedProductID: String?
    @State private var isLoadingProducts = false
    @State private var loadingErrorMessage: String?
    @State private var purchaseMessage: String?

    init(feature: PremiumUpsellFeature? = nil) {
        self.feature = feature
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    header
                    productOptions
                    legalDisclosure
                    PremiumIncludedPanel()
                }
                .padding(.horizontal, 20)
                .padding(.top, 24)
                .padding(.bottom, 96)
            }
            .background(theme.appBackground())
            .foregroundStyle(theme.primaryText())
            .safeAreaInset(edge: .bottom) {
                purchaseActions
                    .padding(.horizontal, 20)
                    .padding(.top, 12)
                    .padding(.bottom, 10)
            }
            .navigationTitle("Premium")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") {
                        dismiss()
                    }
                }
            }
            .task {
                await loadProducts()
            }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Unlock Bochi Premium")
                .font(.title2.weight(.bold))
                .fixedSize(horizontal: false, vertical: true)

            Text("Upgrade for refunds, advanced recovery tools, reminders, dependencies, timers, and more control over your progress.")
                .font(.callout)
                .foregroundStyle(theme.secondaryText())
                .fixedSize(horizontal: false, vertical: true)

            if let feature {
                Text(feature.contextDescription)
                    .font(.footnote)
                    .foregroundStyle(theme.secondaryText())
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var productOptions: some View {
        VStack(spacing: 12) {
            if isLoadingProducts {
                ProgressView("Loading App Store options...")
            } else if products.isEmpty {
                Text(loadingErrorMessage ?? "Premium options are not available from the App Store yet.")
                    .font(.footnote)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(theme.secondaryText())
            } else {
                ForEach(products, id: \.id) { product in
                    premiumProductOption(product)
                }
            }

            if let purchaseMessage {
                Text(purchaseMessage)
                    .font(.footnote)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(theme.secondaryText())
            }
        }
        .frame(maxWidth: .infinity)
    }

    private func premiumProductOption(_ product: Product) -> some View {
        let isSelected = selectedProductID == product.id

        return Button {
            selectedProductID = product.id
        } label: {
            HStack(alignment: .center, spacing: 12) {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .foregroundStyle(isSelected ? theme.premiumFill() : theme.secondaryText())

                VStack(alignment: .leading, spacing: 4) {
                    Text(product.displayName)
                        .font(.subheadline.weight(.semibold))
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)

                    Text(descriptionText(for: product))
                        .font(.caption)
                        .foregroundStyle(theme.secondaryText())
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                VStack(alignment: .trailing, spacing: 5) {
                    if let badgeText = badgeText(for: product) {
                        Text(badgeText)
                            .font(.caption2.weight(.bold))
                            .textCase(.uppercase)
                            .lineLimit(1)
                            .minimumScaleFactor(0.75)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(theme.premiumBackground(), in: Capsule())
                            .foregroundStyle(theme.premiumText())
                    }

                    Text(priceText(for: product))
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(theme.primaryText())
                        .lineLimit(1)
                        .minimumScaleFactor(0.75)
                }
                .frame(minWidth: 86, alignment: .trailing)
                .layoutPriority(2)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 14)
            .padding(.vertical, 14)
            .background(
                isSelected ? theme.premiumBackground() : theme.componentBackground(),
                in: RoundedRectangle(cornerRadius: 8, style: .continuous)
            )
            .overlay {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .strokeBorder(isSelected ? theme.premiumFill() : theme.subtleBorder(), lineWidth: isSelected ? 1.5 : 1)
            }
            .contentShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
        .buttonStyle(.plain)
        .disabled(isStoreKitBusy)
        .opacity(isStoreKitBusy ? 0.65 : 1)
    }

    private var purchaseActions: some View {
        BochiActionSurface(
            layout: .expanded(tint: theme.premiumFill()),
            isEnabled: selectedProduct != nil && !isStoreKitBusy,
            action: {
                guard let selectedProduct else { return }
                Task { await purchase(selectedProduct) }
            }
        ) {
            continueActionLabel
        }
        .frame(maxWidth: .infinity)
    }

    private var continueActionLabel: some View {
        HStack(spacing: 8) {
            Text(authManager.isPurchasingPremium ? "Purchasing..." : "Continue")
                .lineLimit(1)
                .minimumScaleFactor(0.85)
            Image(systemName: "arrow.right")
        }
        .font(.callout.weight(.semibold))
        .frame(maxWidth: .infinity)
    }

    private var legalDisclosure: some View {
        Text(linkedLegalDisclosure)
            .font(.caption)
            .multilineTextAlignment(.center)
            .lineLimit(nil)
            .fixedSize(horizontal: false, vertical: true)
            .tint(.blue)
            .padding(.top, 2)
    }

    private var linkedLegalDisclosure: AttributedString {
        let disclosureText = [billingDisclosureText, "By continuing, you agree to the Terms of Use (EULA) and Privacy Policy."]
            .compactMap { $0 }
            .joined(separator: " ")
        var disclosure = AttributedString(disclosureText)
        disclosure.foregroundColor = theme.secondaryText()

        if let termsRange = disclosure.range(of: "Terms of Use (EULA)") {
            disclosure[termsRange].link = AppConfiguration.termsOfUseURL
            disclosure[termsRange].foregroundColor = .blue
        }

        if let privacyRange = disclosure.range(of: "Privacy Policy") {
            disclosure[privacyRange].link = AppConfiguration.privacyPolicyURL
            disclosure[privacyRange].foregroundColor = .blue
        }

        return disclosure
    }

    private var billingDisclosureText: String? {
        guard let selectedProductID,
              let productKind = PremiumProductConfiguration.productKind(for: selectedProductID)
        else {
            return nil
        }

        switch productKind {
        case .monthly, .yearly:
            return "Recurring billing."
        case .lifetime:
            return "One-time purchase."
        }
    }

    private var selectedProduct: Product? {
        products.first { $0.id == selectedProductID }
    }

    private var isStoreKitBusy: Bool {
        authManager.isPurchasingPremium || authManager.isRestoringPurchases
    }

    private func descriptionText(for product: Product) -> String {
        let description = product.description.trimmingCharacters(in: .whitespacesAndNewlines)
        return description.isEmpty ? "Premium access." : description
    }

    private func priceText(for product: Product) -> String {
        switch PremiumProductConfiguration.productKind(for: product.id) {
        case .monthly:
            return "\(product.displayPrice)/mo"
        case .yearly:
            return "\(product.displayPrice)/yr"
        case .lifetime, .none:
            return product.displayPrice
        }
    }

    private func badgeText(for product: Product) -> String? {
        PremiumProductConfiguration.productKind(for: product.id) == .lifetime ? "Best value" : nil
    }

    private func loadProducts() async {
        guard !isLoadingProducts else { return }
        isLoadingProducts = true
        defer { isLoadingProducts = false }

        do {
            let configuredIDs = PremiumProductConfiguration.productIDs()
            let loadedProducts = try await Product.products(for: configuredIDs)
            products = configuredIDs.compactMap { productID in
                loadedProducts.first { $0.id == productID }
            }
            selectedProductID = defaultSelectedProductID(from: products)
            loadingErrorMessage = products.isEmpty
                ? "No premium products were returned by the App Store."
                : nil
        } catch {
            loadingErrorMessage = "The App Store could not load premium options right now."
        }
    }

    private func defaultSelectedProductID(from products: [Product]) -> String? {
        if let selectedProductID, products.contains(where: { $0.id == selectedProductID }) {
            return selectedProductID
        }

        return products.first { PremiumProductConfiguration.productKind(for: $0.id) == .yearly }?.id
            ?? products.first?.id
    }

    private func purchase(_ product: Product) async {
        purchaseMessage = nil

        do {
            let result = try await authManager.purchasePremium(productID: product.id)
            if result.shouldShowPremiumWelcome {
                premiumWelcomeStore.requestPresentation()
                dismiss()
                return
            }

            switch result {
            case .activeOnDeviceAccountLinkFailed:
                purchaseMessage = "Premium is active on this device, but could not link to this account. Check your connection and use Restore Apple Purchase in Settings."
            case .inactive:
                purchaseMessage = "The App Store did not return an active premium entitlement."
            case .activeForAccount, .activeOnDeviceNeedsAccount:
                purchaseMessage = "Premium access is active."
            }
        } catch ApplePurchaseError.cancelled {
            purchaseMessage = nil
        } catch {
            purchaseMessage = (error as? LocalizedError)?.errorDescription
                ?? "The App Store could not complete this purchase right now."
        }
    }

}

private struct PremiumIncludedPanel: View {
    @Environment(\.bochiTheme) private var theme

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Included")
                .font(.headline)

            VStack(spacing: 0) {
                ForEach(PremiumIncludedFeatureCatalog.all) { feature in
                    HStack(alignment: .top, spacing: 12) {
                        Image(systemName: feature.systemImage)
                            .font(.subheadline)
                            .foregroundStyle(theme.premiumText())
                            .frame(width: 24)

                        VStack(alignment: .leading, spacing: 3) {
                            Text(feature.title)
                                .font(.subheadline.weight(.semibold))
                                .frame(maxWidth: .infinity, alignment: .leading)

                            Text(feature.detail)
                                .font(.caption)
                                .foregroundStyle(theme.secondaryText())
                                .fixedSize(horizontal: false, vertical: true)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 10)

                    if feature.id != PremiumIncludedFeatureCatalog.all.last?.id {
                        Divider()
                    }
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 2)
            .background(theme.componentBackground(), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .strokeBorder(theme.subtleBorder(), lineWidth: 1)
            }
        }
    }
}
