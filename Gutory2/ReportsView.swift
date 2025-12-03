//  ReportsView.swift
//  Gutory2
//
//  Created by Mac Mantei on 2025-11-16.
//

import SwiftUI
import Supabase
import Combine

// MARK: - Supabase row model for dashboard / reports

struct ReportsDailyLog: Codable, Identifiable {
    // Use logDate as a stable ID (assumes 1 log per day)
    var id: String { logDate }

    let logDate: String         // "yyyy-MM-dd"
    let mealsText: String?      // free-text food / drink log from `meals_text`
    let bloating: Int?
    let abdominalPain: Int?
    let gas: Int?
    let energyLevel: Int?
    let mood: Int?
    let sleepQuality: Int?

    enum CodingKeys: String, CodingKey {
        case logDate       = "log_date"
        case mealsText     = "meals_text"
        case bloating
        case abdominalPain = "abdominal_pain"
        case gas
        case energyLevel   = "energy_level"
        case mood
        case sleepQuality  = "sleep_quality"
    }
}

// MARK: - Locally saved weekly reports model (UserDefaults)

struct SavedWeeklyReport: Identifiable, Codable {
    let id: UUID
    let createdAt: Date
    let periodStart: String      // "yyyy-MM-dd"
    let periodEnd: String        // "yyyy-MM-dd"
    let daysLogged: Int
    let rangeType: String

    // Snapshot of the AI report at that time
    let summary: String
    let keyTakeaways: [String]
    let patterns: [String]
    let actionItems: [String]
}

// MARK: - GutReport (what we show in the UI)

struct GutReport {
    let summary: String
    let keyTakeaways: [String]
    let patterns: [String]
    let actionItems: [String]
}

// MARK: - Date range enum

enum ReportRange: String, CaseIterable, Identifiable {
    case last7Days
    case last30Days
    case allTime
    case custom

    var id: String { rawValue }

    var label: String {
        switch self {
        case .last7Days: return "Last\n7 Days"
        case .last30Days: return "Last 30\nDays"
        case .allTime:    return "All Time"
        case .custom:     return "Custom"
        }
    }

    var shortLabel: String {
        switch self {
        case .last7Days: return "Last 7 Days"
        case .last30Days: return "Last 30 Days"
        case .allTime: return "All Time"
        case .custom: return "Custom"
        }
    }
}

// MARK: - ViewModel

final class ReportsViewModel: ObservableObject {

    // MARK: Published UI state

    @Published var isLoading: Bool = false
    @Published var aiErrorMessage: String? = nil

    @Published var allLogs: [ReportsDailyLog] = []
    @Published var logsInRange: [ReportsDailyLog] = []
    @Published var loggedDaysInRange: Int = 0

    @Published var selectedRange: ReportRange = .last7Days
    @Published var customStartDate: Date = Calendar.current.date(byAdding: .day, value: -6, to: Date()) ?? Date()
    @Published var customEndDate: Date = Date()

    @Published var currentReport: GutReport? = nil

    @Published var savedReports: [SavedWeeklyReport] = []
    @Published var selectedSavedReportID: UUID? = nil

    // MARK: Supabase / configuration

    private let client: SupabaseClient
    private let aiEndpoint: URL
    private var cancellables = Set<AnyCancellable>()

    static let supabaseAnonKey: String = SupabaseConfig.anonKey

    // Local storage key for past reports
    private let storageKey = "gutory_saved_weekly_reports_v1"

    init(client: SupabaseClient = supabase) {
        self.client = client
        self.aiEndpoint = URL(string: "\(SupabaseConfig.url)/functions/v1/generate-gut-report")!
    }

    // MARK: - Public entry points

    @MainActor
    func onAppear() {
        Task {
            loadSavedReportsFromDisk()
            await loadAllLogs()
            updateRangeLogs()
        }
    }

