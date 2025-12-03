//
//  RootView.swift
//  Gutory2
//

import SwiftUI
import Supabase

struct RootView: View {
    @State private var isCheckingSession = true
    @State private var isAuthenticated = false

    var body: some View {
        Group {
            if isCheckingSession {
                // Simple loading view
                ZStack {
                    Color(.systemBackground)
                        .ignoresSafeArea()

                    VStack(spacing: 12) {
                        Image("GutoryLogoText")
                            .resizable()
                            .scaledToFit()
                            .frame(width: 180, height: 180)

                        ProgressView()
                            .progressViewStyle(.circular)
                    }
                    .padding(.horizontal, 32)
                }

            } else if isAuthenticated {
                // ✅ When signed in, show tabs and listen for sign-out
                ContentView(onSignedOut: {
                    isAuthenticated = false
                })

            } else {
                // ✅ When not signed in, show onboarding / auth
                OnboardingView {
                    // Called after successful sign-in
                    isAuthenticated = true
                }
            }
        }
        .task {
            await checkExistingSession()
        }
    }

    // MARK: - Check Supabase session on app launch

    private func checkExistingSession() async {
        do {
            let session = try await supabase.auth.session
            await MainActor.run {
                // If your Session type is non-optional, you can just set true.
                isAuthenticated = (session != nil)
                isCheckingSession = false
            }
        } catch {
            print("Error checking session:", error)
            await MainActor.run {
                isAuthenticated = false
                isCheckingSession = false
            }
        }
    }
}

#Preview {
    RootView()
}
