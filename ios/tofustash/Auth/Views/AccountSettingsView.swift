import SwiftUI

struct AccountSettingsView: View {
    var body: some View {
        List {
            NavigationLink("Change Email") {
                ChangeEmailView()
            }

            NavigationLink("Change Password") {
                ChangePasswordView()
            }
        }
        .navigationTitle("Account")
    }
}