    @MainActor
    func changeRange(_ range: ReportRange) {
        selectedRange = range
        selectedSavedReportID = nil   // back to “live” range view
        updateRangeLogs()
    }

    @MainActor
    func setCustomRange(start: Date, end: Date) {
        customStartDate = start
        customEndDate = end
        selectedRange = .custom
        selectedSavedReportID = nil
        updateRangeLogs()
    }

    @MainActor
    func selectSavedReport(_ report: SavedWeeklyReport) {
        selectedSavedReportID = report.id

        // Restore the saved GutReport snapshot
        currentReport = GutReport(
            summary: report.summary,
            keyTakeaways: report.keyTakeaways,
            patterns: report.patterns,
            actionItems: report.actionItems
        )
    }

    @MainActor
    func generateReportTapped() {
        aiErrorMessage = nil

        guard loggedDaysInRange >= 3 else {
            aiErrorMessage = "Log at least 3 days in the selected range before generating a report."
            return
        }

        let periodLogs = logsInRange.sorted { $0.logDate > $1.logDate }

        isLoading = true
        Task {
            do {
                let report = try await requestAIReport(periodLogs: periodLogs, allLogs: allLogs)
                await MainActor.run {
                    self.currentReport = report
                    self.aiErrorMessage = nil
                    self.selectedSavedReportID = nil   // fresh live report
                }

                // Save a local snapshot for Past Reports
                await MainActor.run {
                    self.addSavedReport(using: periodLogs, range: self.selectedRange, aiReport: report)
                }
            } catch {
                await MainActor.run {
                    self.aiErrorMessage = error.localizedDescription
                    self.currentReport = self.buildPlaceholderReport(from: periodLogs, allLogs: self.allLogs)
                }
            }
            await MainActor.run {
                self.isLoading = false
            }
        }
    }

    // MARK: - Loading logs (Supabase)

    @MainActor
    private func loadAllLogs() async {
        isLoading = true
        defer { isLoading = false }

        do {
            let rows: [ReportsDailyLog] = try await client
                .from("daily_logs")
                .select()
                .order("log_date", ascending: false)
                .execute()
                .value

            allLogs = rows
        } catch {
            aiErrorMessage = "Failed to load logs from Supabase: \(error.localizedDescription)"
            print("Failed to load daily_logs: \(error)")
        }
    }

    // MARK: - Local saved reports (UserDefaults)

    private func loadSavedReportsFromDisk() {
        guard let data = UserDefaults.standard.data(forKey: storageKey) else {
            savedReports = []
            return
        }

        do {
            let decoded = try JSONDecoder().decode([SavedWeeklyReport].self, from: data)
            savedReports = decoded.sorted { $0.createdAt > $1.createdAt }
            print("Loaded \(savedReports.count) saved weekly reports from disk")
        } catch {
            print("Failed to decode saved weekly reports: \(error)")
            savedReports = []
        }
    }

    private func persistSavedReportsToDisk() {
        do {
            let data = try JSONEncoder().encode(savedReports)
            UserDefaults.standard.set(data, forKey: storageKey)
            print("Persisted \(savedReports.count) weekly reports to disk")
        } catch {
            print("Failed to encode saved weekly reports: \(error)")
        }
    }

    private func addSavedReport(
        using periodLogs: [ReportsDailyLog],
        range: ReportRange,
        aiReport: GutReport
    ) {
        guard let startString = periodLogs.last?.logDate,
              let endString = periodLogs.first?.logDate else {
            print("addSavedReport – missing start/end log dates")
            return
        }

        let newReport = SavedWeeklyReport(
            id: UUID(),
            createdAt: Date(),
            periodStart: startString,
            periodEnd: endString,
            daysLogged: periodLogs.count,
            rangeType: range.shortLabel,
            summary: aiReport.summary,
            keyTakeaways: aiReport.keyTakeaways,
            patterns: aiReport.patterns,
            actionItems: aiReport.actionItems
        )

        // Insert at top so newest appears first
        savedReports.insert(newReport, at: 0)
        persistSavedReportsToDisk()
    }

