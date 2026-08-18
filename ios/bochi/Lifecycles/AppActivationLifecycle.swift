import Foundation
import SwiftUI

// Sync flow: on foreground, accrue local vault interest first, then ask sync for
// a silent remote refresh for the captured owner.
@MainActor
protocol VaultInterestAccruing: AnyObject {
    func accrueVaultInterestIfNeeded(now: Date, shouldNotifySync: Bool)
}

extension TradeStore: VaultInterestAccruing { }

@MainActor
enum AppActivationLifecycleCoordinator {
    static func runActivationWork(
        syncManager: SyncBackgroundPulling,
        tradeStore: VaultInterestAccruing,
        ownerID: String?,
        now: Date = Date()
    ) async {
        tradeStore.accrueVaultInterestIfNeeded(now: now, shouldNotifySync: true)
        guard let ownerID else { return }
        await SyncBackgroundPullLifecycleCoordinator.runPull(
            syncManager: syncManager,
            ownerID: ownerID
        )
    }
}

private struct AppActivationLifecycleTrigger: Equatable {
    let sceneIsActive: Bool
}

private struct AppActivationLifecycleModifier: ViewModifier {
    let scenePhase: ScenePhase
    let ownerID: String?
    let syncManager: SyncBackgroundPulling
    let tradeStore: TradeStore
    let activationDelay: Duration

    func body(content: Content) -> some View {
        let trigger = AppActivationLifecycleTrigger(sceneIsActive: scenePhase == .active)

        content.task(id: trigger) {
            guard trigger.sceneIsActive else { return }

            do {
                try await Task.sleep(for: activationDelay)
            } catch {
                return
            }

            guard !Task.isCancelled else { return }
            await AppActivationLifecycleCoordinator.runActivationWork(
                syncManager: syncManager,
                tradeStore: tradeStore,
                ownerID: ownerID
            )
        }
    }
}

extension View {
    func appActivationLifecycle(
        scenePhase: ScenePhase,
        ownerID: String?,
        syncManager: SyncBackgroundPulling,
        tradeStore: TradeStore,
        activationDelay: Duration = .seconds(1)
    ) -> some View {
        modifier(
            AppActivationLifecycleModifier(
                scenePhase: scenePhase,
                ownerID: ownerID,
                syncManager: syncManager,
                tradeStore: tradeStore,
                activationDelay: activationDelay
            )
        )
    }
}
