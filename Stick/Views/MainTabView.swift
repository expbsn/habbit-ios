//
//  MainTabView.swift
//  Stick
//
//  Created by Kian Jain on 02.02.26.
//

import SwiftUI
import SwiftData

struct MainTabView: View {
    @Query private var preferences: [UserPreferences]

    private var accentColor: Color {
        let colorValue = preferences.first?.appAccentColor ?? UserPreferences.adaptiveAccentColor
        if colorValue == UserPreferences.adaptiveAccentColor {
            return Color.primary
        }
        return Color(hex: colorValue)
    }

    var body: some View {
        #if os(iOS)
        TabView {
            HabitListView()
                .tabItem {
                    Label(String(localized: "tab_habits"), systemImage: "circle.grid.2x2.fill")
                }

            FriendsView()
                .tabItem {
                    Label(String(localized: "tab_friends"), systemImage: "bubble.fill")
                }

            AnalyticsView()
                .tabItem {
                    Label(String(localized: "tab_analytics"), systemImage: "chart.pie.fill")
                }
        }
        .tint(accentColor)
        #else
        NavigationSplitView {
            List {
                Label(String(localized: "tab_habits"), systemImage: "circle.grid.2x2.fill")
                Label(String(localized: "tab_friends"), systemImage: "bubble.fill")
                Label(String(localized: "tab_analytics"), systemImage: "chart.pie.fill")
            }
            .navigationTitle("Habbit")
        } detail: {
            HabitListView()
        }
        #endif
    }
}

#Preview {
    MainTabView()
        .modelContainer(.preview)
}
