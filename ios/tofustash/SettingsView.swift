import SwiftUI

struct SettingsView: View {
    @Environment(AuthManager.self) private var authManager

    var body: some View {
        NavigationStack {
            List {
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

    private var anonymousSection: some View {
        Section {
            if let user = authManager.user {
                Label {
                    VStack(alignment: .leading) {
                        Text("Anonymous Account")
                        Text(String(user.id.prefix(8)) + "...")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                } icon: {
                    Image(systemName: "person.crop.circle.badge.questionmark")
                }
            }

            Text("Create an account to sync your data across devices and keep it safe.")
                .font(.footnote)
                .foregroundStyle(.secondary)

            NavigationLink("Create Account") {
                ClaimAccountView()
            }

            NavigationLink("Log In") {
                LoginView()
            }
        }
    }

    private var authenticatedSection: some View {
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
                Button("Log Out", role: .destructive) {
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
