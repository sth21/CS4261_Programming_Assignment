import Foundation
import KeychainAccess
import SwiftUI

@Observable
class AuthStore {
    private let keychain = Keychain(service: "CS-4261.CS-4261-Programming-Assignment")
    private let tokenKey = "authToken"

    var token: String? {
        didSet {
            if let token {
                try? keychain.set(token, key: tokenKey)
            } else {
                try? keychain.remove(tokenKey)
            }
        }
    }

    var isLoggedIn: Bool { token != nil }

    init() {
        token = try? keychain.get(tokenKey)
    }

    func logOut() {
        token = nil
    }
}
