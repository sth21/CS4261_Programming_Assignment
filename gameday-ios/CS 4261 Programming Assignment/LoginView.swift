import SwiftUI

struct LoginView: View {
    @Environment(AuthStore.self) private var auth

    @State private var mode: Mode = .logIn
    @State private var username = ""
    @State private var password = ""
    @State private var isLoading = false
    @State private var errorMessage: String?

    enum Mode: String, CaseIterable {
        case logIn = "Log In"
        case signUp = "Sign Up"
    }

    var body: some View {
        VStack(spacing: 24) {
            Spacer()

            VStack(spacing: 10) {
                Image(systemName: "football.fill")
                    .font(.system(size: 44))
                    .foregroundStyle(.secondary)

                Text("NCAAFB Pick'em")
                    .font(.largeTitle.bold())
            }

            Picker("Mode", selection: $mode) {
                ForEach(Mode.allCases, id: \.self) { m in
                    Text(m.rawValue).tag(m)
                }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal, 40)
            .onChange(of: mode) { errorMessage = nil }

            VStack(spacing: 12) {
                TextField("Username", text: $username)
                    .textFieldStyle(.roundedBorder)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)

                SecureField("Password", text: $password)
                    .textFieldStyle(.roundedBorder)

                if let errorMessage {
                    Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
                        .font(.caption)
                        .foregroundStyle(.red)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }

                Button {
                    Task { await submit() }
                } label: {
                    Group {
                        if isLoading {
                            ProgressView().tint(.white)
                        } else {
                            Text(mode == .signUp ? "Create Account" : "Log In")
                                .font(.headline)
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .frame(height: 48)
                    .background(canSubmit ? Color.accentColor : Color(.secondarySystemBackground))
                    .foregroundStyle(canSubmit ? .white : .secondary)
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                }
                .buttonStyle(.plain)
                .disabled(!canSubmit)
                .padding(.top, 4)
            }
            .padding(.horizontal, 32)

            Spacer()
            Spacer()
        }
    }

    var canSubmit: Bool {
        !username.isEmpty && password.count >= 6 && !isLoading
    }

    func submit() async {
        isLoading = true
        errorMessage = nil
        do {
            auth.token = try await APIClient.authenticate(
                username: username.trimmingCharacters(in: .whitespaces),
                password: password,
                register: mode == .signUp
            )
        } catch APIError.server(409) {
            errorMessage = "That username is already taken."
        } catch APIError.server(401) {
            errorMessage = "Incorrect username or password."
        } catch APIError.offline {
            errorMessage = "Couldn't connect. Check your connection and try again."
        } catch {
            errorMessage = "Something went wrong. Try again."
        }
        isLoading = false
    }
}

#Preview {
    LoginView()
        .environment(AuthStore())
}