    // MARK: - Compute logs in selected range

    @MainActor
    private func updateRangeLogs() {
        guard !allLogs.isEmpty else {
            logsInRange = []
            loggedDaysInRange = 0
            return
        }

        let calendar = Calendar.current
        let today = Date()

        let filtered: [ReportsDailyLog]

        switch selectedRange {
        case .last7Days:
            let start = calendar.date(byAdding: .day, value: -6, to: today) ?? today
            filtered = filterLogs(from: start, to: today)
        case .last30Days:
            let start = calendar.date(byAdding: .day, value: -29, to: today) ?? today
            filtered = filterLogs(from: start, to: today)
        case .allTime:
            filtered = allLogs
        case .custom:
            filtered = filterLogs(from: customStartDate, to: customEndDate)
        }

        logsInRange = filtered
        loggedDaysInRange = filtered.count
    }

    private func filterLogs(from startDate: Date, to endDate: Date) -> [ReportsDailyLog] {
        let isoFormatter = ISO8601DateFormatter()
        isoFormatter.formatOptions = [.withFullDate]

        let startString = isoFormatter.string(from: startDate)
        let endString = isoFormatter.string(from: endDate)

        return allLogs.filter { log in
            log.logDate >= startString && log.logDate <= endString
        }
    }

    // MARK: - AI networking to Edge Function

    struct AIReportRequest: Encodable {
        let period_logs: [ReportsDailyLog]
        let all_logs: [ReportsDailyLog]
        let goals_text: String?
    }

    struct AIReportResponse: Decodable {
        let summary: String
        let key_takeaways: [String]
        let patterns: [String]
        let action_items: [String]

        func toModel() -> GutReport {
            GutReport(
                summary: summary,
                keyTakeaways: key_takeaways,
                patterns: patterns,
                actionItems: action_items
            )
        }
    }

    private func requestAIReport(
        periodLogs: [ReportsDailyLog],
        allLogs: [ReportsDailyLog]
    ) async throws -> GutReport {

        var request = URLRequest(url: aiEndpoint)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(
            "Bearer \(ReportsViewModel.supabaseAnonKey)",
            forHTTPHeaderField: "Authorization"
        )

        let goalsText = UserDefaults.standard.string(forKey: "profile_goals")

        let payload = AIReportRequest(
            period_logs: periodLogs,
            all_logs: allLogs,
            goals_text: goalsText?.trimmingCharacters(in: .whitespacesAndNewlines)
        )

        let encoder = JSONEncoder()
        request.httpBody = try encoder.encode(payload)

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse,
              (200...299).contains(httpResponse.statusCode) else {
            let status = (response as? HTTPURLResponse)?.statusCode ?? -1
            throw NSError(
                domain: "GutoryReports",
                code: status,
                userInfo: [
                    NSLocalizedDescriptionKey: "AI backend returned status \(status)."
                ]
            )
        }

        let decoder = JSONDecoder()
        let dto = try decoder.decode(AIReportResponse.self, from: data)
        return dto.toModel()
    }

    // MARK: - Local placeholder report

