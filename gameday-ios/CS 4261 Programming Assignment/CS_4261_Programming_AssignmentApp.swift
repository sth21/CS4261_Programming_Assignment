import SwiftUI

@main
struct CS_4261_Programming_AssignmentApp: App {
    @State private var auth = AuthStore()

    var body: some Scene {
        WindowGroup {
            if auth.isLoggedIn {
                ContentView()
                    .environment(auth)
            } else {
                LoginView()
                    .environment(auth)
            }
        }
    }
}
