//
//  ChallengeSyncService.swift
//  Stick
//
//  Service for syncing shared challenges with CloudKit.
//

import Foundation
import CloudKit
import SwiftData
import Combine

/// Service responsible for syncing challenge data with CloudKit.
@MainActor
final class ChallengeSyncService: ObservableObject {
    static let shared = ChallengeSyncService()

    // MARK: - Published State

    @Published var isSyncing = false
    @Published var lastSyncDate: Date?
    @Published var pendingInviteCount = 0

    // MARK: - Private Properties

    private let cloudKitService = CloudKitService.shared
    private var lastSyncTimestamp: Date?
    private let syncDebounceInterval: TimeInterval = 15

    private init() {}

    // MARK: - Sync Operations

    /// Force sync without debounce — use when a real-time push arrives
    func syncChallengesNow(context: ModelContext) async {
        lastSyncTimestamp = nil
        await syncChallenges(context: context)
    }

    /// Sync all challenges from CloudKit
    func syncChallenges(context: ModelContext) async {
        guard cloudKitService.isAuthenticated else {
            print("🏆 ChallengeSyncService: Not authenticated, skipping sync")
            return
        }

        // Debounce: skip if we synced recently
        if let last = lastSyncTimestamp, Date().timeIntervalSince(last) < syncDebounceInterval {
            return
        }

        isSyncing = true
        defer { isSyncing = false }

        do {
            let records = try await cloudKitService.fetchChallenges()
            print("🏆 ChallengeSyncService: Fetched \(records.count) challenge records")

            for record in records {
                await processChallengeRecord(record, context: context)
            }

            try context.save()
            lastSyncDate = Date()
            lastSyncTimestamp = Date()

            // Update pending invite count
            if let userID = cloudKitService.currentUserID {
                pendingInviteCount = SharedChallenge.pendingInviteCount(for: userID, in: context)
            }

            // Retry any completions that previously failed to upload
            await retrySyncUnsynced(context: context)

            // Set up silent push subscriptions for each active challenge so the app
            // wakes up when the partner marks a day complete
            if let userID = cloudKitService.currentUserID {
                let activeStatus = ChallengeStatus.active.rawValue
                let activeDescriptor = FetchDescriptor<SharedChallenge>(
                    predicate: #Predicate { $0.statusRaw == activeStatus }
                )
                if let activeChallenges = try? context.fetch(activeDescriptor) {
                    for challenge in activeChallenges {
                        let partnerID = challenge.isCreator(userID: userID)
                            ? challenge.participantUserID
                            : challenge.creatorUserID
                        await cloudKitService.setupChallengeProgressSubscription(
                            challengeID: challenge.challengeID,
                            partnerUserID: partnerID
                        )
                    }
                }
            }

            print("🏆 ChallengeSyncService: Sync complete")
        } catch {
            print("🏆 ChallengeSyncService: Sync failed: \(error)")
        }
    }

