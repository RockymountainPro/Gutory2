//
//  NewLogFlowView.swift
//  Gutory2
//
//  3-step guided daily log that reads/writes the `daily_logs` table
//  (Dashboard, History, Reports all plug into the same table).
//

import SwiftUI
import Supabase
import Speech
import AVFoundation
import UIKit

// MARK: - Request model for ai-format-meals edge function

struct MealsFormatRequest: Encodable {
    let rawMeals: String
}

// MARK: - Haptics helper

enum Haptics {
    static func stepChanged() {
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
    }

    static func saveSuccess() {
        UINotificationFeedbackGenerator().notificationOccurred(.success)
    }

    static func saveError() {
        UINotificationFeedbackGenerator().notificationOccurred(.error)
    }

    /// Gentle reward when the user has set all gut metrics at least once.
    static func gutAllSet() {
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }
}

// MARK: - Metric info for tap-to-explain

private enum MetricInfo: Identifiable {
    case gut(GutKind)
    case wellbeing(WellbeingKind)

    var id: String {
        switch self {
        case .gut(let kind): return "gut-\(kind.rawValue)"
        case .wellbeing(let kind): return "well-\(kind.rawValue)"
        }
    }

    enum GutKind: String {
        case bloating, pain, gas, stool, nausea
    }

    enum WellbeingKind: String {
        case energy, calmness, sleep
    }

    var title: String {
        switch self {
        case .gut(.bloating):   return "Bloating"
        case .gut(.pain):       return "Stomach Pain"
        case .gut(.gas):        return "Gas"
        case .gut(.stool):      return "Stool Changes"
        case .gut(.nausea):     return "Nauseau"

        case .wellbeing(.energy):   return "Energy"
        case .wellbeing(.calmness): return "Calmness"
        case .wellbeing(.sleep):    return "Sleep Quality"
        }
    }

    var message: String {
        switch self {
        case .gut(.bloating):
            return "How full, swollen, or tight your belly feels."
        case .gut(.pain):
            return "Abdominal pain, cramps, or sharp discomfort."
        case .gut(.gas):
            return "Gas, pressure, or burping that feels uncomfortable."
        case .gut(.stool):
            return "Loose, hard, or unusual changes in your bowel movements."
        case .gut(.nausea):
            return "Nausea, heartburn, or reflux sensations."

        case .wellbeing(.energy):
            return "How energized you felt overall through the day."
        case .wellbeing(.calmness):
            return "How calm and steady you felt vs. keyed up or on edge."
        case .wellbeing(.sleep):
            return "How well and how restfully you slept."
        }
    }
}

// MARK: - Main 3-step flow

struct NewLogFlowView: View {

    // Optional date (for History / Dashboard); defaults to "today".
    var selectedDate: Date? = nil

    /// Optional hook so the parent can react after a successful save
    /// (e.g., switch tabs back to Dashboard).
    var onFinished: (() -> Void)? = nil

    @Environment(\.dismiss) private var dismiss
    @StateObject private var speechRecognizer = SpeechRecognizer()

    // MARK: - Step state

    private enum Step: Int, CaseIterable {
        case food = 0, gut, day
    }

    @State private var step: Step = .food

    // Bounce / snap animation state
    @State private var cardSnap: Bool = true

    // MARK: - Step 1 – food

    @State private var foodNote: String = ""
    @FocusState private var isFoodNoteFocused: Bool
    @State private var lastTranscript: String = ""

    // MARK: - Step 2 – gut (5 metrics)

    @State private var bloating: Double = 5
    @State private var abdominalPain: Double = 5
    @State private var gas: Double = 5
    @State private var stoolChanges: Double = 5
    @State private var nauseaReflux: Double = 5

    /// Track whether each gut metric has been interacted with at least once.
    @State private var gutMetricsTouched = Array(repeating: false, count: 5)
    @State private var gutAllTouchedCelebrated = false

    // MARK: - Step 3 – day (energy + calmness + sleep)

