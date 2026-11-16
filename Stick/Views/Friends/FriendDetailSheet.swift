//
//  FriendDetailSheet.swift
//  Stick
//
//  Detailed profile view of a friend.
//

import SwiftUI
import SwiftData

struct FriendDetailSheet: View {
    let friend: FriendProfile

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Query private var preferences: [UserPreferences]
    @StateObject private var cloudKitService = CloudKitService.shared
    @StateObject private var friendSyncService = FriendSyncService.shared

    @State private var showingRemoveConfirmation = false

    private var accentColor: Color {
        let colorValue = preferences.first?.appAccentColor ?? UserPreferences.adaptiveAccentColor
        if colorValue == UserPreferences.adaptiveAccentColor {
            return Color.primary
        }
        return Color(hex: colorValue)
    }

    /// Formatted hours for display
    private var formattedHours: String {
        let hours = friend.hoursSpentThisWeek
        if hours < 1 {
            let minutes = Int(hours * 60)
            return "\(minutes)m"
        } else {
            let wholeHours = Int(hours)
            let minutes = Int((hours - Double(wholeHours)) * 60)
            if minutes > 0 {
                return "\(wholeHours)h \(minutes)m"
            }
            return "\(wholeHours)h"
        }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    // Profile Header
                    profileHeader

                    // Motivational Quote (if set)
                    if let quote = friend.motivationalQuote, !quote.isEmpty {
                        quoteSection(quote)
                    }

                    // Stats Grid
                    statsGrid

                    // Additional Stats
                    additionalStats

                    // Recent Activity
                    progressSection
                }
                .padding()
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle(String(localized: "friends_profile"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        showingRemoveConfirmation = true
                    } label: {
                        Image(systemName: "trash")
                            .foregroundStyle(.red)
                    }
                }
            }
            .alert(
                String(format: String(localized: "friends_remove_confirm_title"), friend.displayName),
                isPresented: $showingRemoveConfirmation
            ) {
                Button(String(localized: "friends_remove"), role: .destructive) {
                    Task {
                        await friendSyncService.removeFriend(friend, context: modelContext)
                        dismiss()
                    }
                }
                Button(String(localized: "settings_cancel"), role: .cancel) {}
            } message: {
                Text(String(localized: "friends_remove_confirm_message"))
            }
            .task {
                // Refresh name/emoji in case the friend changed their profile
                if let refreshed = try? await cloudKitService.fetchUserProfile(userID: friend.cloudUserID) {
                    if friend.displayName != refreshed.displayName || friend.avatarEmoji != refreshed.avatarEmoji {
                        friend.displayName = refreshed.displayName
                        friend.avatarEmoji = refreshed.avatarEmoji
                        try? modelContext.save()
                    }
                }
            }
        }
    }

    // MARK: - Profile Header

    private var profileHeader: some View {
        VStack(spacing: 12) {
            // Avatar
            ZStack {
                Circle()
                    .fill(accentColor.opacity(0.15))
                    .frame(width: 100, height: 100)

                Text(friend.avatarEmoji)
                    .font(.system(size: 50))

                // Rank badge
                if let badge = friend.rankBadge {
                    Text(badge)
                        .font(.title2)
                        .offset(x: 40, y: -40)
                }
            }

            // Name
            Text(friend.displayName)
                .font(.title2.bold())

            // Connection date
            if let acceptedDate = friend.acceptedDate {
                Text(String(format: String(localized: "friends_connected_since"), acceptedDate.formatted(.dateTime.month().year())))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.top, 16)
    }

    // MARK: - Quote Section

    private func quoteSection(_ quote: String) -> some View {
        VStack(spacing: 8) {
            Image(systemName: "quote.opening")
                .font(.title3)
                .foregroundStyle(.secondary)

            Text(quote)
                .font(.body)
                .italic()
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
        }
        .padding()
        .frame(maxWidth: .infinity)
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    // MARK: - Stats Grid

    private var statsGrid: some View {
        HStack(spacing: 12) {
            // Today's Progress
            statCard(
                title: String(localized: "friends_today"),
                value: friend.formattedTodayCompletion,
                icon: "checkmark.circle.fill",
                color: friend.todayCompletionPercentage >= 1.0 ? .green : accentColor
            )

            // Current Streak
            statCard(
                title: String(localized: "friends_streak"),
                value: "\(friend.currentStreak)",
                icon: "flame.fill",
                color: .orange
            )

            // Weekly Average
            statCard(
                title: String(localized: "friends_weekly"),
                value: "\(Int(friend.weeklyAverageCompletion * 100))%",
                icon: "chart.line.uptrend.xyaxis",
                color: .blue
            )
        }
    }

    private func statCard(title: String, value: String, icon: String, color: Color) -> some View {
        VStack(spacing: 8) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundStyle(color)

            Text(value)
                .font(.title3.bold())

            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 16)
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    // MARK: - Additional Stats

    private var additionalStats: some View {
        VStack(spacing: 0) {
            // Top Habit
            if let topHabit = friend.topHabitName, !topHabit.isEmpty {
                additionalStatRow(
                    icon: "star.fill",
                    iconColor: .yellow,
                    title: String(localized: "friends_top_habit"),
                    value: topHabit
                )
                Divider()
                    .padding(.leading, 44)
            }

            // Hours This Week
            additionalStatRow(
                icon: "clock.fill",
                iconColor: .purple,
                title: String(localized: "friends_hours_this_week"),
                value: formattedHours
            )
        }
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private func additionalStatRow(icon: String, iconColor: Color, title: String, value: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundStyle(iconColor)
                .frame(width: 32)

            Text(title)
                .font(.body)

            Spacer()

            Text(value)
                .font(.body.weight(.medium))
                .foregroundStyle(.secondary)
        }
        .padding()
    }

    // MARK: - Progress Section

    private var progressSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(String(localized: "friends_recent_activity"))
                .font(.headline)

            // Today's progress only (we don't have historical data for friends yet)
            HStack(spacing: 8) {
                ForEach(last7Days, id: \.self) { date in
                    ActivityDayCell(
                        date: date,
                        progress: progressForDate(date),
                        isToday: Calendar.current.isDateInToday(date),
                        accentColor: accentColor
                    )
                    .frame(maxWidth: .infinity)
                }
            }
            .padding()
            .background(Color(.secondarySystemGroupedBackground))
            .clipShape(RoundedRectangle(cornerRadius: 12))

            // Note about historical data (only show if some days have no data)
            if last7Days.contains(where: { progressForDate($0) < 0 }) {
                Text(String(localized: "friends_historical_note"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var last7Days: [Date] {
        let calendar = Calendar.current
        return (0..<7).compactMap { offset in
            calendar.date(byAdding: .day, value: -(6 - offset), to: Date())
        }
    }

    /// Get actual progress for a date from stored data
    private func progressForDate(_ date: Date) -> Double {
        // Use the friend's stored progress data (includes today + past days)
        if let progress = friend.progress(for: date) {
            return progress
        }
        // No data available for this date
        return -1 // -1 indicates no data
    }
}

#Preview {
    let friend = FriendProfile(
        cloudUserID: "test123",
        displayName: "Sarah",
        avatarEmoji: "😊",
        connectionStatus: .accepted
    )
    friend.todayCompletionPercentage = 0.85
    friend.currentStreak = 12
    friend.weeklyAverageCompletion = 0.78
    friend.topHabitName = "Morning Meditation"
    friend.hoursSpentThisWeek = 4.5
    friend.motivationalQuote = "Every day is a new opportunity to grow."

    return FriendDetailSheet(friend: friend)
        .modelContainer(.preview)
}