    /// Process a single challenge record from CloudKit
    private func processChallengeRecord(_ record: CKRecord, context: ModelContext) async {
        let challengeID = record[CloudKitConfig.Field.challengeID] as? String ?? record.recordID.recordName
        let creatorUserID = record[CloudKitConfig.Field.creatorUserID] as? String ?? ""
        let participantUserID = record[CloudKitConfig.Field.participantUserID] as? String ?? ""
        let statusRaw = record[CloudKitConfig.Field.status] as? String ?? ChallengeStatus.pending.rawValue

        // Check if challenge already exists locally
        let descriptor = FetchDescriptor<SharedChallenge>(
            predicate: #Predicate { $0.challengeID == challengeID }
        )

        do {
            let existing = try context.fetch(descriptor)

            if let challenge = existing.first {
                // Update existing challenge, but don't revert an accepted/declined challenge back to pending.
                // This handles the case where the participant can't write to the creator's CloudKit record.
                let oldStatus = challenge.statusRaw
                let localIsResolved = challenge.statusRaw != ChallengeStatus.pending.rawValue
                let cloudIsPending = statusRaw == ChallengeStatus.pending.rawValue
                if !(localIsResolved && cloudIsPending) {
                    challenge.statusRaw = statusRaw
                }
                challenge.startDate = record[CloudKitConfig.Field.startDate] as? Date
                challenge.endDate = record[CloudKitConfig.Field.endDate] as? Date
                challenge.lastSyncDate = Date()
                challenge.isCollaborative = (record[CloudKitConfig.Field.isCollaborative] as? Int ?? 0) == 1

                if oldStatus != challenge.statusRaw {
                    print("🏆 ChallengeSyncService: Updated \(challenge.habitName) status: \(oldStatus) → \(challenge.statusRaw)")
                }

                // Refresh display names on every sync so name changes propagate
                if let creatorProfile = try? await cloudKitService.fetchUserProfile(userID: creatorUserID) {
                    challenge.creatorDisplayName = creatorProfile.displayName
                    challenge.creatorAvatarEmoji = creatorProfile.avatarEmoji
                }
                if let participantProfile = try? await cloudKitService.fetchUserProfile(userID: participantUserID) {
                    challenge.participantDisplayName = participantProfile.displayName
                    challenge.participantAvatarEmoji = participantProfile.avatarEmoji
                }

                // Sync progress counts
                await syncChallengeProgress(challenge, context: context)
            } else {
                // Create new challenge
                let challenge = SharedChallenge(
                    challengeID: challengeID,
                    creatorUserID: creatorUserID,
                    participantUserID: participantUserID,
                    habitName: record[CloudKitConfig.Field.habitName] as? String ?? "",
                    habitEmoji: record[CloudKitConfig.Field.habitEmoji] as? String ?? "",
                    habitColor: record[CloudKitConfig.Field.habitColor] as? String ?? "#007AFF",
                    targetDays: record[CloudKitConfig.Field.targetDays] as? Int ?? 30
                )

                challenge.cloudRecordID = record.recordID.recordName
                challenge.statusRaw = statusRaw
                challenge.startDate = record[CloudKitConfig.Field.startDate] as? Date
                challenge.endDate = record[CloudKitConfig.Field.endDate] as? Date
                challenge.createdDate = record[CloudKitConfig.Field.createdDate] as? Date ?? Date()
                challenge.lastSyncDate = Date()
                challenge.isCollaborative = (record[CloudKitConfig.Field.isCollaborative] as? Int ?? 0) == 1

                // Fetch profile info for both users
                if let creatorProfile = try? await cloudKitService.fetchUserProfile(userID: creatorUserID) {
                    challenge.creatorDisplayName = creatorProfile.displayName
                    challenge.creatorAvatarEmoji = creatorProfile.avatarEmoji
                }

                if let participantProfile = try? await cloudKitService.fetchUserProfile(userID: participantUserID) {
                    challenge.participantDisplayName = participantProfile.displayName
                    challenge.participantAvatarEmoji = participantProfile.avatarEmoji
                }

                context.insert(challenge)
                print("🏆 ChallengeSyncService: Created new challenge: \(challenge.habitName)")

                // Sync progress counts
                await syncChallengeProgress(challenge, context: context)
            }
        } catch {
            print("🏆 ChallengeSyncService: Error processing challenge record: \(error)")
        }
    }

    /// Sync progress records for a challenge
    func syncChallengeProgress(_ challenge: SharedChallenge, context: ModelContext) async {
        do {
            let records = try await cloudKitService.fetchChallengeProgress(challengeID: challenge.challengeID)

            // Count completions per user
            var creatorCount = 0
            var participantCount = 0

            for record in records {
                let userID = record[CloudKitConfig.Field.userID] as? String ?? ""
                let date = record[CloudKitConfig.Field.date] as? Date ?? Date()

                if userID == challenge.creatorUserID {
                    creatorCount += 1
                } else if userID == challenge.participantUserID {
                    participantCount += 1
                }

                // Store completion locally
                await processChallengeProgressRecord(record, challenge: challenge, context: context)
            }

            // Update cached counts with fixed semantics:
            // myCompletedDays = creator's count, friendCompletedDays = participant's count.
            // The myCompletedDays(for:) / friendCompletedDays(for:) methods handle
            // the per-user perspective translation at display time.
            challenge.myCompletedDays = creatorCount
            challenge.friendCompletedDays = participantCount

            print("🏆 ChallengeSyncService: Synced progress for \(challenge.habitName) - creator: \(creatorCount), participant: \(participantCount)")
        } catch {
            print("🏆 ChallengeSyncService: Error syncing progress: \(error)")
        }
    }

