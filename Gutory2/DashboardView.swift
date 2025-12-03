//
//  DashboardView.swift
//  Gutory2
//
//  Created by Mac Mantei on 2025-11-16.
//

import SwiftUI
import Supabase

// MARK: - Supabase row model for dashboard

struct DashboardLog: Decodable, Identifiable {
    // Use logDate as a stable ID for now
    var id: String { logDate }

    let logDate: String       // "yyyy-MM-dd"
    let mealsText: String?

    // Gut symptoms (5 sliders)
    let bloating: Int?
    let abdominalPain: Int?
    let gas: Int?
    let stoolQuality: Int?
    let nauseaReflux: Int?

    // Other metrics (kept for future summaries if needed)
    let energyLevel: Int?
    let mood: Int?
    let sleepQuality: Int?

    enum CodingKeys: String, CodingKey {
        case logDate       = "log_date"
        case mealsText     = "meals_text"

        case bloating
        case abdominalPain = "abdominal_pain"
        case gas
        case stoolQuality  = "stool_quality"
        case nauseaReflux  = "nausea_reflux"

        case energyLevel   = "energy_level"
        case mood
        case sleepQuality  = "sleep_quality"
    }
}

// MARK: - Chart support types

private struct TrendPoint: Identifiable {
    let id = UUID()
    let x: CGFloat   // 0...1
    let y: CGFloat   // 0...1  (normalized value)
}

private enum SymptomMetric: String, CaseIterable, Identifiable {
    // Only gut symptoms
    case bloating
    case abdominalPain
    case gas
    case stoolQuality
    case nauseaReflux

    var id: String { rawValue }

    var label: String {
        switch self {
        case .bloating:      return "Bloating"
        case .abdominalPain: return "Abdominal Pain"
        case .gas:           return "Gas"
        case .stoolQuality:  return "Stool Quality"
        case .nauseaReflux:  return "Nausea / Reflux"
        }
    }

    // Gutory-ish palette: green / teal / purple family
    var color: Color {
        switch self {
        case .bloating:
            // main Gutory green
            return Color.gutoryAccent
        case .abdominalPain:
            // warm magenta / raspberry
            return Color(red: 0.90, green: 0.32, blue: 0.54)
        case .gas:
            // orange / amber
            return Color(red: 0.98, green: 0.68, blue: 0.33)
        case .stoolQuality:
            // teal
            return Color(red: 0.12, green: 0.75, blue: 0.72)
        case .nauseaReflux:
            // purple
            return Color(red: 0.62, green: 0.51, blue: 0.96)
        }
    }

    func value(from log: DashboardLog) -> Int? {
        switch self {
        case .bloating:      return log.bloating
        case .abdominalPain: return log.abdominalPain
        case .gas:           return log.gas
        case .stoolQuality:  return log.stoolQuality
        case .nauseaReflux:  return log.nauseaReflux
        }
    }
}

private struct MetricSeries: Identifiable {
    let metric: SymptomMetric
    let points: [TrendPoint]

    var id: String { metric.id }
}

// MARK: - Main Dashboard View

struct DashboardView: View {

    @Environment(\.colorScheme) private var colorScheme

    // Supabase-loaded data
    @State private var isLoading = true
    @State private var loadError: String?
    @State private var recentLogs: [DashboardLog] = []

    // Mascot animation state
    @State private var mascotBreath = false
    @State private var mascotTilt: Double = 0
    @State private var mascotBounce = false

    // Symptom trend chart – which metrics are visible
    @State private var activeMetrics: Set<SymptomMetric> = Set(SymptomMetric.allCases)

    // Recent days expand / collapse
    @State private var showAllRecent = false

    // MARK: - Date helpers

    private var today: Date { Date() }

    private var isoFormatter: DateFormatter {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        f.timeZone = .current
        return f
    }

    private var prettyFormatter: DateFormatter {
        let f = DateFormatter()
        f.dateStyle = .medium
        return f
    }

    private var todayISO: String {
        isoFormatter.string(from: today)
    }

    private func date(from iso: String) -> Date? {
        isoFormatter.date(from: iso)
    }

    // MARK: - Derived values

