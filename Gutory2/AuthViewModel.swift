import Foundation
import Combine
import Supabase

/// Simple auth state + actions for Gutory
@MainActor
final class AuthViewModel: ObservableObject {

    // MARK: - Published state

    @Published var email: String = ""
    @Published var password: String = ""
    @Published var isLoading: Bool = false
    @Published var errorMessage: String? = nil
    @Published var infoMessage: String? = nil   // <- non-error messages (e.g. password reset)

    /// True when we have a valid Supabase session
    @Published var isLoggedIn: Bool = false

    /// Optional: current session if you need it later
    @Published var currentSession: Session? = nil

    // MARK: - Init

    init() {
        Task {
            await self.loadInitialSession()
        }
    }

    // MARK: - Public actions

    /// Create a new account with email + password
    func signUp() async {
        errorMessage = nil
        infoMessage = nil
        isLoading = true
        defer { isLoading = false }

        let trimmedEmail = email.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedPassword = password.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !trimmedEmail.isEmpty, !trimmedPassword.isEmpty else {
            errorMessage = "Please enter an email and password."
            return
        }

        do {
            _ = try await supabase.auth.signUp(
                email: trimmedEmail,
                password: trimmedPassword
            )
            try await refreshSession()
        } catch {
            errorMessage = friendlyErrorMessage(error)
            print("Auth signUp error: \(error)")
        }
    }

    /// Log in an existing user
    func signIn() async {
        errorMessage = nil
        infoMessage = nil
        isLoading = true
        defer { isLoading = false }

        let trimmedEmail = email.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedPassword = password.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !trimmedEmail.isEmpty, !trimmedPassword.isEmpty else {
            errorMessage = "Please enter an email and password."
            return
        }

        do {
            _ = try await supabase.auth.signIn(
                email: trimmedEmail,
                password: trimmedPassword
            )
            try await refreshSession()
        } catch {
            errorMessage = friendlyErrorMessage(error)
            print("Auth signIn error: \(error)")
        }
    }

    /// Send a password reset email
    func sendPasswordReset() async {
        errorMessage = nil
        infoMessage = nil
        isLoading = true
        defer { isLoading = false }

        let trimmedEmail = email.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !trimmedEmail.isEmpty else {
            errorMessage = "Enter your email above first."
            return
        }

        do {
            // Uses your Supabase project's Site URL / redirect settings
            try await supabase.auth.resetPasswordForEmail(trimmedEmail)
            infoMessage = "If an account exists for that email, you’ll receive a reset link shortly."
        } catch {
            errorMessage = friendlyErrorMessage(error)
            print("Auth resetPassword error: \(error)")
        }
    }

    /// Log out
    func signOut() async {
        errorMessage = nil
        infoMessage = nil
        isLoading = true
        defer { isLoading = false }

        do {
            try await supabase.auth.signOut()
            currentSession = nil
            isLoggedIn = false
        } catch {
            errorMessage = "Could not sign out. Please try again."
            print("Auth signOut error: \(error)")
        }
    }

    // MARK: - Internal helpers

    /// Check if a session already exists when the app launches
    private func loadInitialSession() async {
        do {
            let session = try await supabase.auth.session
            self.currentSession = session
            self.isLoggedIn = (session != nil)
        } catch {
            self.currentSession = nil
            self.isLoggedIn = false
            print("No existing session on launch: \(error)")
        }
    }

    /// Refresh our local state from Supabase
    private func refreshSession() async throws {
        do {
            let session = try await supabase.auth.session
            self.currentSession = session
            self.isLoggedIn = (session != nil)
        } catch {
            self.currentSession = nil
            self.isLoggedIn = false
            throw error
        }
    }

    /// Make Supabase errors a bit nicer for end users
    private func friendlyErrorMessage(_ error: Error) -> String {
        let message = error.localizedDescription.lowercased()

        if message.contains("invalid login credentials") {
            return "Incorrect email or password. Please try again."
        }
        if message.contains("rate limit") {
            return "Too many attempts. Please wait a minute and try again."
        }
        if message.contains("user already registered") {
            return "An account already exists for this email. Try logging in instead."
        }

        // Default
        return "Something went wrong. Please try again."
    }
}
