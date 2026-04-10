import SwiftUI

struct SettingsView: View {
    // @Environment — reads from SwiftUI's environment (exactly like React's useContext). The AuthManager was provided via .environment() up the tree.
    @Environment(AuthManager.self) private var authManager

    var body: some View {
        // NavigationStack — like React Router's <Routes> wrapper, manages a push/pop navigation stack
        NavigationStack {
            // List — like <ul> with native iOS styling and scroll behavior
            List {
                // SwiftUI supports inline conditionals in the body builder (like ternary/&& in JSX, but with full if/else)
                if authManager.isLoading {
                    ProgressView()
                } else if authManager.isAnonymous {
                    anonymousSection
                } else {
                    authenticatedSection
                }
            }
            .navigationTitle("Settings")
        }
    }

    // Computed property returning `some View` — extract sub-views like extracting a JSX fragment into a const
    private var anonymousSection: some View {
        // Section — groups list items with a header/footer (like a fieldset)
        Section {
            if let user = authManager.user {
                // Label { content } icon: { } — trailing closure syntax. The last closure can go outside the parens; named closures use `label:` syntax.
                Label {
                    VStack(alignment: .leading) {
                        Text("Anonymous Account")
                        Text(String(user.id.prefix(8)) + "...")
                            .font(.caption)
                            // .foregroundStyle(.secondary) — `.secondary` is shorthand for `Color.secondary` (Swift infers the type from context)
                            .foregroundStyle(.secondary)
                    }
                } icon: {
                    Image(systemName: "person.crop.circle.badge.questionmark")
                }
            }

            Text("Create an account to sync your data across devices and keep it safe.")
                .font(.footnote)
                .foregroundStyle(.secondary)

            // NavigationLink — like React Router's <Link>, but pushes a view onto the NavigationStack
            NavigationLink("Create Account") {
                ClaimAccountView()
            }

            NavigationLink("Log In") {
                LoginView()
            }
        }
    }

    private var authenticatedSection: some View {
        // Group — transparent wrapper to return multiple Sections (like React.Fragment / <>...</>)
        Group {
            Section {
                if let user = authManager.user {
                    Label {
                        Text(String(user.id.prefix(8)) + "...")
                    } icon: {
                        Image(systemName: "person.crop.circle")
                    }
                }

                NavigationLink("Account Settings") {
                    AccountSettingsView()
                }
            }

            Section {
                // `role: .destructive` — styles the button red (semantic role, like type="danger" in UI libs)
                Button("Log Out", role: .destructive) {
                    // Task { } inside a synchronous context — bridge from sync to async (like wrapping in an IIFE: (async () => { ... })())
                    Task { await authManager.logout() }
                }
            }
        }
    }
}

#Preview {
    SettingsView()
        .environment(AuthManager(
            apiClient: LiveAuthAPIClient(baseURL: URL(string: "http://localhost:8501")!),
            tokenStorage: KeychainTokenStorage()
        ))
}
