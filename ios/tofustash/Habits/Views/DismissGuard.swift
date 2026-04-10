import SwiftUI
import UIKit

// DismissGuard intercepts interactive dismiss attempts (drag-down or tap-outside)
// on a sheet. It's like a `beforeunload` event in the browser — it lets you block
// the dismiss and show a confirmation dialog instead.
//
// SwiftUI's .interactiveDismissDisabled blocks dismissal but doesn't tell you
// when the user tried to dismiss. This bridge into UIKit's presentation controller
// delegate gives us that "attempt" callback.
//
// Usage: add `.background(DismissGuard(isEnabled: condition) { showDialog = true })`
// to the content inside a .sheet.
struct DismissGuard: UIViewControllerRepresentable {
    // When false, interactive dismiss works normally (no interception).
    let isEnabled: Bool
    // Called when the user tries to dismiss interactively while isEnabled is true.
    let onAttempt: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(isEnabled: isEnabled, onAttempt: onAttempt)
    }

    func makeUIViewController(context: Context) -> UIViewController {
        // This view controller is invisible — it only exists to hook into UIKit's
        // view controller hierarchy so we can access the sheet's presentation controller.
        let vc = UIViewController()
        vc.view.isHidden = true
        vc.view.frame = .zero
        return vc
    }

    func updateUIViewController(_ vc: UIViewController, context: Context) {
        // Keep the coordinator's state in sync with SwiftUI's state.
        // This runs every time `isEnabled` changes (like a useEffect dependency).
        context.coordinator.isEnabled = isEnabled
        context.coordinator.onAttempt = onAttempt

        // Walk up the view controller tree to find the root of this sheet,
        // then install our delegate on its presentation controller.
        // Similar to walking up the DOM to find a parent element in React.
        DispatchQueue.main.async {
            var topVC: UIViewController = vc
            while let parent = topVC.parent {
                topVC = parent
            }
            topVC.presentationController?.delegate = context.coordinator
        }
    }

    class Coordinator: NSObject, UIAdaptivePresentationControllerDelegate {
        var isEnabled: Bool
        var onAttempt: () -> Void

        init(isEnabled: Bool, onAttempt: @escaping () -> Void) {
            self.isEnabled = isEnabled
            self.onAttempt = onAttempt
        }

        // UIKit calls this when the user tries to dismiss interactively.
        // Returning false blocks the dismiss; returning true allows it.
        func presentationControllerShouldDismiss(
            _ presentationController: UIPresentationController
        ) -> Bool {
            !isEnabled
        }

        // Called after we blocked a dismiss attempt (returned false above).
        // This is where we trigger the discard confirmation dialog.
        func presentationControllerDidAttemptToDismiss(
            _ presentationController: UIPresentationController
        ) {
            onAttempt()
        }
    }
}
