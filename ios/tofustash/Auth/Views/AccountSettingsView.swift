import SwiftUI

struct AccountSettingsView: View {
    var body: some View {
        // List = a scrollable container like <ul>. NavigationLink = <Link to={...}> in React Router.
        // The trailing closure is the destination view — rendered lazily when tapped.
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
