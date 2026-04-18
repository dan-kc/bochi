import SwiftUI

// Kept as a compatibility wrapper while older navigation entry points are
// removed. The old "claim anonymous account" workflow is now just normal
// account creation from signed-out local mode.
struct ClaimAccountView: View {
    var body: some View {
        RegisterView()
    }
}
