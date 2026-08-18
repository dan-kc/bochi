import SwiftUI

struct EntityLockedSummary: View {
    @Environment(\.bochiTheme) private var theme
    let summary: String?

    var body: some View {
        HStack {
            Label("Locked", systemImage: "lock.fill")
            Spacer()
            if let summary {
                Text(summary)
                    .fontWeight(.semibold)
            }
        }
        .font(.subheadline)
        .foregroundStyle(theme.secondaryText())
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .background(theme.componentBackground(), in: Capsule())
    }
}

extension View {
    func blockedTaskDependencyAlert(isPresented: Binding<Bool>) -> some View {
        alert("Task Blocked", isPresented: isPresented) {
            Button("OK", role: .cancel) { }
        } message: {
            Text("This task cannot be completed until its dependencies are finished.")
        }
    }
}