    /// Today’s log, if it exists
    private var todayLog: DashboardLog? {
        recentLogs.first(where: { $0.logDate == todayISO })
    }

    /// Simple streak over the last 30 days (including today if logged)
    private var streakCount: Int {
        var streak = 0
        let sortedLogs = recentLogs.sorted { $0.logDate > $1.logDate } // newest first
        let logDates = Set(sortedLogs.compactMap { date(from: $0.logDate) }.map { isoFormatter.string(from: $0) })

        for offset in 0..<30 {
            guard let day = Calendar.current.date(byAdding: .day, value: -offset, to: today) else { break }
            let iso = isoFormatter.string(from: day)

            if logDates.contains(iso) {
                streak += 1
            } else {
                if offset > 0 { break }
            }
        }
        return streak
    }

    /// Gut symptom severity score 0...10 based on the 5 gut sliders
    private func severityScore(for log: DashboardLog) -> Double? {
        let components = [
            log.bloating,
            log.abdominalPain,
            log.gas,
            log.stoolQuality,
            log.nauseaReflux
        ].compactMap { $0 }

        guard !components.isEmpty else { return nil }

        let sum = components.reduce(0, +)
        return Double(sum) / Double(components.count)
    }

    /// Average gut symptom severity over last up to 7 logs (0...1 normalized)
    private var averageSymptomScore: Double {
        let logs = recentLogs.prefix(7)
        let scores = logs.compactMap { severityScore(for: $0) }
        guard !scores.isEmpty else { return 0 }

        let avg = scores.reduce(0, +) / Double(scores.count)
        return avg / 10.0
    }

    /// Per-metric chart series for the last ~14 days
    private var metricSeries: [MetricSeries] {
        let logs = recentLogs
            .sorted { $0.logDate < $1.logDate }
            .prefix(14)

        guard !logs.isEmpty else { return [] }

        let count = logs.count

        return SymptomMetric.allCases.compactMap { metric in
            var points: [TrendPoint] = []

            for (index, log) in logs.enumerated() {
                guard let value = metric.value(from: log) else { continue }

                let xNorm: CGFloat
                if count <= 1 {
                    xNorm = 0.5
                } else {
                    xNorm = CGFloat(Double(index) / Double(count - 1))
                }

                let yNorm = CGFloat(Double(value) / 10.0)
                points.append(TrendPoint(x: xNorm, y: yNorm))
            }

            guard !points.isEmpty else { return nil }
            return MetricSeries(metric: metric, points: points)
        }
    }

    // MARK: - Body

    var body: some View {
        NavigationView {
            ZStack {
                Color.gutoryBackground
                    .ignoresSafeArea()

                ScrollView(showsIndicators: false) {
                    VStack(spacing: 18) {

                        headerCard
                        heroLogCard

                        if isLoading {
                            loadingRow
                        } else if let loadError {
                            errorCard(message: loadError)
                        } else if recentLogs.isEmpty {
                            emptyStateCard
                        } else {
                            symptomTrendCard
                            recentLogsCard
                        }

                        Spacer(minLength: 12)
                    }
                    .padding(.horizontal, 16)   // match ReportsView
                    .padding(.top, 16)
                    .padding(.bottom, 32)
                }
            }
            .navigationTitle("Dashboard")
            .navigationBarTitleDisplayMode(.inline)
            .task {
                await loadRecentLogs()
            }
        }
    }

    // MARK: - Header Card

