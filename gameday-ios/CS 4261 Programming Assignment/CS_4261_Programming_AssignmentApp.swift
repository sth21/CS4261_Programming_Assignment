//
//  CS_4261_Programming_AssignmentApp.swift
//  CS 4261 Programming Assignment
//
//  Created by Sam Heseltine on 8/31/26.
//

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
