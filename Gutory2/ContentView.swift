//
//  ContentView.swift
//  Gutory2
//

import SwiftUI

// MARK: - App color palette

struct AppColors {
    /// Matches your slider / brand green
    static let accent = Color(red: 0.26, green: 0.77, blue: 0.62)
}

// MARK: - Root tab container

struct ContentView: View {
    /// Called when the user finishes signing out (handled in RootView)
    var onSignedOut: () -> Void = {}

    // 0 = Dashboard, 1 = Reports, 2 = Log, 3 = History, 4 = Profile
    @State private var selectedTab: Int = 0

    var body: some View {
        TabView(selection: $selectedTab) {

            DashboardView()
                .tabItem {
                    Label("Dashboard", systemImage: "house.fill")
                }
                .tag(0)

            ReportsView()
                .tabItem {
                    Label("Reports", systemImage: "chart.bar.doc.horizontal")
                }
                .tag(1)

            // UPDATED: Old -> LogEntryView()
            NewLogFlowView()
                .tabItem {
                    Label("Log", systemImage: "plus.circle.fill")
                }
                .tag(2)

            HistoryView()
                .tabItem {
                    Label("History", systemImage: "calendar")
                }
                .tag(3)

            ProfileView(onSignedOut: onSignedOut)
                .tabItem {
                    Label("Profile", systemImage: "person.crop.circle")
                }
                .tag(4)
        }
        .tint(AppColors.accent)
    }
}

#Preview {
    ContentView()
}
