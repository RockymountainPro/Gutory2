//
//  ProfileView.swift
//  Gutory2
//
//  Created by Mac Mantei on 2025-11-18.
//

import SwiftUI
import Supabase

struct ProfileView: View {
    /// Called after the user successfully signs out
    var onSignedOut: () -> Void = {}

    // Persisted user settings
    @AppStorage("profile_display_name") private var displayName: String = ""
    @AppStorage("profile_goals") private var goalsText: String = ""

    // Quick goal chips
    private let quickGoals: [String] = [
        "Reduce bloating",
        "Less abdominal pain",
        "Improve energy",
        "Improve sleep quality",
        "Identify trigger foods",
        "Improve overall gut health"
    ]

    // Save feedback
    @State private var saveStatus: String? = nil
    @State private var saveStatusWorkItem: DispatchWorkItem?

    // Sign-out
    @State private var showSignOutAlert = false
    @State private var isSigningOut = false

    // Name editing
    @State private var isEditingName = false
    @State private var draftName: String = ""

    // Keyboard focus for goals text
    @FocusState private var isGoalsFocused: Bool

    var body: some View {
        NavigationStack {
            ZStack {
                Color.gutoryBackground
                    .ignoresSafeArea()

                ScrollView(showsIndicators: false) {
                    VStack(spacing: 20) {
                        headerCard
                        goalsCard
                        appInfoCard
                        Spacer(minLength: 24)
                    }
                    .padding(.horizontal, 16)   // ✅ align with Reports / History
                    .padding(.top, 16)
                    .padding(.bottom, 32)
                }
                .scrollDismissesKeyboard(.interactively)
            }
            .navigationTitle("Profile")
            .navigationBarTitleDisplayMode(.inline)
            .alert("Sign out of Gutory?", isPresented: $showSignOutAlert) {
                Button("Cancel", role: .cancel) {}

                Button("Sign out", role: .destructive) {
                    Task {
                        await signOut()
                    }
                }
            } message: {
                Text("You can sign back in anytime with the same account.")
            }
            .sheet(isPresented: $isEditingName) {
                nameEditSheet
            }
            .toolbar {
                // Keyboard toolbar
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button {
                        isGoalsFocused = false
                    } label: {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.title3)
                    }
                }
            }
        }
    }

    // MARK: - Header (Whoop-style)

    private var headerCard: some View {
        let trimmedName = displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        let hasName = !trimmedName.isEmpty

        return ZStack {
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(
                    LinearGradient(
                        gradient: Gradient(colors: [
                            Color.gutoryAccent.opacity(0.95),
                            Color.gutoryAccent
                        ]),
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .shadow(radius: 8, y: 4)

            HStack(spacing: 16) {
                ZStack {
                    Circle()
                        .fill(Color.white.opacity(0.22))
                        .frame(width: 54, height: 54)

                    Image(systemName: "person.crop.circle.fill")
                        .font(.system(size: 30))
                        .foregroundColor(.white)
                }

                VStack(alignment: .leading, spacing: 6) {
                    Text(hasName ? trimmedName : "Add your name")
                        .font(.title3.weight(.bold))
                        .foregroundColor(.white)

                    Text("This is how Gutory will refer to you in reports.")
                        .font(.footnote)
                        .foregroundColor(.white.opacity(0.9))
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer()

                Button {
                    draftName = trimmedName
                    isEditingName = true
                } label: {
                    Text("Edit")
                        .font(.footnote.weight(.semibold))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(Color.white.opacity(0.18))
                        .foregroundColor(.white)
                        .clipShape(
                            RoundedRectangle(
                                cornerRadius: 999,
                                style: .continuous
                            )
                        )
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 16)
        }
    }

    // MARK: - Name edit sheet

    private var nameEditSheet: some View {
        NavigationStack {
            Form {
                Section(header: Text("Display name")) {
                    TextField("Your name", text: $draftName)
                        .textInputAutocapitalization(.words)
                        .disableAutocorrection(true)
                        .submitLabel(.done)
                }

                Section(footer: Text("Your name is used only inside the app and AI reports. It’s never public.")) {
                    EmptyView()
                }
            }
            .navigationTitle("Edit name")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        isEditingName = false
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        displayName = draftName.trimmingCharacters(in: .whitespacesAndNewlines)
                        markSaved()
                        isEditingName = false
                    }
                    .disabled(draftName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
    }

    // MARK: - Goals card

    private var goalsCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 8) {
                Image(systemName: "target")
                    .foregroundColor(.gutoryPrimaryText)
                Text("Current Focus")
                    .font(.headline)
                    .foregroundColor(.gutoryPrimaryText)
                Spacer()
            }

            Text("Tell Gutory what you’re working on right now. Your AI reports will gently prioritize these goals when looking for patterns.")
                .font(.footnote)
                .foregroundColor(.gutorySecondaryText)
                .fixedSize(horizontal: false, vertical: true)

            // Quick goal chips
            VStack(alignment: .leading, spacing: 8) {
                Text("Quick picks")
                    .font(.caption)
                    .foregroundColor(.gutorySecondaryText)

                let columns = [
                    GridItem(.flexible(), spacing: 8),
                    GridItem(.flexible(), spacing: 8)
                ]

                LazyVGrid(columns: columns, alignment: .leading, spacing: 8) {
                    ForEach(quickGoals, id: \.self) { goal in
                        goalChip(for: goal)
                    }
                }
            }

            // Freeform goals text
            VStack(alignment: .leading, spacing: 6) {
                Text("In your own words")
                    .font(.caption)
                    .foregroundColor(.gutorySecondaryText)

                ZStack(alignment: .topLeading) {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(Color.gutoryInput)

                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(
                            isGoalsFocused
                            ? Color.gutoryAccent
                            : Color.gutoryAccent.opacity(0.7),
                            lineWidth: isGoalsFocused ? 1.8 : 1.3
                        )

                    TextEditor(text: $goalsText)
                        .font(.footnote)
                        .frame(minHeight: 90, maxHeight: 140)
                        .padding(8)
                        .foregroundColor(.gutoryPrimaryText)
                        .scrollContentBackground(.hidden)
                        .focused($isGoalsFocused)
                        .onChange(of: goalsText) { newValue in
                            let limit = 160
                            if newValue.count > limit {
                                goalsText = String(newValue.prefix(limit))
                            }
                            markSaved()
                        }

                    if goalsText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !isGoalsFocused {
                        Text("Example: \"Reduce bloating and figure out if dairy or gluten are triggers. Support more stable energy through the day.\"")
                            .font(.footnote)
                            .foregroundColor(.gutorySecondaryText.opacity(0.8))
                            .padding(.horizontal, 12)
                            .padding(.vertical, 10)
                    }
                }
                .contentShape(Rectangle())
                .onTapGesture {
                    isGoalsFocused = true
                }
            }

            // Save feedback
            if let status = saveStatus {
                Text(status)
                    .font(.caption2.weight(.semibold))
                    .foregroundColor(.gutoryAccent)
                    .frame(maxWidth: .infinity, alignment: .trailing)
                    .transition(.opacity)
            }

            Text("These goals are stored on your device and passed to the AI when you generate reports. They’re never treated as medical information.")
                .font(.caption2)
                .foregroundColor(.gutorySecondaryText)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(Color.gutoryCard)
                .shadow(radius: 4, y: 2)   // ✅ match Reports / History cards
        )
    }

    // MARK: - Quick goal chip (uniform size)

    private func goalChip(for goal: String) -> some View {
        let trimmedGoal = goal.trimmingCharacters(in: .whitespacesAndNewlines)
        let isSelected = goalsText.localizedCaseInsensitiveContains(trimmedGoal)

        return Button {
            toggleGoal(trimmedGoal)
            markSaved()
        } label: {
            HStack(spacing: 6) {
                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.caption)
                } else {
                    Image(systemName: "circle")
                        .font(.caption2)
                        .opacity(0.6)
                }

                Text(goal)
                    .font(.system(size: 13, weight: isSelected ? .semibold : .regular))
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                    .minimumScaleFactor(0.9)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.vertical, 8)
            .padding(.horizontal, 10)
            .frame(maxWidth: .infinity,
                   minHeight: 60,
                   maxHeight: 60,
                   alignment: .center)
            .background(
                Capsule()
                    .fill(
                        isSelected
                        ? Color.gutoryAccent.opacity(0.16)
                        : Color.gutoryInput
                    )
            )
            .overlay(
                Capsule()
                    .stroke(
                        isSelected ? Color.gutoryAccent : Color.gutoryDivider,
                        lineWidth: isSelected ? 1.6 : 1.0
                    )
            )
            .foregroundColor(isSelected ? Color.gutoryAccent : Color.gutoryPrimaryText)
        }
        .buttonStyle(.plain)
    }

    private func toggleGoal(_ goal: String) {
        var current = goalsText
            .replacingOccurrences(of: "\n", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        if current.isEmpty {
            current = goal
        } else if current.localizedCaseInsensitiveContains(goal) {
            current = current.replacingOccurrences(
                of: goal,
                with: "",
                options: .caseInsensitive,
                range: nil
            )
            while current.contains("  ") {
                current = current.replacingOccurrences(of: "  ", with: " ")
            }
            current = current.trimmingCharacters(in: .whitespacesAndNewlines)
            if current.hasSuffix(",") { current.removeLast() }
        } else {
            if !current.hasSuffix(",") && !current.hasSuffix(" ") {
                current += ", "
            }
            current += goal
        }

        let limit = 160
        if current.count > limit {
            current = String(current.prefix(limit))
        }

        goalsText = current
    }

    // MARK: - App info / safety / sign-out

    private var appInfoCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: "info.circle")
                    .foregroundColor(.gutoryPrimaryText)
                Text("About Gutory")
                    .font(.headline)
                    .foregroundColor(.gutoryPrimaryText)
                Spacer()
            }

            Text("Gutory is designed for gut-health journaling and pattern spotting. It does not provide diagnoses, treatment, or medical advice.")
                .font(.footnote)
                .foregroundColor(.gutorySecondaryText)
                .fixedSize(horizontal: false, vertical: true)

            Divider()
                .padding(.vertical, 4)

            VStack(alignment: .leading, spacing: 4) {
                Text("Safety")
                    .font(.subheadline.weight(.semibold))
                    .foregroundColor(.gutoryPrimaryText)

                Text("If you have ongoing symptoms, pain, or concerns about your health, please talk to a healthcare professional. AI reports in Gutory are for personal reflection only.")
                    .font(.caption)
                    .foregroundColor(.gutorySecondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Divider()
                .padding(.vertical, 4)

            // Account / Sign out
            VStack(alignment: .leading, spacing: 8) {
                Text("Account")
                    .font(.subheadline.weight(.semibold))
                    .foregroundColor(.gutoryPrimaryText)

                Button {
                    showSignOutAlert = true
                } label: {
                    HStack {
                        Image(systemName: "rectangle.portrait.and.arrow.right")
                        Text("Sign out")
                        Spacer()
                        if isSigningOut {
                            ProgressView()
                                .scaleEffect(0.7)
                        }
                    }
                    .font(.footnote.weight(.semibold))
                    .foregroundColor(.red)
                    .padding(.vertical, 4)
                }
                .buttonStyle(.plain)
            }

            HStack {
                Text("App version")
                    .font(.caption)
                    .foregroundColor(.gutorySecondaryText)
                Spacer()
                Text(appVersionString)
                    .font(.caption)
                    .foregroundColor(.gutorySecondaryText)
            }
            .padding(.top, 4)
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(Color.gutoryCard)
                .shadow(radius: 4, y: 2)   // ✅ match Reports / History cards
        )
    }

    private var appVersionString: String {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"
        return "v\(version) (\(build))"
    }

    // MARK: - Save feedback helper

    private func markSaved() {
        saveStatusWorkItem?.cancel()

        withAnimation(.easeOut(duration: 0.15)) {
            saveStatus = "Saved"
        }

        let workItem = DispatchWorkItem {
            withAnimation(.easeOut(duration: 0.25)) {
                saveStatus = nil
            }
        }
        saveStatusWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5, execute: workItem)
    }

    // MARK: - Sign out helper

    @MainActor
    private func signOut() async {
        isSigningOut = true
        do {
            try await supabase.auth.signOut()
            print("Signed out of Supabase")

            // Tell parent (RootView) that sign-out is complete
            onSignedOut()
        } catch {
            print("Error signing out:", error)
        }
        isSigningOut = false
    }
}

// MARK: - Preview

#Preview {
    ProfileView()
        .preferredColorScheme(.dark)
}