    private func buildPlaceholderReport(
        from periodLogs: [ReportsDailyLog],
        allLogs: [ReportsDailyLog]
    ) -> GutReport {
        let days = periodLogs.count
        let formatter = DateFormatter()
        formatter.dateStyle = .medium

        let isoFormatter = ISO8601DateFormatter()
        isoFormatter.formatOptions = [.withFullDate]

        let startString = periodLogs.last?.logDate ?? ""
        let endString = periodLogs.first?.logDate ?? ""

        let periodString: String
        if let startDate = isoFormatter.date(from: startString),
           let endDate = isoFormatter.date(from: endString) {
            periodString = "\(formatter.string(from: startDate)) – \(formatter.string(from: endDate))"
        } else {
            periodString = "\(startString) – \(endString)"
        }

        let summary = """
        Over \(days) logged days from \(periodString), we weren’t able to generate a full AI report right now, but you still tracked useful information about your gut, energy, mood, and sleep. Keep logging so future reports can highlight clearer trends.
        """

        return GutReport(
            summary: summary,
            keyTakeaways: [
                "Logging consistently is the most important thing – even a few quick entries per week add up.",
                "Use the History tab to look back at days where you felt especially good or uncomfortable.",
                "As more data builds up, AI reports will be able to spot patterns with meals, tags, and symptoms."
            ],
            patterns: [],
            actionItems: [
                "Keep logging symptoms and meals on most days.",
                "Consider tagging common triggers like dairy, gluten, coffee, or alcohol when you use them.",
                "When you feel ready, generate another report to see updated trends."
            ]
        )
    }
}

// MARK: - View

struct ReportsView: View {
    @StateObject private var viewModel = ReportsViewModel()
    @State private var showingCustomDatePicker: Bool = false
    @State private var showAllPastReports: Bool = false   // collapse/expand

    var body: some View {
        NavigationStack {
            ZStack(alignment: .bottom) {
                Color.gutoryBackground
                    .ignoresSafeArea()

                ScrollView(showsIndicators: false) {
                    VStack(spacing: 20) {
                        headerCard           // gradient hero
                        dateRangeCard        // white date selector card
                        reportCard
                        pastReportsCard
                        Spacer(minLength: 12)
                    }
                    .padding(.horizontal, 16)   // ✅ match Dashboard width
                    .padding(.top, 16)
                    .padding(.bottom, 32)
                }

                if let error = viewModel.aiErrorMessage {
                    errorBanner(error)
                }
            }
            .navigationTitle("Weekly Reports")
            .navigationBarTitleDisplayMode(.inline)
            .onAppear {
                viewModel.onAppear()
            }
        }
    }

    // MARK: - Header (AI banner with CTA) – gradient

    private var headerCard: some View {
        let canGenerate = viewModel.loggedDaysInRange >= 3 && !viewModel.isLoading

        return VStack(alignment: .leading, spacing: 12) {
            // Title
            HStack(spacing: 8) {
                Image(systemName: "sparkles")
                Text("Gutory AI Report")
                    .font(.title2.weight(.bold))
            }
            .foregroundColor(.white)

            Text("Analyze your logs in the selected range for potential gut patterns, triggers, and small wins.")
                .font(.footnote)
                .foregroundColor(.white.opacity(0.9))
                .fixedSize(horizontal: false, vertical: true)

            // Generate button
            VStack(spacing: 4) {
                Button {
                    if canGenerate {
                        viewModel.generateReportTapped()
                    }
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "sparkles")
                        Text(
                            canGenerate
                            ? (viewModel.isLoading ? "Generating…" : "Generate AI Report")
                            : "Keep logging to unlock reports"
                        )
                    }
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .fill(
                                canGenerate
                                ? Color.white.opacity(0.9)
                                : Color.white.opacity(0.18)
                            )
                    )
                    .foregroundColor(
                        canGenerate
                        ? Color.gutoryAccentPurple
                        : Color.white.opacity(0.9)
                    )
                }
                .buttonStyle(.plain)
                .disabled(!canGenerate)