    @State private var energyToday: Double = 5
    @State private var calmnessToday: Double = 5   // higher = calmer
    @State private var sleepToday: Double = 5

    /// Track whether each wellbeing metric has been interacted with.
    @State private var wellbeingMetricsTouched = Array(repeating: false, count: 3)

    // MARK: - Save + AI state

    @State private var isSaving = false
    @State private var saveError: String?

    @State private var isOrganizingWithAI = false
    @State private var aiStatusMessage: String? = nil
    @State private var shimmerPhase: Bool = false

    // MARK: - Info sheet state

    @State private var activeInfo: MetricInfo?

    // MARK: - Date helpers

    private var entryDate: Date { selectedDate ?? Date() }

    private static let isoFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        f.timeZone = .current
        return f
    }()

    private static let prettyFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .long
        return f
    }()

    private var entryISODate: String {
        Self.isoFormatter.string(from: entryDate)
    }

    private var prettyEntryDate: String {
        Self.prettyFormatter.string(from: entryDate)
    }

    // MARK: - Body

    var body: some View {
        ZStack {
            Color.gutoryBackground
                .ignoresSafeArea()

            VStack(spacing: 12) {
                header
                    .padding(.horizontal, 20)
                    .padding(.top, 4)

                cardPages
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .safeAreaInset(edge: .bottom) {
            bottomArea
        }
        .onAppear {
            speechRecognizer.requestPermissions()
        }
        .onChange(of: step) { _ in
            bounceCard()
            Haptics.stepChanged()
        }
        .onChange(of: speechRecognizer.transcript) { newValue in
            appendTranscriptDelta(newValue)
        }
        .alert(item: $activeInfo) { info in
            Alert(
                title: Text(info.title),
                message: Text(info.message),
                dismissButton: .default(Text("Got it"))
            )
        }
        .toolbar {
            // Keyboard toolbar for meals text
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button {
                    isFoodNoteFocused = false
                } label: {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.title3)
                }
            }
        }
        .task {
            // When opened from History/Dashboard, pre-fill if a log already exists
            await loadExistingLogIfAny()
        }
    }

    // MARK: - Header

    private var header: some View {
        VStack(spacing: 8) {
            Text(statusLine(for: step))
                .font(.subheadline.weight(.medium))
                .foregroundColor(.gutorySecondaryText)

            Text(stepSubtitle(for: step))
                .font(.footnote)
                .foregroundColor(.gutorySecondaryText.opacity(0.9))

            progressBar
        }
        .padding(.bottom, 4)
    }

    private func statusLine(for step: Step) -> String {
        switch step {
        case .food:
            return "3-step gut check"
        case .gut:
            return "Nice job – 2 steps to go."
        case .day:
            return "Last step – finish today’s check-in."
        }
    }

    private func stepSubtitle(for step: Step) -> String {
        switch step {
        case .food:
            return "Step 1 of 3 · Meals"
        case .gut:
            return "Step 2 of 3 · Gut symptoms"
        case .day:
            return "Step 3 of 3 · Energy, calmness & sleep"
        }
    }

    private var progressBar: some View {
        HStack(spacing: 10) {
            ForEach(Step.allCases, id: \.rawValue) { s in
                Capsule()
                    .fill(
                        s == step
                        ? Color.gutoryAccent
                        : Color.gutoryDivider
                    )
                    .frame(height: 4)
            }
        }
        .padding(.horizontal, 40)
        .animation(.easeInOut(duration: 0.25), value: step)
    }

    // MARK: - Swipeable pages

    private var cardPages: some View {
        TabView(selection: $step) {
            cardPage { foodStep }
                .tag(Step.food)

            cardPage { gutStep }
                .tag(Step.gut)

            cardPage { dayStep }
                .tag(Step.day)
        }
        .tabViewStyle(.page(indexDisplayMode: .never))
    }

    private func cardPage<Content: View>(
        @ViewBuilder content: () -> Content
    ) -> some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(spacing: 22) {
                content()
            }
            .padding(.vertical, 24)
            .padding(.horizontal, 20)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(Color.gutoryCard)
        .scaleEffect(cardSnap ? 1.0 : 0.98)
    }

    private func bounceCard() {
        cardSnap = false
        withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
            cardSnap = true
        }
    }

    // MARK: - Step 1 – Food

    private var foodStep: some View {
        VStack(alignment: .leading, spacing: 22) {
            VStack(alignment: .leading, spacing: 8) {
                Text("What did you eat today?")
                    .font(.title2.weight(.bold))
                    .foregroundColor(.gutoryPrimaryText)

                Text("Use voice or typing to describe your meals. Tap AI to organize it.")
                    .font(.subheadline)
                    .foregroundColor(.gutorySecondaryText)
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("Meals and drinks")
                    .font(.subheadline.weight(.semibold))
                    .foregroundColor(.gutoryPrimaryText)

                ZStack(alignment: .topLeading) {
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .fill(Color.gutoryInput)

                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .stroke(
                            isFoodNoteFocused
                            ? Color.gutoryAccent
                            : Color.gutoryAccent.opacity(0.7),
                            lineWidth: isFoodNoteFocused ? 1.8 : 1.3
                        )

                    TextEditor(text: $foodNote)
                        .font(.body)
                        .frame(minHeight: 150)
                        .padding(10)
                        .foregroundColor(.gutoryPrimaryText)
                        .scrollContentBackground(.hidden)
                        .focused($isFoodNoteFocused)

                    if foodNote.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !isFoodNoteFocused {
                        Text("Ex: Breakfast – yogurt with granola; Lunch – Korean beef bowl with rice; Snacks – toast, tea…")
                            .font(.callout)
                            .foregroundColor(.gutorySecondaryText.opacity(0.9))
                            .padding(.horizontal, 14)
                            .padding(.top, 12)
                    }
                }
                .contentShape(Rectangle())
                .onTapGesture {
                    isFoodNoteFocused = true
                }
            }

            Button {
                toggleSpeech()
            } label: {
                ZStack {
                    Circle()
                        .fill(Color.gutoryAccent)
                        .frame(width: 64, height: 64)
                        .shadow(color: Color.black.opacity(0.25), radius: 10, y: 6)

                    Image(systemName: speechRecognizer.isRecording ? "stop.fill" : "mic.fill")
                        .font(.title2.bold())
                        .foregroundColor(.white)
                }
            }
            .frame(maxWidth: .infinity, alignment: .center)
            .padding(.top, 8)

            VStack(spacing: 6) {
                organizeWithAIButton

                if let msg = aiStatusMessage {
                    Text(msg)
                        .font(.caption)
                        .foregroundColor(.gutorySecondaryText)
                }
            }
            .padding(.top, 4)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var canRunAI: Bool {
        !foodNote.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !isOrganizingWithAI
    }

    private var organizeWithAIButton: some View {
        Button {
            Task {
                await runAIOrganizeMeals()
            }
        } label: {
            ZStack {
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .fill(Color.gutoryAccent)
                    .shadow(color: Color.black.opacity(0.2), radius: 10, y: 6)

                HStack(spacing: 8) {
                    Image(systemName: "wand.and.stars")
                        .font(.headline.weight(.semibold))

                    Text(isOrganizingWithAI ? "Organizing your log…" : "Organize with AI")
                        .font(.headline.weight(.semibold))
                }
                .foregroundColor(.white)

                if isOrganizingWithAI {
                    Rectangle()
                        .fill(
                            LinearGradient(
                                colors: [
                                    Color.white.opacity(0.0),
                                    Color.white.opacity(0.35),
                                    Color.white.opacity(0.0)
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .rotationEffect(.degrees(20))
                        .offset(x: shimmerPhase ? 220 : -220)
                        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
                        .animation(
                            .linear(duration: 1.0)
                                .repeatForever(autoreverses: false),
                            value: shimmerPhase
                        )
                        .onAppear { shimmerPhase = true }
                        .onDisappear { shimmerPhase = false }
                }
            }
            .frame(height: 54)
        }
        .disabled(!canRunAI)
        .opacity(canRunAI ? 1.0 : 0.5)
    }

    // MARK: - Step 2 – Gut

    private var gutStep: some View {
        VStack(alignment: .leading, spacing: 24) {
            VStack(alignment: .leading, spacing: 4) {
                Text("How is your gut feeling?")
                    .font(.title2.weight(.bold))
                    .foregroundColor(.gutoryPrimaryText)

                Text("Drag each bar to set today’s levels.")
                    .font(.subheadline)
                    .foregroundColor(.gutorySecondaryText)

                Text("0 = none / calm · 10 = very severe")
                    .font(.caption)
                    .foregroundColor(.gutorySecondaryText.opacity(0.9))
            }

            HStack(spacing: 10) {
                VerticalBarMetric(
                    primaryTitle: "Bloating",
                    secondaryTitle: nil,
                    value: $bloating,
                    style: .gutSymptom,
                    isActive: gutMetricsTouched[0],
                    onChanged: { markGutMetricTouched(0) },
                    onTapInfo: { activeInfo = .gut(.bloating) }
                )

                VerticalBarMetric(
                    primaryTitle: "Stomach",
                    secondaryTitle: "Pain",
                    value: $abdominalPain,
                    style: .gutSymptom,
                    isActive: gutMetricsTouched[1],
                    onChanged: { markGutMetricTouched(1) },
                    onTapInfo: { activeInfo = .gut(.pain) }
                )

                VerticalBarMetric(
                    primaryTitle: "Gas",
                    secondaryTitle: nil,
                    value: $gas,
                    style: .gutSymptom,
                    isActive: gutMetricsTouched[2],
                    onChanged: { markGutMetricTouched(2) },
                    onTapInfo: { activeInfo = .gut(.gas) }
                )

                VerticalBarMetric(
                    primaryTitle: "Stool",
                    secondaryTitle: "Changes",
                    value: $stoolChanges,
                    style: .gutSymptom,
                    isActive: gutMetricsTouched[3],
                    onChanged: { markGutMetricTouched(3) },
                    onTapInfo: { activeInfo = .gut(.stool) }
                )

                VerticalBarMetric(
                    primaryTitle: "Nauseau",
                    secondaryTitle: nil,
                    value: $nauseaReflux,
                    style: .gutSymptom,
                    isActive: gutMetricsTouched[4],
                    onChanged: { markGutMetricTouched(4) },
                    onTapInfo: { activeInfo = .gut(.nausea) }
                )
            }
            .frame(height: 220)
            .frame(maxWidth: .infinity)
            .padding(.top, 4)

            Text("Tip: Tap any symptom label for a short explanation.")
                .font(.caption)
                .foregroundColor(.gutorySecondaryText)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func markGutMetricTouched(_ index: Int) {
        guard index >= 0 && index < gutMetricsTouched.count else { return }
        gutMetricsTouched[index] = true

        if !gutAllTouchedCelebrated && gutMetricsTouched.allSatisfy({ $0 }) {
            gutAllTouchedCelebrated = true
            Haptics.gutAllSet()
        }
    }

    // MARK: - Step 3 – Day

    private var dayStep: some View {
        VStack(alignment: .leading, spacing: 24) {
            VStack(alignment: .leading, spacing: 4) {
                Text("How was your day overall?")
                    .font(.title2.weight(.bold))
                    .foregroundColor(.gutoryPrimaryText)

                Text("Energy, calmness, and sleep.")
                    .font(.subheadline)
                    .foregroundColor(.gutorySecondaryText)

                Text("0 = very poor · 10 = excellent")
                    .font(.caption)
                    .foregroundColor(.gutorySecondaryText.opacity(0.9))
            }

            HStack(spacing: 16) {
                VerticalBarMetric(
                    primaryTitle: "Energy",
                    secondaryTitle: nil,
                    value: $energyToday,
                    style: .wellbeing,
                    isActive: wellbeingMetricsTouched[0],
                    onChanged: { markWellbeingMetricTouched(0) },
                    onTapInfo: { activeInfo = .wellbeing(.energy) }
                )

                VerticalBarMetric(
                    primaryTitle: "Calmness",
                    secondaryTitle: nil,
                    value: $calmnessToday,
                    style: .wellbeing,
                    isActive: wellbeingMetricsTouched[1],
                    onChanged: { markWellbeingMetricTouched(1) },
                    onTapInfo: { activeInfo = .wellbeing(.calmness) }
                )

                VerticalBarMetric(
                    primaryTitle: "Sleep",
                    secondaryTitle: "quality",
                    value: $sleepToday,
                    style: .wellbeing,
                    isActive: wellbeingMetricsTouched[2],
                    onChanged: { markWellbeingMetricTouched(2) },
                    onTapInfo: { activeInfo = .wellbeing(.sleep) }
                )
            }
            .frame(height: 220)
            .frame(maxWidth: .infinity)
            .padding(.top, 4)

            VStack(spacing: 10) {
                Text("Tip: Tap any label for a quick description.")
                    .font(.caption)
                    .foregroundColor(.gutorySecondaryText)

                Button {
                    Task { await saveLog() }
                } label: {
                    ZStack {
                        RoundedRectangle(cornerRadius: 24, style: .continuous)
                            .fill(Color.gutoryAccent)
                            .shadow(color: Color.black.opacity(0.18), radius: 10, y: 6)

                        Text(isSaving ? "Saving…" : "Save log")
                            .font(.headline.weight(.semibold))
                            .foregroundColor(.white)
                            .padding(.vertical, 4)
                    }
                    .frame(height: 54)
                }
                .disabled(isSaving)
                .opacity(isSaving ? 0.7 : 1.0)

                if let saveError {
                    Text(saveError)
                        .font(.caption)
                        .foregroundColor(.red)
                        .multilineTextAlignment(.center)
                }
            }
            .padding(.top, 4)

            Text("Log for \(prettyEntryDate)")
                .font(.caption)
                .foregroundColor(.gutorySecondaryText)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func markWellbeingMetricTouched(_ index: Int) {
        guard index >= 0 && index < wellbeingMetricsTouched.count else { return }
        wellbeingMetricsTouched[index] = true
    }

    // MARK: - Bottom area

    private var bottomArea: some View {
        VStack(spacing: 8) {
            Text("Swipe left or right to move through your 3-step gut check.")
                .font(.caption)
                .foregroundColor(.gutorySecondaryText)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 24)
        }
        .padding(.horizontal, 20)
        .padding(.top, 8)
        .padding(.bottom, 12)
        .frame(maxWidth: .infinity)
        .background(
            Color.gutoryBackground
                .opacity(0.97)
                .ignoresSafeArea(edges: .bottom)
        )
    }

    // MARK: - Speech helpers

    private func toggleSpeech() {
        if speechRecognizer.isRecording {
            speechRecognizer.stopTranscribing()
        } else {
            speechRecognizer.resetTranscript()
            lastTranscript = ""
            speechRecognizer.startTranscribing()
        }
    }

    private func appendTranscriptDelta(_ newTranscript: String) {
        guard newTranscript.count >= lastTranscript.count else {
            lastTranscript = newTranscript
            return
        }

        let startIndex = newTranscript.index(newTranscript.startIndex,
                                             offsetBy: lastTranscript.count)
        let delta = String(newTranscript[startIndex...])
        let trimmedDelta = delta.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !trimmedDelta.isEmpty else {
            lastTranscript = newTranscript
            return
        }

        if !foodNote.isEmpty {
            foodNote.append(" ")
        }
        foodNote.append(trimmedDelta)
        lastTranscript = newTranscript
    }

    // MARK: - AI organize

    private func runAIOrganizeMeals() async {
        let raw = foodNote.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !raw.isEmpty else { return }

        await MainActor.run {
            isOrganizingWithAI = true
            aiStatusMessage = "Organizing your log…"
        }

        do {
            let payload = MealsFormatRequest(rawMeals: raw)
            let data = try JSONEncoder().encode(payload)

            struct MealsResponse: Decodable {
                let organizedMeals: String
            }

            let response: MealsResponse = try await supabase.functions.invoke(
                "ai-format-meals",
                options: FunctionInvokeOptions(
                    headers: ["Content-Type": "application/json"],
                    body: data
                )
            )

            await MainActor.run {
                foodNote = response.organizedMeals
                isOrganizingWithAI = false
                aiStatusMessage = "Nicely organized. You can still edit anything."
            }
        } catch {
            print("AI format meals error:", error)
            await MainActor.run {
                isOrganizingWithAI = false
                aiStatusMessage = "Couldn’t organize right now. Please try again."
            }
        }
    }

    // MARK: - Load existing log

    private func loadExistingLogIfAny() async {
        guard let user = supabase.auth.currentUser else { return }

        do {
            let response: PostgrestResponse<[DailyLogPayload]> = try await supabase
                .from("daily_logs")
                .select()
                .eq("user_id", value: user.id.uuidString)
                .eq("log_date", value: entryISODate)
                .limit(1)
                .execute()

            if let existing = response.value.first {
                await MainActor.run {
                    applyExistingLog(existing)
                }
            }
        } catch {
            print("NewLogFlow load existing error:", error)
        }
    }

    private func applyExistingLog(_ log: DailyLogPayload) {
        if let text = log.mealsText {
            foodNote = text
        }

        if let v = log.bloating {
            bloating = Double(v)
            gutMetricsTouched[0] = true
        }
        if let v = log.abdominalPain {
            abdominalPain = Double(v)
            gutMetricsTouched[1] = true
        }
        if let v = log.gas {
            gas = Double(v)
            gutMetricsTouched[2] = true
        }
        if let v = log.stoolQuality {
            stoolChanges = Double(v)
            gutMetricsTouched[3] = true
        }
        if let v = log.nauseaReflux {
            nauseaReflux = Double(v)
            gutMetricsTouched[4] = true
        }

        if let v = log.energyLevel {
            energyToday = Double(v)
            wellbeingMetricsTouched[0] = true
        }

        if let storedStress = log.stressLevel {
            let clamped = max(0, min(10, storedStress))
            calmnessToday = Double(10 - clamped)
            wellbeingMetricsTouched[1] = true
        }

        if let v = log.sleepQuality {
            sleepToday = Double(v)
            wellbeingMetricsTouched[2] = true
        }
    }

    // MARK: - Save to Supabase (UPSERT)

    private func saveLog() async {
        guard let user = supabase.auth.currentUser else {
            await MainActor.run {
                saveError = "Not signed in."
            }
            Haptics.saveError()
            return
        }

        await MainActor.run {
            isSaving = true
            saveError = nil
        }

        let mealsCombined = foodNote.trimmingCharacters(in: .whitespacesAndNewlines)

        // Calmness 0–10 (high = calmer) -> stressLevel 0–10 (high = more stressed)
        let calmRounded = calmnessToday.rounded()
        let storedStress = max(0, min(10, 10 - calmRounded))

        let payload = DailyLogPayload(
            userId: user.id.uuidString,
            logDate: entryISODate,
            mealsText: mealsCombined.isEmpty ? nil : mealsCombined,

            bloating: Int(bloating.rounded()),
            abdominalPain: Int(abdominalPain.rounded()),
            gas: Int(gas.rounded()),
            stoolQuality: Int(stoolChanges.rounded()),
            nauseaReflux: Int(nauseaReflux.rounded()),

            energyLevel: Int(energyToday.rounded()),
            brainFog: nil,
            mood: nil,
            skinQuality: nil,

            sleepQuality: Int(sleepToday.rounded()),
            stressLevel: Int(storedStress),
            waterIntake: nil,
            exerciseLevel: nil
        )

        do {
            _ = try await supabase
                .from("daily_logs")
                .upsert(payload, onConflict: "user_id,log_date")
                .execute()

            await MainActor.run {
                isSaving = false
                saveError = nil
                Haptics.saveSuccess()
                onFinished?()
                dismiss()
            }
        } catch {
            print("NewLogFlow save error:", error)
            await MainActor.run {
                isSaving = false
                saveError = "Couldn’t save your log. Please try again."
                Haptics.saveError()
            }
        }
    }
}

// MARK: - VerticalBarMetric

private struct VerticalBarMetric: View {

    enum Style {
        case gutSymptom
        case wellbeing
    }

    let primaryTitle: String
    let secondaryTitle: String?
    @Binding var value: Double     // 0–10
    let style: Style
    let isActive: Bool
    let onChanged: (() -> Void)?
    let onTapInfo: (() -> Void)?

    private let barCornerRadius: CGFloat = 18

    var body: some View {
        VStack(spacing: 8) {
            VStack(spacing: 0) {
                Text(primaryTitle)
                    .font(.system(size: 13, weight: .semibold))
                if let secondary = secondaryTitle {
                    Text(secondary)
                        .font(.system(size: 12, weight: .semibold))
                }
            }
            .multilineTextAlignment(.center)
            .foregroundColor(.gutoryPrimaryText)
            .frame(maxWidth: .infinity)
            .frame(height: 34)
            .contentShape(Rectangle())
            .onTapGesture { onTapInfo?() }

            GeometryReader { geo in
                let height = geo.size.height

                ZStack(alignment: .bottom) {
                    RoundedRectangle(cornerRadius: barCornerRadius, style: .continuous)
                        .stroke(borderColor, lineWidth: borderWidth)

                    let normalized = max(0, min(10, value)) / 10.0
                    let rawHeight = height * CGFloat(normalized)
                    let finalHeight: CGFloat = normalized == 0 ? 0 : max(10, rawHeight)

                    RoundedRectangle(cornerRadius: barCornerRadius, style: .continuous)
                        .fill(fillGradient)
                        .frame(height: finalHeight)
                        .clipShape(
                            RoundedRectangle(cornerRadius: barCornerRadius, style: .continuous)
                        )
                }
                .contentShape(Rectangle())
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { gesture in
                            let y = gesture.location.y
                            let clampedY = min(max(y, 0), height)
                            let progress = 1 - (clampedY / height)
                            let rawValue = Double(progress * 10)
                            let stepped = rawValue.rounded()
                            value = max(0, min(10, stepped))
                            onChanged?()
                        }
                )
            }
            .frame(width: 64)

            Text("\(Int(value.rounded())) / 10")
                .font(.footnote.weight(.semibold))
                .foregroundColor(Color.gutoryAccent)
        }
    }

    private var borderColor: Color {
        isActive ? Color.gutoryAccent : Color.gutoryAccent.opacity(0.35)
    }

    private var borderWidth: CGFloat {
        isActive ? 2.0 : 1.4
    }

    private var fillGradient: LinearGradient {
        switch style {
        case .gutSymptom:
            return LinearGradient(
                colors: [
                    Color(red: 0.64, green: 0.46, blue: 0.99),
                    Color(red: 0.26, green: 0.77, blue: 0.62)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
        case .wellbeing:
            return LinearGradient(
                colors: [
                    Color(red: 0.26, green: 0.77, blue: 0.62),
                    Color(red: 0.64, green: 0.46, blue: 0.99)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
        }
    }
}

// MARK: - Preview

#Preview {
    NavigationStack {
        NewLogFlowView()
            .preferredColorScheme(.dark)
            .navigationTitle("Daily Log")
            .navigationBarTitleDisplayMode(.inline)
    }
}
