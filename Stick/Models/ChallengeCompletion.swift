//
//  ChallengeCompletion.swift
//  Stick
//
//  Local record of challenge completion for a specific day.
//

import Foundation
import SwiftData

/// A completion record for a challenge on a specific day.
/// Stored locally and synced from CloudKit.
@Model
final class ChallengeCompletion {
    /// CloudKit record ID for this completion
    var cloudRecordID: String?

    /// The challenge this completion belongs to
    var challengeID: String = ""

    /// CloudKit user ID of the user who completed
    var userID: String = ""

    /// The date of completion (normalized to start of day)
    var date: Date = Date()

    /// When the completion was recorded
    var completedAt: Date = Date()

    /// Whether this completion has been synced to CloudKit
    var isSynced: Bool = false

    init(
        challengeID: String,
        userID: String,
        date: Date = Date(),
        completedAt: Date = Date()
    ) {
        self.challengeID = challengeID
        self.userID = userID
        self.date = Calendar.current.startOfDay(for: date)
        self.completedAt = completedAt
        self.isSynced = false
    }

    /// Generate a deterministic record ID for CloudKit
    var deterministicRecordID: String {
        let dayTimestamp = Int(Calendar.current.startOfDay(for: date).timeIntervalSince1970)
        return "cp_\(challengeID)_\(userID)_\(dayTimestamp)"
    }

    /// Check if this completion is for today
    var isToday: Bool {
        Calendar.current.isDateInToday(date)
    }
}

// MARK: - Fetch Helpers

extension ChallengeCompletion {
    /// Fetch all completions for a specific challenge
    @MainActor
    static func completions(for challengeID: String, in context: ModelContext) -> [ChallengeCompletion] {
        let descriptor = FetchDescriptor<ChallengeCompletion>(
            predicate: #Predicate { $0.challengeID == challengeID },
            sortBy: [SortDescriptor(\.date, order: .reverse)]
        )

        do {
            return try context.fetch(descriptor)
        } catch {
            print("Error fetching challenge completions: \(error)")
            return []
        }
    }

    /// Fetch completions for a specific user in a challenge
    @MainActor
    static func completions(for challengeID: String, userID: String, in context: ModelContext) -> [ChallengeCompletion] {
        let descriptor = FetchDescriptor<ChallengeCompletion>(
            predicate: #Predicate { $0.challengeID == challengeID && $0.userID == userID },
            sortBy: [SortDescriptor(\.date, order: .reverse)]
        )

        do {
            return try context.fetch(descriptor)
        } catch {
            print("Error fetching user challenge completions: \(error)")
            return []
        }
    }

    /// Check if a specific date is already completed
    @MainActor
    static func isCompleted(challengeID: String, userID: String, date: Date, in context: ModelContext) -> Bool {
        let dayStart = Calendar.current.startOfDay(for: date)
        let dayEnd = Calendar.current.date(byAdding: .day, value: 1, to: dayStart) ?? dayStart

        let descriptor = FetchDescriptor<ChallengeCompletion>(
            predicate: #Predicate {
                $0.challengeID == challengeID &&
                $0.userID == userID &&
                $0.date >= dayStart &&
                $0.date < dayEnd
            }
        )

        do {
            let count = try context.fetchCount(descriptor)
            return count > 0
        } catch {
            print("Error checking completion: \(error)")
            return false
        }
    }

    /// Count of completed days for a user in a challenge
    @MainActor
    static func completedDaysCount(for challengeID: String, userID: String, in context: ModelContext) -> Int {
        completions(for: challengeID, userID: userID, in: context).count
    }

    /// Fetch unsynced completions
    @MainActor
    static func unsyncedCompletions(in context: ModelContext) -> [ChallengeCompletion] {
        let descriptor = FetchDescriptor<ChallengeCompletion>(
            predicate: #Predicate { !$0.isSynced }
        )

        do {
            return try context.fetch(descriptor)
        } catch {
            print("Error fetching unsynced completions: \(error)")
            return []
        }
    }
}