                if !canGenerate {
                    Text("Log at least 3 days in this window to generate your first AI report.")
                        .font(.caption2)
                        .foregroundColor(.white.opacity(0.9))
                        .frame(maxWidth: .infinity, alignment: .center)
                }
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [
                            Color.gutoryAccentPurple,
                            Color.pink
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .shadow(radius: 4, y: 2)
        )
    }

    // MARK: - Date range card (separate white card)

    private var dateRangeCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Date Range")
                .font(.headline)
                .foregroundColor(.gutoryPrimaryText)

            HStack(spacing: 10) {
                rangePill(.last7Days, compact: true)
                rangePill(.last30Days, compact: true)
                rangePill(.allTime, compact: true)
                rangePill(.custom, compact: true)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(rangeString(for: viewModel.selectedRange))
                    .font(.footnote.weight(.medium))
                    .foregroundColor(.gutoryPrimaryText)

                HStack(spacing: 6) {
                    Image(systemName: "calendar")
                        .font(.caption)
                    Text("\(viewModel.loggedDaysInRange) days logged in this range")
                        .font(.caption)
                }
                .foregroundColor(.gutorySecondaryText)
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(Color.gutoryCard)
                .shadow(radius: 4, y: 2)
        )
        .sheet(isPresented: $showingCustomDatePicker) {
            customDatePickerSheet
        }
    }

    // MARK: - Past reports card

    private var pastReportsCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                HStack(spacing: 8) {
                    Image(systemName: "clock.arrow.circlepath")
                    Text("Past Reports")
                        .font(.headline)
                }
                .foregroundColor(.gutoryPrimaryText)
                Spacer()
            }

            if viewModel.savedReports.isEmpty {
                Text("Recently generated reports will appear here so you can revisit past time periods.")
                    .font(.footnote)
                    .foregroundColor(.gutorySecondaryText)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                let reportsToShow: [SavedWeeklyReport] = {
                    if showAllPastReports {
                        return viewModel.savedReports
                    } else {
                        return Array(viewModel.savedReports.prefix(3))
                    }
                }()

                VStack(spacing: 10) {
                    ForEach(reportsToShow) { report in
                        let isSelected = viewModel.selectedSavedReportID == report.id

                        Button {
                            viewModel.selectSavedReport(report)
                        } label: {
                            HStack {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(rangeString(start: report.periodStart, end: report.periodEnd))
                                        .font(.subheadline.weight(.semibold))
                                        .foregroundColor(.gutoryPrimaryText)
                                    Text("\(report.rangeType) • \(report.daysLogged) days logged")
                                        .font(.caption)
                                        .foregroundColor(.gutorySecondaryText)
                                }
                                Spacer()
                                if isSelected {
                                    Text("Viewing")
                                        .font(.caption2.weight(.semibold))
                                        .padding(.vertical, 4)
                                        .padding(.horizontal, 8)
                                        .background(
                                            Capsule()
                                                .fill(Color.gutoryAccent.opacity(0.18))
                                        )
                                        .foregroundColor(.gutoryAccent)
                                } else {
                                    Image(systemName: "chevron.right")
                                        .foregroundColor(.gutorySecondaryText)
                                }
                            }
                            .padding(10)
                            .background(
                                RoundedRectangle(cornerRadius: 16)
                                    .fill(isSelected
                                          ? Color.gutoryAccent.opacity(0.12)
                                          : Color.gutoryDivider.opacity(0.1))
                            )
                        }
                        .buttonStyle(.plain)
                    }

                    if viewModel.savedReports.count > 3 {
                        Button {
                            withAnimation(.spring(response: 0.25, dampingFraction: 0.9)) {
                                showAllPastReports.toggle()
                            }
                        } label: {
                            HStack(spacing: 4) {
                                Text(showAllPastReports
                                     ? "Show fewer"
                                     : "Show all (\(viewModel.savedReports.count))")
                                Image(systemName: showAllPastReports ? "chevron.up" : "chevron.down")
                            }
                            .font(.caption.weight(.semibold))
                            .foregroundColor(Color.gutoryAccent)
                            .frame(maxWidth: .infinity, alignment: .center)
                            .padding(.top, 4)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(Color.gutoryCard)
                .shadow(radius: 4, y: 2)
        )
    }

    // MARK: - Report preview card

    private var reportCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let contextTitle = currentReportContextTitle {
                Text(contextTitle)
                    .font(.caption)
                    .foregroundColor(.gutorySecondaryText)
            }

            HStack(spacing: 8) {
                Image(systemName: "doc.text.magnifyingglass")
                Text("AI Report Preview")
                    .font(.headline)
                Spacer()
            }
            .foregroundColor(.gutoryPrimaryText)

            if let report = viewModel.currentReport {
                ScrollView(showsIndicators: true) {
                    VStack(alignment: .leading, spacing: 16) {
                        Text(report.summary)
                            .font(.body)
                            .foregroundColor(.gutoryPrimaryText)

                        if !report.keyTakeaways.isEmpty {
                            VStack(alignment: .leading, spacing: 6) {
                                HStack(spacing: 6) {
                                    Image(systemName: "checkmark.circle.fill")
                                    Text("Key Takeaways")
                                        .font(.subheadline.weight(.semibold))
                                }
                                .foregroundColor(.gutoryPrimaryText)

                                ForEach(report.keyTakeaways, id: \.self) { item in
                                    HStack(alignment: .top, spacing: 6) {
                                        Circle()
                                            .fill(Color.gutorySecondaryText.opacity(0.7))
                                            .frame(width: 5, height: 5)
                                            .padding(.top, 4)
                                        Text(item)
                                            .font(.footnote)
                                            .foregroundColor(.gutoryPrimaryText)
                                            .fixedSize(horizontal: false, vertical: true)
                                    }
                                }
                            }
                        }

                        if !report.patterns.isEmpty {
                            VStack(alignment: .leading, spacing: 6) {
                                HStack(spacing: 6) {
                                    Image(systemName: "chart.line.uptrend.xyaxis")
                                    Text("Patterns to Watch")
                                        .font(.subheadline.weight(.semibold))
                                }
                                .foregroundColor(.gutoryPrimaryText)

                                ForEach(report.patterns, id: \.self) { item in
                                    Text(item)
                                        .font(.footnote)
                                        .foregroundColor(.gutoryPrimaryText)
                                        .padding(8)
                                        .background(
                                            RoundedRectangle(cornerRadius: 10)
                                                .fill(Color.gutoryDivider.opacity(0.18))
                                        )
                                }
                            }
                        }

                        if !report.actionItems.isEmpty {
                            VStack(alignment: .leading, spacing: 6) {
                                HStack(spacing: 6) {
                                    Image(systemName: "sparkles")
                                    Text("Try This Week")
                                        .font(.subheadline.weight(.semibold))
                                }
                                .foregroundColor(.gutoryPrimaryText)

                                ForEach(report.actionItems, id: \.self) { item in
                                    Text(item)
                                        .font(.footnote)
                                        .foregroundColor(.gutoryPrimaryText)
                                        .padding(8)
                                        .background(
                                            RoundedRectangle(cornerRadius: 10)
                                                .fill(Color.gutoryDivider.opacity(0.18))
                                        )
                                }
                            }
                        }

                        Divider()

                        Text("⚕︎ This is for wellness tracking only and not medical advice. Please talk to a healthcare professional about medical concerns.")
                            .font(.caption2)
                            .foregroundColor(.gutorySecondaryText)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            } else {
                Text("No report yet. Choose a date range above, log at least 3 days, and tap Generate to see your weekly-style gut wellness summary.")
                    .font(.footnote)
                    .foregroundColor(.gutorySecondaryText)
                    .fixedSize(horizontal: false, vertical: true)

                Text("⚕︎ This is for wellness tracking only and not medical advice. Please talk to a healthcare professional about medical concerns.")
                    .font(.caption2)
                    .foregroundColor(.gutorySecondaryText)
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(Color.gutoryCard)
                .shadow(radius: 4, y: 2)
        )
    }

    // MARK: - Range Pill

    private func rangePill(_ range: ReportRange, compact: Bool = false) -> some View {
        let isSelected = viewModel.selectedRange == range
        let size: CGFloat = compact ? 72 : 80

        return Button {
            if range == .custom {
                showingCustomDatePicker = true
            } else {
                viewModel.changeRange(range)
            }
        } label: {
            Text(range.label)
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .font(.footnote.weight(isSelected ? .semibold : .regular))
                .padding(8)
                .frame(width: size, height: size)
                .background(
                    Circle()
                        .fill(
                            isSelected
                            ? Color.gutoryAccentPurple      // selected = purple
                            : Color.gutoryDivider.opacity(0.25)
                        )
                )
                .foregroundColor(isSelected ? Color.white : Color.gutoryPrimaryText)
        }
        .buttonStyle(.plain)
    }

    // MARK: - Custom date picker

    private var customDatePickerSheet: some View {
        NavigationStack {
            Form {
                Section("Custom range") {
                    DatePicker(
                        "Start",
                        selection: Binding(
                            get: { viewModel.customStartDate },
                            set: { viewModel.customStartDate = $0 }
                        ),
                        displayedComponents: .date
                    )

                    DatePicker(
                        "End",
                        selection: Binding(
                            get: { viewModel.customEndDate },
                            set: { viewModel.customEndDate = $0 }
                        ),
                        displayedComponents: .date
                    )
                }
            }
            .navigationTitle("Custom Range")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        showingCustomDatePicker = false
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Apply") {
                        viewModel.setCustomRange(
                            start: viewModel.customStartDate,
                            end: viewModel.customEndDate
                        )
                        showingCustomDatePicker = false
                    }
                }
            }
        }
    }

    // MARK: - Helpers

    private var currentReportContextTitle: String? {
        guard viewModel.currentReport != nil else { return nil }

        if let selectedId = viewModel.selectedSavedReportID,
           let saved = viewModel.savedReports.first(where: { $0.id == selectedId }) {
            return "Currently viewing: \(rangeString(start: saved.periodStart, end: saved.periodEnd)) report"
        } else {
            switch viewModel.selectedRange {
            case .last7Days:
                return "Currently viewing: Last 7 Days report"
            case .last30Days:
                return "Currently viewing: Last 30 Days report"
            case .allTime:
                return "Currently viewing: All-time report"
            case .custom:
                return "Currently viewing: Custom range report"
            }
        }
    }

    private func rangeString(for range: ReportRange) -> String {
        let calendar = Calendar.current
        let today = Date()
        let formatter = DateFormatter()
        formatter.dateStyle = .medium

        switch range {
        case .last7Days:
            if let start = calendar.date(byAdding: .day, value: -6, to: today) {
                return "\(formatter.string(from: start)) – \(formatter.string(from: today))"
            }
        case .last30Days:
            if let start = calendar.date(byAdding: .day, value: -29, to: today) {
                return "\(formatter.string(from: start)) – \(formatter.string(from: today))"
            }
        case .allTime:
            return "All available logs"
        case .custom:
            return "\(formatter.string(from: viewModel.customStartDate)) – \(formatter.string(from: viewModel.customEndDate))"
        }
        return ""
    }

    private func rangeString(start: String, end: String) -> String {
        let isoFormatter = ISO8601DateFormatter()
        isoFormatter.formatOptions = [.withFullDate]

        let displayFormatter = DateFormatter()
        displayFormatter.dateStyle = .medium

        if let startDate = isoFormatter.date(from: start),
           let endDate = isoFormatter.date(from: end) {
            return "\(displayFormatter.string(from: startDate)) – \(displayFormatter.string(from: endDate))"
        } else {
            return "\(start) – \(end)"
        }
    }

    private func errorBanner(_ message: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundColor(.white)
                .font(.subheadline)

            Text(message)
                .font(.footnote)
                .foregroundColor(.white)
                .fixedSize(horizontal: false, vertical: true)

            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color.red.opacity(0.9))
        )
        .padding(.horizontal, 16)
        .padding(.bottom, 12)
    }
}

// MARK: - Preview

#Preview {
    ReportsView()
        .preferredColorScheme(.dark)
}
