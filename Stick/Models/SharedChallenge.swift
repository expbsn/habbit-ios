//
//  SharedChallenge.swift
//  Stick
//
//  Local cache of shared challenge data from CloudKit.
//

import Foundation
import SwiftData

/// A shared challenge between two friends.
/// Stored locally and synced from CloudKit.
@Model
final class SharedChallenge {
    /// CloudKit record ID for this challenge
    var cloudRecordID: String?

    /// Unique challenge identifier
    var challengeID: String = ""

    /// CloudKit user ID of the challenge creator
    var creatorUserID: String = ""

    /// CloudKit user ID of the invited participant
    var participantUserID: String = ""

    /// Name of the habit being challenged (e.g., "Morning Meditation")
    var habitName: String = ""

    /// Emoji representing the habit
    var habitEmoji: String = ""

    /// Color hex string for the habit display
    var habitColor: String = "#007AFF"

    /// Target number of days for the challenge (e.g., 7, 14, 30)
    var targetDays: Int = 30

    /// Date the challenge starts (set when accepted)
    var startDate: Date?

    /// Date the challenge ends (calculated from startDate + targetDays)
    var endDate: Date?

    /// Current status of the challenge
    var statusRaw: String = "pending"

    /// Date the challenge was created
    var createdDate: Date = Date()

    /// Last time this challenge was synced from CloudKit
    var lastSyncDate: Date?

    // MARK: - Cached Progress Data

    /// Number of days the current user has completed
    var myCompletedDays: Int = 0

    /// Number of days the friend has completed
    var friendCompletedDays: Int = 0

    /// Creator's display name (cached)
    var creatorDisplayName: String?

    /// Creator's avatar emoji (cached)
    var creatorAvatarEmoji: String?

    /// Participant's display name (cached)
    var participantDisplayName: String?

    /// Participant's avatar emoji (cached)
    var participantAvatarEmoji: String?

    // MARK: - Extended Habit Settings

    /// Optional description for the challenge habit
    var habitDescription: String?

    /// Frequency type raw value (daily, weekly, monthly, customInterval)
    var frequencyRaw: String = "daily"

    /// Scheduled days of week (1=Sunday through 7=Saturday) for weekly-specific habits
    var scheduledDays: [Int] = []

    /// Number of times per week for flexible weekly habits
    var weeklyRepetitions: Int?

    /// Number of times per month for monthly habits
    var monthlyRepetitions: Int?

    /// Custom interval in days
    var customInterval: Int?

    /// Whether this is a timer-based habit
    var isTimerBased: Bool = false

    /// Target duration in seconds (for timer-based habits)
    var duration: Int?

    /// Target count (for count-based habits)
    var targetCount: Int?

    /// Whether both friends contribute to shared progress (collaborative) or track separately (competitive)
    var isCollaborative: Bool = false

    /// Optional HealthKit data type to auto-complete this challenge (e.g., "steps", "calories", "distance", "workouts")
    var healthKitType: String?

    /// Daily target value for the HealthKit type (e.g., 10000 steps, 500 calories)
    var healthKitTarget: Double?

    init(
        challengeID: String = UUID().uuidString,
        creatorUserID: String,
        participantUserID: String,
        habitName: String,
        habitEmoji: String = "",
        habitColor: String = "#007AFF",
        targetDays: Int = 30
    ) {
        self.challengeID = challengeID
        self.creatorUserID = creatorUserID
        self.participantUserID = participantUserID
        self.habitName = habitName
        self.habitEmoji = habitEmoji
        self.habitColor = habitColor
        self.targetDays = targetDays
        self.statusRaw = ChallengeStatus.pending.rawValue
        self.createdDate = Date()
    }

    // MARK: - Computed Properties

    /// Challenge status as enum
    var status: ChallengeStatus {
        get { ChallengeStatus(rawValue: statusRaw) ?? .pending }
        set { statusRaw = newValue.rawValue }
    }

    /// Whether this challenge is pending acceptance
    var isPending: Bool {
        status == .pending
    }

    /// Whether this challenge is actively being tracked
    var isActive: Bool {
        status == .active
    }

    /// Whether this challenge has ended
    var hasEnded: Bool {
        status.hasEnded
    }

    /// Current day number in the challenge (1-based)
    var currentDay: Int {
        guard let start = startDate else { return 0 }
        let calendar = Calendar.current
        let days = calendar.dateComponents([.day], from: calendar.startOfDay(for: start), to: calendar.startOfDay(for: Date())).day ?? 0
        return min(days + 1, targetDays)
    }

    /// Progress percentage through the challenge duration
    var durationProgress: Double {
        guard targetDays > 0 else { return 0 }
        return Double(currentDay) / Double(targetDays)
    }

