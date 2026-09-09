import SwiftUI

@main
struct CS_4261_Programming_AssignmentApp: App {
    @State private var auth = AuthStore()
    @State private var notifications = NotificationStore()

    var body: some Scene {
        WindowGroup {
            if auth.isLoggedIn {
                ContentView()
                    .environment(auth)
                    .environment(notifications)
            } else {
                LoginView()
                    .environment(auth)
            }
        }
    }
}