    /// Process a single progress record
    private func processChallengeProgressRecord(_ record: CKRecord, challenge: SharedChallenge, context: ModelContext) async {
        let challengeID = record[CloudKitConfig.Field.challengeID] as? String ?? ""
        let userID = record[CloudKitConfig.Field.userID] as? String ?? ""
        let date = record[CloudKitConfig.Field.date] as? Date ?? Date()
        let completedAt = record[CloudKitConfig.Field.completedAt] as? Date ?? Date()

        // Check if completion already exists locally
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
            let existing = try context.fetch(descriptor)
            if let localCompletion = existing.first {
                // Mark as synced now that CloudKit confirms the record exists
                localCompletion.isSynced = true
                if localCompletion.cloudRecordID == nil {
                    localCompletion.cloudRecordID = record.recordID.recordName
                }
            } else {
                let completion = ChallengeCompletion(
                    challengeID: challengeID,
                    userID: userID,
                    date: date,
                    completedAt: completedAt
                )
                completion.cloudRecordID = record.recordID.recordName
                completion.isSynced = true
                context.insert(completion)
            }
        } catch {
            print("🏆 ChallengeSyncService: Error processing progress record: \(error)")
        }
    }

    // MARK: - Challenge Actions

    /// Create a new challenge
    func createChallenge(
        participantUserID: String,
        habitName: String,
        habitEmoji: String,
        habitColor: String,
        targetDays: Int,
        context: ModelContext
    ) async throws -> SharedChallenge {
        guard let currentUserID = cloudKitService.currentUserID else {
            throw CloudKitError.notAuthenticated
        }

        let challenge = SharedChallenge(
            creatorUserID: currentUserID,
            participantUserID: participantUserID,
            habitName: habitName,
            habitEmoji: habitEmoji,
            habitColor: habitColor,
            targetDays: targetDays
        )

        // Save to CloudKit
        try await cloudKitService.saveChallenge(challenge)

        // Fetch participant profile info
        if let profile = try? await cloudKitService.fetchUserProfile(userID: participantUserID) {
            challenge.participantDisplayName = profile.displayName
            challenge.participantAvatarEmoji = profile.avatarEmoji
        }

        // Save locally
        context.insert(challenge)
        try context.save()

        print("🏆 ChallengeSyncService: Created challenge: \(habitName) with \(participantUserID)")
        return challenge
    }

    /// Accept a challenge invite
    func acceptChallenge(_ challenge: SharedChallenge, context: ModelContext) async throws {
        challenge.activate()
        try context.save()
        pendingInviteCount = max(0, pendingInviteCount - 1)

        // Best-effort CloudKit update (participant may not own the record)
        try? await cloudKitService.updateChallengeStatus(
            challengeID: challenge.challengeID,
            status: .active,
            startDate: challenge.startDate,
            endDate: challenge.endDate
        )

        print("🏆 ChallengeSyncService: Accepted challenge: \(challenge.habitName)")
    }

    /// Decline a challenge invite
    func declineChallenge(_ challenge: SharedChallenge, context: ModelContext) async throws {
        challenge.cancel()
        try context.save()
        pendingInviteCount = max(0, pendingInviteCount - 1)

        // Best-effort CloudKit update (participant may not own the record)
        try? await cloudKitService.updateChallengeStatus(
            challengeID: challenge.challengeID,
            status: .cancelled
        )

        print("🏆 ChallengeSyncService: Declined challenge: \(challenge.habitName)")
    }

    /// Remove a challenge — deletes locally and marks cancelled in CloudKit (best-effort)
    func removeChallenge(_ challenge: SharedChallenge, context: ModelContext) async {
        let challengeID = challenge.challengeID

        // Delete associated local completions
        let completionsPredicate = #Predicate<ChallengeCompletion> { $0.challengeID == challengeID }
        if let completions = try? context.fetch(FetchDescriptor(predicate: completionsPredicate)) {
            for completion in completions {
                context.delete(completion)
            }
        }

        context.delete(challenge)
        try? context.save()

        // Best-effort CloudKit cancel
        try? await cloudKitService.updateChallengeStatus(challengeID: challengeID, status: .cancelled)
    }

    /// Mark today as complete for a challenge
    func markTodayComplete(_ challenge: SharedChallenge, context: ModelContext) async throws {
        guard let currentUserID = cloudKitService.currentUserID else {
            throw CloudKitError.notAuthenticated
        }

        let today = Calendar.current.startOfDay(for: Date())

        // Check if already completed today
        if ChallengeCompletion.isCompleted(
            challengeID: challenge.challengeID,
            userID: currentUserID,
            date: today,
            in: context
        ) {
            print("🏆 ChallengeSyncService: Already completed today")
            return
        }

        // Save locally first (optimistic) — this is what the UI reads
        let completion = ChallengeCompletion(
            challengeID: challenge.challengeID,
            userID: currentUserID,
            date: today
        )
        completion.isSynced = false
        context.insert(completion)

        // Update cached count in the correct slot (creator vs participant)
        if challenge.isCreator(userID: currentUserID) {
            challenge.myCompletedDays += 1
        } else {
            challenge.friendCompletedDays += 1
        }

        try context.save()

        // Best-effort CloudKit sync
        do {
            try await cloudKitService.saveChallengeProgress(
                challengeID: challenge.challengeID,
                date: today
            )
            completion.isSynced = true
            try? context.save()

            // Pull fresh progress so the friend's count is up to date immediately
            await syncChallengeProgress(challenge, context: context)
            try? context.save()
        } catch {
            print("🏆 ChallengeSyncService: CloudKit save failed (will retry on next sync): \(error)")
        }

        print("🏆 ChallengeSyncService: Marked today complete for: \(challenge.habitName)")
    }

    /// Retry uploading any locally-stored completions that failed to sync to CloudKit
    func retrySyncUnsynced(context: ModelContext) async {
        guard cloudKitService.isAuthenticated else { return }

        let descriptor = FetchDescriptor<ChallengeCompletion>(
            predicate: #Predicate { !$0.isSynced }
        )
        guard let unsynced = try? context.fetch(descriptor), !unsynced.isEmpty else { return }

        print("🏆 ChallengeSyncService: Retrying \(unsynced.count) unsynced completions")

        for completion in unsynced {
            do {
                try await cloudKitService.saveChallengeProgress(
                    challengeID: completion.challengeID,
                    date: completion.date
                )
                completion.isSynced = true
                print("🏆 ChallengeSyncService: Retry succeeded for \(completion.challengeID)")
            } catch {
                print("🏆 ChallengeSyncService: Retry failed for \(completion.challengeID): \(error)")
            }
        }
        try? context.save()
    }

    /// Auto-complete active challenges where HealthKit shows activity today
    func syncHealthKitForChallenges(context: ModelContext) async {
        guard HealthKitManager.shared.isAuthorized else { return }

        let activeStatus = ChallengeStatus.active.rawValue
        let descriptor = FetchDescriptor<SharedChallenge>(
            predicate: #Predicate { $0.statusRaw == activeStatus }
        )
        guard let activeChallenges = try? context.fetch(descriptor) else { return }

        for challenge in activeChallenges {
            guard let hkTypeString = challenge.healthKitType,
                  let hkType = HealthKitDataType(rawValue: hkTypeString),
                  challenge.canMarkTodayComplete else { continue }

            let value = await HealthKitManager.shared.fetchValue(for: hkType, date: Date())

            // Always upload today's value so the friend can see partial progress
            try? await cloudKitService.saveHKSnapshot(challengeID: challenge.challengeID, value: value)

            // Auto-complete if target reached and not yet marked
            let target = challenge.healthKitTarget ?? hkType.defaultTarget
            if value >= target, !isCompletedToday(challenge, context: context) {
                try? await markTodayComplete(challenge, context: context)
                print("🏆 ChallengeSyncService: HealthKit auto-completed \(challenge.habitName) (\(hkType.displayName): \(value) >= \(target))")
            }
        }
    }

    /// Check if the current user has completed today for a challenge
    func isCompletedToday(_ challenge: SharedChallenge, context: ModelContext) -> Bool {
        guard let currentUserID = cloudKitService.currentUserID else { return false }

        return ChallengeCompletion.isCompleted(
            challengeID: challenge.challengeID,
            userID: currentUserID,
            date: Date(),
            in: context
        )
    }

    /// Get completions for a specific user
    func getCompletions(for challenge: SharedChallenge, userID: String, context: ModelContext) -> [Date] {
        let completions = ChallengeCompletion.completions(
            for: challenge.challengeID,
            userID: userID,
            in: context
        )
        return completions.map { Calendar.current.startOfDay(for: $0.date) }
    }

    /// Check and update challenge status if needed (e.g., mark completed when target days reached)
    func checkChallengeStatus(_ challenge: SharedChallenge, context: ModelContext) async {
        guard challenge.isActive else { return }

        // Check if challenge duration has ended
        if let endDate = challenge.endDate,
           Calendar.current.startOfDay(for: Date()) > Calendar.current.startOfDay(for: endDate) {
            challenge.markCompleted()

            try? await cloudKitService.updateChallengeStatus(
                challengeID: challenge.challengeID,
                status: .completed
            )

            try? context.save()
            print("🏆 ChallengeSyncService: Challenge completed: \(challenge.habitName)")
        }
    }
}
