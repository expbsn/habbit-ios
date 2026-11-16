//
//  LeaderboardView.swift
//  Stick
//
//  Weekly/monthly leaderboard rankings view.
//

import SwiftUI
import SwiftData

struct LeaderboardView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Query private var preferences: [UserPreferences]
    @Query(filter: #Predicate<FriendProfile> { $0.connectionStatus == "accepted" }) private var friends: [FriendProfile]
    @Query private var myProfile: [MyCloudProfile]
    @Query private var habits: [Habit]
    @Query private var skippedDays: [SkippedDay]

    @State private var selectedPeriod: LeaderboardPeriod = .weekly
    @State private var selectedFriend: FriendProfile?

    enum LeaderboardPeriod: String, CaseIterable {
        case weekly
        case monthly

        var localizedName: String {
            switch self {
            case .weekly: return String(localized: "friends_leaderboard_weekly")
            case .monthly: return String(localized: "friends_leaderboard_monthly")
            }
        }
    }

    private var accentColor: Color {
        let colorValue = preferences.first?.appAccentColor ?? UserPreferences.adaptiveAccentColor
        if colorValue == UserPreferences.adaptiveAccentColor {
            return Color.primary
        }
        return Color(hex: colorValue)
    }

    private var activeHabits: [Habit] {
        habits.filter { $0.isActive }
    }

    private var skippedDateSet: Set<Date> {
        Set(skippedDays.map { Calendar.current.startOfDay(for: $0.date) })
    }

    private var myCompletion: Double {
        switch selectedPeriod {
        case .weekly:
            return calculateWeeklyAverage()
        case .monthly:
            return calculateMonthlyAverage()
        }
    }

    private var currentStreak: Int {
        let threshold = preferences.first?.streakThreshold ?? 1.0
        return ProgressTracker.calculateStreak(habits: activeHabits, skippedDates: skippedDateSet, threshold: threshold)
    }

    private var sortedFriends: [FriendProfile] {
        switch selectedPeriod {
        case .weekly:
            return friends.sorted(by: FriendProfile.weeklyLeaderboardSort)
        case .monthly:
            return friends.sorted { $0.monthlyAverageCompletion > $1.monthlyAverageCompletion }
        }
    }

    /// Combined leaderboard entries including self
    private var leaderboardEntries: [LeaderboardEntry] {
        var entries: [LeaderboardEntry] = []

        // Add self
        let myEntry = LeaderboardEntry(
            id: "me",
            displayName: myProfile.first?.displayName ?? String(localized: "friends_you"),
            avatarEmoji: myProfile.first?.avatarEmoji ?? "😊",
            completion: myCompletion,
            streak: currentStreak,
            isCurrentUser: true
        )
        entries.append(myEntry)

        // Add friends
        for friend in sortedFriends {
            let completion = selectedPeriod == .weekly ? friend.weeklyAverageCompletion : friend.monthlyAverageCompletion
            let entry = LeaderboardEntry(
                id: friend.cloudUserID,
                displayName: friend.displayName,
                avatarEmoji: friend.avatarEmoji,
                completion: completion,
                streak: friend.currentStreak,
                isCurrentUser: false
            )
            entries.append(entry)
        }

        // Sort by completion
        return entries.sorted { $0.completion > $1.completion }
    }

    var body: some View {
        NavigationStack {
            List {
                // Period Picker
                Section {
                    Picker("", selection: $selectedPeriod) {
                        ForEach(LeaderboardPeriod.allCases, id: \.self) { period in
                            Text(period.localizedName).tag(period)
                        }
                    }
                    .pickerStyle(.segmented)
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets())
                }

                // Podium (Top 3)
                if leaderboardEntries.count >= 3 {
                    Section {
                        podiumView
                            .listRowBackground(Color.clear)
                            .listRowInsets(EdgeInsets())
                    }
                }

                // Full Rankings
                Section {
                    ForEach(Array(leaderboardEntries.enumerated()), id: \.element.id) { index, entry in
                        leaderboardRow(entry: entry, rank: index + 1)
                            .contentShape(Rectangle())
                            .onTapGesture {
                                // Open profile for friends (not current user)
                                if !entry.isCurrentUser {
                                    if let friend = friends.first(where: { $0.cloudUserID == entry.id }) {
                                        selectedFriend = friend
                                    }
                                }
                            }
                            .listRowSeparator(.visible, edges: .bottom)
                            .listRowSeparatorTint(Color(.separator).opacity(0.3))
                    }
                } header: {
                    Text(String(localized: "friends_all_rankings"))
                }
            }
            .listStyle(.insetGrouped)
            .navigationTitle(String(localized: "friends_leaderboard"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(String(localized: "timer_done")) {
                        dismiss()
                    }
                }
            }
            .sheet(item: $selectedFriend) { friend in
                FriendDetailSheet(friend: friend)
            }
        }
    }

    // MARK: - Podium View

    private var podiumView: some View {
        HStack(alignment: .bottom, spacing: 8) {
            // Second place
            if leaderboardEntries.count > 1 {
                podiumPosition(entry: leaderboardEntries[1], rank: 2, height: 80)
            }

            // First place
            if !leaderboardEntries.isEmpty {
                podiumPosition(entry: leaderboardEntries[0], rank: 1, height: 100)
            }

            // Third place
            if leaderboardEntries.count > 2 {
                podiumPosition(entry: leaderboardEntries[2], rank: 3, height: 60)
            }
        }
        .padding(.vertical, 16)
        .frame(maxWidth: .infinity)
    }

    private func podiumPosition(entry: LeaderboardEntry, rank: Int, height: CGFloat) -> some View {
        VStack(spacing: 8) {
            // Avatar
            ZStack {
                Text(entry.avatarEmoji)
                    .font(.system(size: rank == 1 ? 36 : 28))
                    .frame(width: rank == 1 ? 60 : 50, height: rank == 1 ? 60 : 50)
                    .background(Color(.systemGray5))
                    .clipShape(Circle())

                // Crown for first place
                if rank == 1 {
                    Text("👑")
                        .font(.title3)
                        .offset(y: -35)
                }
            }

            Text(entry.displayName)
                .font(.caption.weight(.medium))
                .lineLimit(1)

            Text("\(Int(entry.completion * 100))%")
                .font(.caption2)
                .foregroundStyle(.secondary)

            // Podium block
            RoundedRectangle(cornerRadius: 8)
                .fill(podiumColor(for: rank))
                .frame(width: 70, height: height)
                .overlay(
                    Text("\(rank)")
                        .font(.title2.bold())
                        .foregroundStyle(.white)
                )
        }
        .onTapGesture {
            // Open profile for friends (not current user)
            if !entry.isCurrentUser {
                if let friend = friends.first(where: { $0.cloudUserID == entry.id }) {
                    selectedFriend = friend
                }
            }
        }
    }

    private func podiumColor(for rank: Int) -> Color {
        switch rank {
        case 1: return .yellow.opacity(0.8)
        case 2: return .gray.opacity(0.6)
        case 3: return .orange.opacity(0.6)
        default: return .gray.opacity(0.3)
        }
    }

    // MARK: - Leaderboard Row

    private func leaderboardRow(entry: LeaderboardEntry, rank: Int) -> some View {
        HStack(spacing: 12) {
            // Rank
            Text("\(rank)")
                .font(.headline)
                .foregroundStyle(rankColor(for: rank))
                .frame(width: 28)

            // Avatar
            Text(entry.avatarEmoji)
                .font(.title3)
                .frame(width: 36, height: 36)
                .background(Color(.systemGray5))
                .clipShape(Circle())

            // Name
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 4) {
                    Text(entry.displayName)
                        .font(.body.weight(entry.isCurrentUser ? .semibold : .regular))

                    if entry.isCurrentUser {
                        Text(String(localized: "friends_you_label"))
                            .font(.caption2)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color(.systemGray5))
                            .clipShape(Capsule())
                    }
                }

                HStack(spacing: 4) {
                    Image(systemName: "flame.fill")
                        .font(.caption2)
                        .foregroundStyle(.orange)
                    Text("\(entry.streak)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()

            // Completion
            Text("\(Int(entry.completion * 100))%")
                .font(.headline)
                .foregroundStyle(entry.completion >= 0.9 ? .green : .primary)
        }
        .padding(.vertical, 4)
    }

    private func rankColor(for rank: Int) -> Color {
        switch rank {
        case 1: return .yellow
        case 2: return .gray
        case 3: return .orange
        default: return .secondary
        }
    }

    // MARK: - Calculations

    private func calculateWeeklyAverage() -> Double {
        let calendar = Calendar.current
        guard let weekStart = calendar.dateInterval(of: .weekOfYear, for: Date())?.start else { return 0 }

        var totalProgress: Double = 0
        var daysWithData = 0

        for dayOffset in 0..<7 {
            guard let date = calendar.date(byAdding: .day, value: dayOffset, to: weekStart),
                  date <= Date() else { continue }

            let progress = ProgressTracker.progress(for: date, habits: activeHabits)
            if progress >= 0 {
                totalProgress += progress
                daysWithData += 1
            }
        }

        return daysWithData > 0 ? totalProgress / Double(daysWithData) : 0
    }

    private func calculateMonthlyAverage() -> Double {
        let calendar = Calendar.current
        guard let monthStart = calendar.dateInterval(of: .month, for: Date())?.start else { return 0 }

        var totalProgress: Double = 0
        var daysWithData = 0

        var date = monthStart
        while date <= Date() {
            let progress = ProgressTracker.progress(for: date, habits: activeHabits)
            if progress >= 0 {
                totalProgress += progress
                daysWithData += 1
            }

            guard let nextDate = calendar.date(byAdding: .day, value: 1, to: date) else { break }
            date = nextDate
        }

        return daysWithData > 0 ? totalProgress / Double(daysWithData) : 0
    }
}

// MARK: - Leaderboard Entry

struct LeaderboardEntry: Identifiable {
    let id: String
    let displayName: String
    let avatarEmoji: String
    let completion: Double
    let streak: Int
    let isCurrentUser: Bool
}

#Preview {
    LeaderboardView()
        .modelContainer(.preview)
}