    /// Combined completed days (for collaborative mode)
    var combinedCompletedDays: Int {
        myCompletedDays + friendCompletedDays
    }

    /// Progress percentage based on mode (collaborative uses combined, competitive uses individual)
    func completionProgress(for userID: String) -> Double {
        guard targetDays > 0 else { return 0 }
        if isCollaborative {
            return Double(combinedCompletedDays) / Double(targetDays)
        } else {
            return Double(myCompletedDays(for: userID)) / Double(targetDays)
        }
    }

    /// Check if a specific user is the creator
    func isCreator(userID: String) -> Bool {
        creatorUserID == userID
    }

    /// Check if a specific user is the participant
    func isParticipant(userID: String) -> Bool {
        participantUserID == userID
    }

    /// Get the friend's user ID for a given user
    func friendUserID(for currentUserID: String) -> String {
        if creatorUserID == currentUserID {
            return participantUserID
        } else {
            return creatorUserID
        }
    }

    /// Get my completed days count for a given user ID
    func myCompletedDays(for userID: String) -> Int {
        if isCreator(userID: userID) {
            return myCompletedDays
        } else {
            return friendCompletedDays
        }
    }

    /// Get friend's completed days count for a given user ID
    func friendCompletedDays(for userID: String) -> Int {
        if isCreator(userID: userID) {
            return friendCompletedDays
        } else {
            return myCompletedDays
        }
    }

    /// Get the friend's display name for a given user
    func friendDisplayName(for currentUserID: String) -> String {
        if isCreator(userID: currentUserID) {
            return participantDisplayName ?? "Friend"
        } else {
            return creatorDisplayName ?? "Friend"
        }
    }

    /// Get the friend's avatar emoji for a given user
    func friendAvatarEmoji(for currentUserID: String) -> String {
        if isCreator(userID: currentUserID) {
            return participantAvatarEmoji ?? ""
        } else {
            return creatorAvatarEmoji ?? ""
        }
    }

    /// Check if today can still be marked complete
    var canMarkTodayComplete: Bool {
        guard isActive, let start = startDate, let end = endDate else { return false }
        let today = Calendar.current.startOfDay(for: Date())
        let startDay = Calendar.current.startOfDay(for: start)
        let endDay = Calendar.current.startOfDay(for: end)
        return today >= startDay && today <= endDay
    }

    /// Number of days elapsed so far (capped at targetDays)
    var elapsedDays: Int {
        max(1, currentDay)
    }

    /// Completion rate based on elapsed days (how consistent has the user been)
    func completionRate(for userID: String) -> Double {
        guard elapsedDays > 0 else { return 0 }
        return min(1.0, Double(myCompletedDays(for: userID)) / Double(elapsedDays))
    }

    /// Formatted display for current progress (e.g., "Day 12 of 30")
    var progressDisplay: String {
        String(format: String(localized: "challenges_day_x_of_y"), currentDay, targetDays)
    }

    /// Set start and end dates when challenge is accepted
    func activate() {
        let calendar = Calendar.current
        startDate = calendar.startOfDay(for: Date())
        if let start = startDate {
            endDate = calendar.date(byAdding: .day, value: targetDays - 1, to: start)
        }
        status = .active
    }

    /// Mark the challenge as completed
    func markCompleted() {
        status = .completed
    }

    /// Cancel the challenge
    func cancel() {
        status = .cancelled
    }
}

// MARK: - Fetch Helpers

extension SharedChallenge {
    /// Fetch all active challenges for display
    @MainActor
    static func activeChallenges(in context: ModelContext) -> [SharedChallenge] {
        let activeStatus = ChallengeStatus.active.rawValue
        let descriptor = FetchDescriptor<SharedChallenge>(
            predicate: #Predicate { $0.statusRaw == activeStatus },
            sortBy: [SortDescriptor(\.startDate, order: .reverse)]
        )

        do {
            return try context.fetch(descriptor)
        } catch {
            print("Error fetching active challenges: \(error)")
            return []
        }
    }

    /// Fetch all pending challenges (invites)
    @MainActor
    static func pendingChallenges(for userID: String, in context: ModelContext) -> [SharedChallenge] {
        let pendingStatus = ChallengeStatus.pending.rawValue
        let descriptor = FetchDescriptor<SharedChallenge>(
            predicate: #Predicate {
                $0.statusRaw == pendingStatus && $0.participantUserID == userID
            },
            sortBy: [SortDescriptor(\.createdDate, order: .reverse)]
        )

        do {
            return try context.fetch(descriptor)
        } catch {
            print("Error fetching pending challenges: \(error)")
            return []
        }
    }

    /// Count of pending challenge invites
    @MainActor
    static func pendingInviteCount(for userID: String, in context: ModelContext) -> Int {
        pendingChallenges(for: userID, in: context).count
    }
}