    private var headerCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .center, spacing: 12) {
                Image("GutoryMascot")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 44, height: 44)
                    .clipShape(RoundedRectangle(cornerRadius: 14))
                    .scaleEffect(mascotBreath ? 1.04 : 0.96)
                    .rotationEffect(.degrees(mascotTilt))
                    .offset(y: mascotBounce ? -4 : 0)
                    .animation(
                        .easeInOut(duration: 1.6).repeatForever(autoreverses: true),
                        value: mascotBreath
                    )
                    .animation(
                        .easeOut(duration: 0.25),
                        value: mascotTilt
                    )
                    .animation(
                        .spring(response: 0.35, dampingFraction: 0.45),
                        value: mascotBounce
                    )
                    .onAppear { mascotBreath = true }
                    .onTapGesture {
                        mascotTilt = mascotTilt == 0 ? -8 : 0
                    }

                VStack(alignment: .leading, spacing: 4) {
                    Text("Welcome back")
                        .font(.title3.weight(.semibold))
                        .foregroundColor(.gutoryPrimaryText)

                    Text("Here’s a snapshot of how your gut has been lately.")
                        .font(.subheadline)
                        .foregroundColor(.gutorySecondaryText)
                }

                Spacer()
            }

            if streakCount > 0 {
                Text("You’ve logged \(streakCount) day\(streakCount == 1 ? "" : "s") in a row.")
                    .font(.caption)
                    .foregroundColor(.gutorySecondaryText)
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(Color.gutoryCard)
                .shadow(radius: 4, y: 2)        // SAME as Reports cards
        )
    }

    // MARK: - Hero "Log Today" Banner

    private var heroLogCard: some View {
        let hasToday = (todayLog != nil)

        return NavigationLink {
            // 🔗 New 3-step flow instead of old LogEntryView
            NewLogFlowView(selectedDate: today)
        } label: {
            Group {
                if hasToday {
                    // Logged today: calm card
                    HStack(alignment: .center, spacing: 14) {
                        ZStack {
                            Circle()
                                .fill(Color.gutoryAccent.opacity(0.15))
                                .frame(width: 32, height: 32)

                            Image(systemName: "checkmark")
                                .font(.caption.weight(.bold))
                                .foregroundColor(Color.gutoryAccent)
                        }

                        VStack(alignment: .leading, spacing: 4) {
                            Text("Today is logged")
                                .font(.subheadline.weight(.semibold))
                                .foregroundColor(.gutoryPrimaryText)

                            Text("Tap to review or edit what you ate and how you felt today.")
                                .font(.footnote)
                                .foregroundColor(.gutorySecondaryText)
                                .lineLimit(2)
                        }

                        Spacer()

                        HStack(spacing: 4) {
                            Image(systemName: "pencil")
                                .font(.caption.weight(.semibold))
                            Text("Edit")
                                .font(.footnote.weight(.semibold))
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(
                            Capsule()
                                .fill(Color.gutoryInput)
                        )
                        .foregroundColor(.gutoryPrimaryText)
                    }
                    .padding(16)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(
                        RoundedRectangle(cornerRadius: 24, style: .continuous)
                            .fill(Color.gutoryCard)
                            .shadow(radius: 4, y: 2)
                    )

                } else {
                    // Not logged yet: gradient CTA, same lifted style
                    HStack {
                        VStack(alignment: .leading, spacing: 10) {
                            Text("Log today’s entry")
                                .font(.headline.weight(.semibold))
                                .foregroundColor(.white)

                            Text("Capture today’s meals, symptoms, energy and sleep in a few seconds.")
                                .font(.subheadline)
                                .foregroundColor(Color.white.opacity(0.9))
                                .fixedSize(horizontal: false, vertical: true)

                            HStack {
                                Spacer()
                                HStack(spacing: 6) {
                                    Image(systemName: "plus")
                                        .font(.subheadline.weight(.semibold))
                                    Text("Log now")
                                        .font(.subheadline.weight(.semibold))
                                }
                                .padding(.horizontal, 16)
                                .padding(.vertical, 8)
                                .background(
                                    RoundedRectangle(cornerRadius: 18)
                                        .fill(Color.white)
                                )
                                .foregroundColor(Color(red: 0.00, green: 0.65, blue: 0.72))
                            }
                        }
                        .padding(18)
                    }
                    .frame(maxWidth: .infinity)
                    .background(
                        RoundedRectangle(cornerRadius: 24, style: .continuous)
                            .fill(
                                LinearGradient(
                                    gradient: Gradient(colors: [
                                        Color(red: 0.16, green: 0.82, blue: 0.66),
                                        Color(red: 0.00, green: 0.70, blue: 0.79)
                                    ]),
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                            .shadow(radius: 4, y: 2)
                    )
                }
            }
        }
        .buttonStyle(.plain)
    }

    // MARK: - Loading / Error / Empty

    private var loadingRow: some View {
        HStack(spacing: 8) {
            ProgressView()
            Text("Loading your recent logs…")
                .font(.footnote)
                .foregroundColor(.gutorySecondaryText)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color.gutoryCard)
                .shadow(radius: 4, y: 2)
        )
    }

    private func errorCard(message: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: "exclamationmark.triangle.fill")
                Text("Couldn’t load your dashboard")
                    .font(.subheadline.weight(.semibold))
            }
            .foregroundColor(.red)

            Text(message)
                .font(.footnote)
                .foregroundColor(.gutorySecondaryText)
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(Color.gutoryCard)
                .shadow(radius: 4, y: 2)
        )
    }

    private var emptyStateCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Let’s start tracking")
                .font(.headline)
                .foregroundColor(.gutoryPrimaryText)

            Text("Once you’ve logged a few days, this dashboard will highlight symptom trends and your recent entries.")
                .font(.subheadline)
                .foregroundColor(.gutorySecondaryText)

            NavigationLink {
                // 🔗 New flow for first entry
                NewLogFlowView(selectedDate: today)
            } label: {
                HStack {
                    Image(systemName: "plus.circle.fill")
                    Text("Log your first entry")
                        .fontWeight(.semibold)
                }
                .font(.subheadline)
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(
                    RoundedRectangle(cornerRadius: 14)
                        .fill(Color.gutoryAccent.opacity(0.16))
                )
            }
            .buttonStyle(.plain)
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(Color.gutoryCard)
                .shadow(radius: 4, y: 2)
        )
    }

    // MARK: - Symptom Trend Card

    private var symptomTrendCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: "waveform.path.ecg")
                Text("Symptom trends")
                    .font(.headline)
                Spacer()
                if averageSymptomScore > 0 {
                    Text("Avg last 7 logs: \(Int(averageSymptomScore * 10))/10")
                        .font(.caption)
                        .foregroundColor(.gutorySecondaryText)
                }
            }
            .foregroundColor(.gutoryPrimaryText)

            // Metric toggle chips
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(SymptomMetric.allCases) { metric in
                        let isActive = activeMetrics.contains(metric)

                        Button {
                            if isActive, activeMetrics.count == 1 {
                                return   // keep at least one metric visible
                            }
                            if isActive {
                                activeMetrics.remove(metric)
                            } else {
                                activeMetrics.insert(metric)
                            }
                        } label: {
                            HStack(spacing: 6) {
                                Circle()
                                    .fill(metric.color.opacity(isActive ? 0.9 : 0.3))
                                    .frame(width: 8, height: 8)

                                Text(metric.label)
                                    .font(.caption.weight(.medium))
                            }
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(
                                RoundedRectangle(cornerRadius: 14)
                                    .fill(
                                        isActive
                                        ? metric.color.opacity(0.12)
                                        : Color.gutoryInput
                                    )
                            )
                            .foregroundColor(isActive ? .gutoryPrimaryText : .gutorySecondaryText)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }

            GeometryReader { geo in
                let logsWithGutData = recentLogs.filter { severityScore(for: $0) != nil }
                let totalWidth = geo.size.width
                let totalHeight = geo.size.height

                let leftAxisPadding: CGFloat = 30
                let rightPadding: CGFloat = 12
                let topPadding: CGFloat = 12
                let bottomPadding: CGFloat = 18

                let chartWidth = totalWidth - leftAxisPadding - rightPadding
                let chartHeight = totalHeight - topPadding - bottomPadding

                ZStack {
                    RoundedRectangle(cornerRadius: 16)
                        .fill(Color.gutoryInput)

                    if logsWithGutData.isEmpty {
                        Text("Log a few more days to see symptom trends.")
                            .font(.caption)
                            .foregroundColor(.gutorySecondaryText)
                            .multilineTextAlignment(.center)
                            .padding()
                    } else {
                        // Axis 0–10 on the left
                        let axisColor = Color.gutorySecondaryText.opacity(0.35)
                        let axisX = leftAxisPadding - 8
                        let chartBottomY = topPadding + chartHeight

                        Path { path in
                            path.move(to: CGPoint(x: axisX, y: topPadding))
                            path.addLine(to: CGPoint(x: axisX, y: chartBottomY))
                        }
                        .stroke(axisColor, lineWidth: 0.7)

                        // ticks at 0, 5, 10
                        ForEach([0, 5, 10], id: \.self) { level in
                            let fraction = CGFloat(level) / 10.0
                            let y = topPadding + chartHeight * (1 - fraction)

                            Path { path in
                                path.move(to: CGPoint(x: axisX, y: y))
                                path.addLine(to: CGPoint(x: axisX + 4, y: y))
                            }
                            .stroke(axisColor, lineWidth: 0.7)

                            Text("\(level)")
                                .font(.caption2)
                                .foregroundColor(axisColor)
                                .position(x: axisX - 8, y: y)
                        }

                        // Decide chart type: line for multiple days, bar for single day
                        let sortedLogs = recentLogs.sorted { $0.logDate < $1.logDate }
                        if sortedLogs.count == 1 {
                            // Single-day: vertical rounded bars for each gut symptom,
                            // bottom exactly on the 0 baseline (chartBottomY).
                            let log = sortedLogs[0]
                            let metrics = SymptomMetric.allCases
                            let barCount = metrics.count
                            let barSpacing: CGFloat = chartWidth / CGFloat(max(barCount, 1))
                            let barWidth = barSpacing * 0.5

                            ForEach(Array(metrics.enumerated()), id: \.offset) { index, metric in
                                let xCenter = leftAxisPadding + barSpacing * (CGFloat(index) + 0.5)
                                let value = metric.value(from: log) ?? 0
                                let clamped = max(0, min(value, 10))
                                let heightFraction = CGFloat(clamped) / 10.0
                                let barHeight = chartHeight * heightFraction

                                // Bar is a rounded rectangle whose *bottom* sits at chartBottomY
                                RoundedRectangle(cornerRadius: barWidth / 2, style: .continuous)
                                    .fill(metric.color.opacity(0.9))
                                    .frame(width: barWidth, height: barHeight)
                                    .position(
                                        x: xCenter,
                                        y: chartBottomY - barHeight / 2
                                    )
                            }
                        } else {
                            // Multi-day: lines per metric
                            let seriesList = metricSeries
                            let lineWidth: CGFloat = 2

                            ForEach(seriesList) { series in
                                if activeMetrics.contains(series.metric) {
                                    Path { path in
                                        for (index, point) in series.points.enumerated() {
                                            let x = leftAxisPadding + point.x * chartWidth
                                            let y = topPadding + (1 - point.y) * chartHeight

                                            if index == 0 {
                                                path.move(to: CGPoint(x: x, y: y))
                                            } else {
                                                path.addLine(to: CGPoint(x: x, y: y))
                                            }
                                        }
                                    }
                                    .stroke(series.metric.color.opacity(0.9), lineWidth: lineWidth)

                                    ForEach(series.points) { point in
                                        let x = leftAxisPadding + point.x * chartWidth
                                        let y = topPadding + (1 - point.y) * chartHeight

                                        Circle()
                                            .fill(series.metric.color.opacity(0.95))
                                            .frame(width: 6, height: 6)
                                            .position(x: x, y: y)
                                    }
                                }
                            }
                        }
                    }
                }
            }
            .frame(height: 190)
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(Color.gutoryCard)
                .shadow(radius: 4, y: 2)
        )
    }

    // MARK: - Recent Days (max 3 collapsed, expandable)

    private var recentLogsCard: some View {
        let sorted = recentLogs.sorted { $0.logDate > $1.logDate } // newest first
        let maxCollapsed = 3
        let logsToShow: [DashboardLog] = showAllRecent ? sorted : Array(sorted.prefix(maxCollapsed))

        return VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("Recent days")
                    .font(.headline)
                    .foregroundColor(.gutoryPrimaryText)

                Spacer()

                if sorted.count > maxCollapsed {
                    Button {
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                            showAllRecent.toggle()
                        }
                    } label: {
                        Text(showAllRecent ? "Show less" : "Show more")
                            .font(.caption.weight(.semibold))
                    }
                    .buttonStyle(.plain)
                    .foregroundColor(.gutoryAccent)
                }
            }

            ForEach(logsToShow) { log in
                NavigationLink {
                    // 🔗 Use new flow when tapping a past day
                    let selected = date(from: log.logDate) ?? today
                    NewLogFlowView(selectedDate: selected)
                } label: {
                    VStack(alignment: .leading, spacing: 10) {
                        HStack {
                            if let d = date(from: log.logDate) {
                                Text(prettyFormatter.string(from: d))
                                    .font(.subheadline)
                                    .fontWeight(.semibold)
                                    .foregroundColor(.gutoryPrimaryText)
                            } else {
                                Text(log.logDate)
                                    .font(.subheadline)
                                    .fontWeight(.semibold)
                                    .foregroundColor(.gutoryPrimaryText)
                            }

                            Spacer()

                            let severity = Int(round(severityScore(for: log) ?? 0))
                            Text("Gut symptom severity: \(severity)/10")
                                .font(.caption)
                                .foregroundColor(.gutorySecondaryText)
                        }

                        // Gradient severity bar with white/dark dash
                        GeometryReader { geo in
                            let width = geo.size.width
                            let severity = Int(round(severityScore(for: log) ?? 0))
                            let ratio = CGFloat(severity) / 10.0
                            let markerWidth: CGFloat = 4

                            ZStack(alignment: .leading) {
                                Capsule()
                                    .fill(
                                        LinearGradient(
                                            gradient: Gradient(colors: [
                                                Color.green,
                                                Color.yellow,
                                                Color.orange,
                                                Color.red
                                            ]),
                                            startPoint: .leading,
                                            endPoint: .trailing
                                        )
                                    )

                                let markerColor: Color = {
                                    switch colorScheme {
                                    case .dark:
                                        return .white
                                    default:
                                        return Color.black.opacity(0.7)
                                    }
                                }()

                                Capsule()
                                    .fill(markerColor)
                                    .frame(width: markerWidth)
                                    .offset(x: max(0, min(width - markerWidth, width * ratio - markerWidth / 2)))
                            }
                        }
                        .frame(height: 10)

                        if let text = log.mealsText, !text.isEmpty {
                            Text(text)
                                .font(.footnote)
                                .foregroundColor(.gutorySecondaryText)
                                .lineLimit(2)
                        }
                    }
                    .padding(12)
                    .background(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .fill(Color.gutoryInput)
                    )
                }
                .buttonStyle(.plain)
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(Color.gutoryCard)
                .shadow(radius: 4, y: 2)
        )
    }

    // MARK: - Supabase load

    private func loadRecentLogs() async {
        guard let user = supabase.auth.currentUser else {
            await MainActor.run {
                self.isLoading = false
                self.loadError = "Not signed in to Supabase."
                self.mascotBounce = false
            }
            return
        }

        let f = isoFormatter
        let today = Date()
        let thirtyDaysAgo = Calendar.current.date(byAdding: .day, value: -30, to: today) ?? today
        let fromDateString = f.string(from: thirtyDaysAgo)
        let toDateString = f.string(from: today)

        await MainActor.run {
            self.isLoading = true
            self.loadError = nil
            self.mascotBounce = true
        }

        do {
            let response: PostgrestResponse<[DashboardLog]> = try await supabase
                .from("daily_logs")
                .select()
                .eq("user_id", value: user.id)
                .gte("log_date", value: fromDateString)
                .lte("log_date", value: toDateString)
                .order("log_date", ascending: false)
                .execute()

            let rows = response.value

            await MainActor.run {
                self.recentLogs = rows
                self.isLoading = false
                self.loadError = nil
                self.mascotBounce = false
                print("Dashboard: loaded \(rows.count) logs from Supabase")
            }
        } catch {
            await MainActor.run {
                self.isLoading = false
                self.loadError = "Failed to load logs."
                self.mascotBounce = false
                print("Dashboard load error:", error)
            }
        }
    }
}

// MARK: - Preview

#Preview {
    DashboardView()
        .preferredColorScheme(.light)
}
