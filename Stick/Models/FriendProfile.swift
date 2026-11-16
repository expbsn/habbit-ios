//
//  FriendProfile.swift
//  Stick
//
//  Local cache of friend data from CloudKit.
//

import Foundation
import SwiftData

/// Connection status between two users
enum FriendConnectionStatus: String, Codable {
    case pending = "pending"
    case accepted = "accepted"
    case declined = "declined"
}

/// Locally cached friend profile with their progress data.
/// This is synced from CloudKit and updated periodically.
@Model
final class FriendProfile {
    /// CloudKit user record ID
    var cloudUserID: String = ""

    /// Friend's display name
    var displayName: String = ""

    /// Friend's avatar emoji
    var avatarEmoji: String = "😊"

    /// Connection status with this friend
    var connectionStatus: String = "pending"  // FriendConnectionStatus raw value

    /// Whether we initiated the friend request
    var isInitiator: Bool = true

    /// Today's completion percentage (0.0 - 1.0)
    var todayCompletionPercentage: Double = 0.0

    /// Current streak count
    var currentStreak: Int = 0

    /// Weekly average completion (0.0 - 1.0)
    var weeklyAverageCompletion: Double = 0.0

    /// Monthly average completion (0.0 - 1.0)
    var monthlyAverageCompletion: Double = 0.0

    /// Last time we received updated progress from this friend
    var lastProgressUpdate: Date?

    /// Date the friend connection was created
    var connectionDate: Date = Date()

    /// Date the connection was accepted (nil if pending)
    var acceptedDate: Date?

    /// Friend's top habit name this week
    var topHabitName: String?

    /// Hours spent on habits this week
    var hoursSpentThisWeek: Double = 0.0

    /// Friend's motivational quote
    var motivationalQuote: String?

    /// Past 7 days progress stored as JSON: {"2024-01-15": 0.85, "2024-01-14": 0.92, ...}
    var weekProgressJSON: String?

    init(
        cloudUserID: String,
        displayName: String,
        avatarEmoji: String = "😊",
        connectionStatus: FriendConnectionStatus = .pending,
        isInitiator: Bool = true
    ) {
        self.cloudUserID = cloudUserID
        self.displayName = displayName
        self.avatarEmoji = avatarEmoji
        self.connectionStatus = connectionStatus.rawValue
        self.isInitiator = isInitiator
        self.todayCompletionPercentage = 0.0
        self.currentStreak = 0
        self.weeklyAverageCompletion = 0.0
        self.monthlyAverageCompletion = 0.0
        self.connectionDate = Date()
        self.hoursSpentThisWeek = 0.0
    }

    /// Connection status as enum
    var status: FriendConnectionStatus {
        get { FriendConnectionStatus(rawValue: connectionStatus) ?? .pending }
        set { connectionStatus = newValue.rawValue }
    }

    /// Whether this is an accepted friend connection
    var isAccepted: Bool {
        status == .accepted
    }

    /// Whether this is a pending request we received (not initiated)
    var isPendingIncoming: Bool {
        status == .pending && !isInitiator
    }

    /// Whether this is a pending request we sent
    var isPendingOutgoing: Bool {
        status == .pending && isInitiator
    }

    /// Formatted completion percentage for display
    var formattedTodayCompletion: String {
        "\(Int(todayCompletionPercentage * 100))%"
    }

    /// Badge text for leaderboard ranking
    var rankBadge: String? {
        switch currentStreak {
        case 21...:
            return "🏆"  // Champion
        case 14..<21:
            return "🥇"  // Gold
        case 7..<14:
            return "🥈"  // Silver
        case 3..<7:
            return "🥉"  // Bronze
        default:
            return nil
        }
    }

    /// Progress indicator emoji based on today's completion
    var progressIndicator: String {
        switch todayCompletionPercentage {
        case 1.0:
            return "✅"
        case 0.75..<1.0:
            return "🔥"
        case 0.5..<0.75:
            return "💪"
        case 0.25..<0.5:
            return "🌱"
        default:
            return "⏳"
        }
    }

    // MARK: - Week Progress Helpers

    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()

    /// Get progress for a specific date from stored week data
    func progress(for date: Date) -> Double? {
        // For today, use the live value
        if Calendar.current.isDateInToday(date) {
            return todayCompletionPercentage
        }

        guard let json = weekProgressJSON,
              let data = json.data(using: .utf8),
              let dict = try? JSONDecoder().decode([String: Double].self, from: data) else {
            return nil
        }

        let dateKey = Self.dateFormatter.string(from: date)
        return dict[dateKey]
    }

    /// Set the week progress data from a CloudKit fetch result
    func setWeekProgress(_ progressByDate: [Date: Double]) {
        var dict: [String: Double] = [:]
        for (date, progress) in progressByDate {
            let dateKey = Self.dateFormatter.string(from: date)
            dict[dateKey] = progress
        }

        if let data = try? JSONEncoder().encode(dict),
           let json = String(data: data, encoding: .utf8) {
            weekProgressJSON = json
        }
    }
}

// MARK: - Sorting

extension FriendProfile {
    /// Sort friends by today's completion (descending), then by streak
    static func leaderboardSort(_ lhs: FriendProfile, _ rhs: FriendProfile) -> Bool {
        if lhs.todayCompletionPercentage != rhs.todayCompletionPercentage {
            return lhs.todayCompletionPercentage > rhs.todayCompletionPercentage
        }
        return lhs.currentStreak > rhs.currentStreak
    }

    /// Sort friends by weekly average (descending)
    static func weeklyLeaderboardSort(_ lhs: FriendProfile, _ rhs: FriendProfile) -> Bool {
        if lhs.weeklyAverageCompletion != rhs.weeklyAverageCompletion {
            return lhs.weeklyAverageCompletion > rhs.weeklyAverageCompletion
        }
        return lhs.currentStreak > rhs.currentStreak
    }
}
