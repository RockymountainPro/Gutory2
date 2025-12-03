//
//  HistoryView.swift
//  Gutory2
//
//  Created by Mac Mantei on 2025-11-15.
//

import SwiftUI
import Supabase

// Minimal row just to read log_date from Supabase
struct HistoryLogRow: Decodable {
    let logDate: String

    enum CodingKeys: String, CodingKey {
        case logDate = "log_date"
    }
}

struct HistoryView: View {

    // Which month we’re viewing
    @State private var currentMonth: Date = Date()

    // Date we just tapped
    @State private var selectedDate: Date? = nil
    @State private var navigateToLog: Bool = false

    // Set of ISO date strings (“yyyy-MM-dd”) that have a log
    @State private var loggedDates: Set<String> = []

    @State private var isLoading: Bool = false
    @State private var loadError: String?

    // MARK: - Date helpers

    private var calendar: Calendar { Calendar.current }

    private var isoFormatter: DateFormatter {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        f.timeZone = .current
        return f
    }

    private var monthFormatter: DateFormatter {
        let f = DateFormatter()
        f.dateFormat = "MMMM yyyy"
        return f
    }

    private func isoString(from date: Date) -> String {
        isoFormatter.string(from: date)
    }

    // MARK: - Body

    var body: some View {
        NavigationStack {
            ZStack {
                Color.gutoryBackground
                    .ignoresSafeArea()

                VStack(spacing: 0) {

                    // Hidden navigation to NewLogFlowView (replaces LogEntryView)
                    NavigationLink(
                        destination: NewLogFlowView(selectedDate: selectedDate ?? Date()),
                        isActive: $navigateToLog
                    ) {
                        EmptyView()
                    }
                    .hidden()

                    ScrollView(showsIndicators: false) {
                        VStack(spacing: 20) {

                            // Header
                            VStack(alignment: .leading, spacing: 4) {
                                Text("History")
                                    .font(.largeTitle)
                                    .fontWeight(.bold)
                                    .foregroundColor(.gutoryPrimaryText)

                                Text("Tap a day to view or edit its log.")
                                    .font(.subheadline)
                                    .foregroundColor(.gutorySecondaryText)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)

                            // Calendar card
                            calendarCard

                            if isLoading {
                                HStack(spacing: 8) {
                                    ProgressView()
                                    Text("Loading logs…")
                                        .font(.footnote)
                                        .foregroundColor(.gutorySecondaryText)
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                            } else if let loadError {
                                Text(loadError)
                                    .font(.footnote)
                                    .foregroundColor(.red)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }

                            Spacer(minLength: 12)
                        }
                        .padding(.horizontal, 16)
                        .padding(.top, 16)
                        .padding(.bottom, 32)
                    }
                }
            }
            .navigationTitle("History")
            .navigationBarTitleDisplayMode(.inline)
            .task {
                await loadLogsForCurrentMonth()
            }
        }
    }

    // MARK: - Calendar Card

    private var calendarCard: some View {
        let components = calendar.dateComponents([.year, .month], from: currentMonth)
        let monthStart = calendar.date(from: components) ?? Date()
        let range = calendar.range(of: .day, in: .month, for: monthStart) ?? 1..<31
        let daysInMonth = Array(range)

        // How many blank cells before day 1 (0–6)
        let firstWeekday = calendar.component(.weekday, from: monthStart)
        let leadingEmpty = (firstWeekday - calendar.firstWeekday + 7) % 7

        // 7 columns
        let columns = Array(repeating: GridItem(.flexible(), spacing: 0), count: 7)
        let today = calendar.startOfDay(for: Date())

        return VStack(spacing: 16) {

            // Month header
            HStack {
                Button {
                    withAnimation {
                        if let newMonth = calendar.date(byAdding: .month, value: -1, to: currentMonth) {
                            currentMonth = newMonth
                        }
                    }
                    Task { await loadLogsForCurrentMonth() }
                } label: {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundColor(.gutoryPrimaryText)
                        .padding(.trailing, 4)
                }

                Spacer()

                Text(monthFormatter.string(from: currentMonth))
                    .font(.headline)
                    .foregroundColor(.gutoryPrimaryText)

                Spacer()

                Button {
                    withAnimation {
                        if let newMonth = calendar.date(byAdding: .month, value: 1, to: currentMonth) {
                            currentMonth = newMonth
                        }
                    }
                    Task { await loadLogsForCurrentMonth() }
                } label: {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundColor(.gutoryPrimaryText)
                        .padding(.leading, 4)
                }
            }

            // Weekday labels
            let weekdaySymbols = calendar.shortWeekdaySymbols
            HStack {
                ForEach(weekdaySymbols, id: \.self) { day in
                    Text(day.prefix(1))
                        .font(.caption)
                        .foregroundColor(.gutorySecondaryText)
                        .frame(maxWidth: .infinity)
                }
            }

            // Calendar grid
            LazyVGrid(columns: columns, spacing: 16) {
                ForEach(0 ..< leadingEmpty + daysInMonth.count, id: \.self) { index in
                    if index < leadingEmpty {
                        Color.clear
                            .frame(height: 34)
                    } else {
                        let day = daysInMonth[index - leadingEmpty]
                        let date = calendar.date(byAdding: .day, value: day - 1, to: monthStart) ?? monthStart
                        let iso = isoString(from: date)
                        let isLogged = loggedDates.contains(iso)
                        let isSelected = selectedDate.map { calendar.isDate($0, inSameDayAs: date) } ?? false
                        let isToday = calendar.isDateInToday(date)
                        let isFuture = date > today

                        if isFuture {
                            VStack(spacing: 4) {
                                Text("\(day)")
                                    .font(.subheadline)
                                    .foregroundColor(.gutorySecondaryText.opacity(0.4))
                                    .frame(maxWidth: .infinity)

                                Circle()
                                    .fill(Color.clear)
                                    .frame(width: 6, height: 6)
                            }
                            .frame(maxWidth: .infinity)
                            .frame(height: 34)
                        } else {
                            Button {
                                selectedDate = date
                                navigateToLog = true
                            } label: {
                                VStack(spacing: 4) {
                                    Text("\(day)")
                                        .font(.subheadline)
                                        .fontWeight(isSelected ? .semibold : .regular)
                                        .foregroundColor(.gutoryPrimaryText)
                                        .frame(maxWidth: .infinity)

                                    Circle()
                                        .fill(isLogged ? Color.gutoryAccent : Color.clear)
                                        .frame(width: 6, height: 6)
                                }
                                .frame(maxWidth: .infinity)
                                .frame(height: 34)
                                .background(
                                    RoundedRectangle(cornerRadius: 10)
                                        .fill(
                                            isSelected
                                            ? Color.gutoryAccent.opacity(0.12)
                                            : Color.clear
                                        )
                                )
                                .overlay(
                                    RoundedRectangle(cornerRadius: 10)
                                        .stroke(
                                            isToday ? Color.gutoryAccent.opacity(0.6) : Color.clear,
                                            lineWidth: 1
                                        )
                                )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(Color.gutoryCard)
                .shadow(radius: 4, y: 2)   // matches Reports cards
        )
    }

    // MARK: - Supabase load

    private func loadLogsForCurrentMonth() async {
        guard let user = supabase.auth.currentUser else {
            await MainActor.run {
                loggedDates = []
                isLoading = false
                loadError = "Not signed in to Supabase."
            }
            return
        }

        await MainActor.run {
            isLoading = true
            loadError = nil
        }

        let comps = calendar.dateComponents([.year, .month], from: currentMonth)
        let monthStart = calendar.date(from: comps) ?? Date()
        let range = calendar.range(of: .day, in: .month, for: monthStart) ?? 1..<31
        let lastDay = range.upperBound - 1
        let monthEnd = calendar.date(byAdding: .day, value: lastDay - 1, to: monthStart) ?? monthStart

        let startISO = isoString(from: monthStart)
        let endISO = isoString(from: monthEnd)

        do {
            let response: PostgrestResponse<[HistoryLogRow]> = try await supabase
                .from("daily_logs")
                .select("log_date")
                .eq("user_id", value: user.id.uuidString)
                .gte("log_date", value: startISO)
                .lte("log_date", value: endISO)
                .order("log_date", ascending: true)
                .execute()

            let rows = response.value
            let dates = Set(rows.map { $0.logDate })

            await MainActor.run {
                self.loggedDates = dates
                self.isLoading = false
            }
        } catch {
            print("History load error:", error)
            await MainActor.run {
                self.isLoading = false
                self.loadError = "Failed to load month history."
            }
        }
    }
}

#Preview {
    HistoryView()
        .preferredColorScheme(.dark)
}
