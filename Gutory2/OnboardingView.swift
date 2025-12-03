import SwiftUI
import Supabase

struct OnboardingView: View {

    // Start in Log In mode
    @State private var mode: AuthMode = .login
    @State private var email = ""
    @State private var password = ""
    @State private var isLoading = false
    @State private var errorMessage: String?

    let onAuthComplete: () -> Void

    enum AuthMode {
        case signup
        case login
    }

    var body: some View {
        ZStack {
            LinearGradient(
                gradient: Gradient(colors: [
                    Color.white,
                    Color.white.opacity(0.92)
                ]),
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()

            VStack(spacing: 28) {

                // Logo
                VStack(spacing: 4) {
                    Image("GutoryLogoText")
                        .resizable()
                        .scaledToFit()
                        .frame(width: 120)
                        .padding(.top, 80)
                }

                // Card container
                VStack(spacing: 16) {
                    // Segmented control
                    HStack(spacing: 0) {
                        // LEFT: Log In
                        Button {
                            mode = .login
                        } label: {
                            Text("Log In")
                                .fontWeight(mode == .login ? .semibold : .regular)
                                .foregroundColor(mode == .login ? .black : .secondary)
                                .padding(.vertical, 10)
                                .frame(maxWidth: .infinity)
                                .background(
                                    mode == .login
                                    ? Color.white.opacity(0.8)
                                    : Color.clear
                                )
                                .clipShape(RoundedRectangle(cornerRadius: 12))
                        }

                        // RIGHT: Create Account
                        Button {
                            mode = .signup
                        } label: {
                            Text("Create Account")
                                .fontWeight(mode == .signup ? .semibold : .regular)
                                .foregroundColor(mode == .signup ? .black : .secondary)
                                .padding(.vertical, 10)
                                .frame(maxWidth: .infinity)
                                .background(
                                    mode == .signup
                                    ? Color.white.opacity(0.8)
                                    : Color.clear
                                )
                                .clipShape(RoundedRectangle(cornerRadius: 12))
                        }
                    }
                    .padding(.horizontal, 12)
                    .background(Color.white.opacity(0.2))
                    .clipShape(RoundedRectangle(cornerRadius: 18))

                    // Email
                    TextField("Email", text: $email)
                        .keyboardType(.emailAddress)
                        .textInputAutocapitalization(.never)
                        .padding()
                        .background(Color.gray.opacity(0.08))
                        .clipShape(RoundedRectangle(cornerRadius: 14))

                    // Password
                    SecureField("Password (min 6 characters)", text: $password)
                        .padding()
                        .background(Color.gray.opacity(0.08))
                        .clipShape(RoundedRectangle(cornerRadius: 14))

                    if let error = errorMessage {
                        Text(error)
                            .foregroundColor(.red)
                            .font(.footnote)
                    }

                    // Submit button
                    Button(action: submitTapped) {
                        HStack {
                            if isLoading {
                                ProgressView().tint(.white)
                            } else {
                                Text(mode == .signup ? "Create Account" : "Log In")
                                    .fontWeight(.semibold)
                            }
                        }
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.accentColor)
                        .foregroundColor(.white)
                        .clipShape(RoundedRectangle(cornerRadius: 16))
                    }
                    .disabled(isLoading)
                    .padding(.top, 4)
                }
                .padding(20)
                .background(Color.white.opacity(0.94))
                .clipShape(RoundedRectangle(cornerRadius: 28))
                .shadow(color: .black.opacity(0.08), radius: 24, y: 8)
                .padding(.horizontal, 20)

                Spacer()
            }
        }
    }

    private func submitTapped() {
        errorMessage = nil
        isLoading = true

        Task {
            do {
                if mode == .signup {
                    _ = try await supabase.auth.signUp(email: email, password: password)
                } else {
                    _ = try await supabase.auth.signIn(email: email, password: password)
                }

                await MainActor.run {
                    isLoading = false
                    onAuthComplete()
                }
            } catch {
                await MainActor.run {
                    isLoading = false
                    errorMessage = error.localizedDescription
                }
            }
        }
    }
}
