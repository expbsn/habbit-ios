//
//  CloudKitService.swift
//  Stick
//
//  Core CloudKit operations for the friends feature.
//

import Foundation
import CloudKit
import SwiftData
import Combine
import UserNotifications

/// CloudKit container and record type identifiers
enum CloudKitConfig {
    static let containerIdentifier = "iCloud.com.kianjain.stick"

    enum RecordType {
        static let userProfile = "UserProfile"
        static let sharedProgress = "SharedProgress"
        static let friendConnection = "FriendConnection"
        static let motivationalMessage = "MotivationalMessage"
        static let sharedChallenge = "SharedChallenge"
        static let challengeProgress = "ChallengeProgress"
    }

    enum Field {
        // UserProfile fields
        static let username = "username"
        static let displayName = "displayName"
        static let avatarEmoji = "avatarEmoji"
        static let isDiscoverable = "isDiscoverable"
        static let motivationalQuote = "motivationalQuote"
        static let topHabitName = "topHabitName"
        static let hoursSpentThisWeek = "hoursSpentThisWeek"

        // SharedProgress fields
        static let date = "date"
        static let completionPercentage = "completionPercentage"
        static let currentStreak = "currentStreak"
        static let lastUpdated = "lastUpdated"

        // FriendConnection fields
        static let initiatorUserID = "initiatorUserID"
        static let receiverUserID = "receiverUserID"
        static let status = "status"
        static let requestDate = "requestDate"
        static let acceptedDate = "acceptedDate"

        // MotivationalMessage fields
        static let senderUserID = "senderUserID"
        static let senderDisplayName = "senderDisplayName"
        static let messageReceiverUserID = "receiverUserID"
        static let templateID = "templateID"
        static let customMessageText = "customMessageText"
        static let sentDate = "sentDate"
        static let isRead = "isRead"

        // SharedChallenge fields
        static let challengeID = "challengeID"
        static let creatorUserID = "creatorUserID"
        static let participantUserID = "participantUserID"
        static let habitName = "habitName"
        static let habitEmoji = "habitEmoji"
        static let habitColor = "habitColor"
        static let targetDays = "targetDays"
        static let startDate = "startDate"
        static let endDate = "endDate"
        static let createdDate = "createdDate"

        // ChallengeProgress fields
        static let userID = "userID"
        static let isCompleted = "isCompleted"
        static let completedAt = "completedAt"
        static let isCollaborative = "isCollaborative"
        static let hkValue = "hkValue"
    }
}

/// Errors that can occur in CloudKit operations
enum CloudKitError: Error, LocalizedError {
    case notAuthenticated
    case networkUnavailable
    case quotaExceeded
    case recordNotFound
    case permissionDenied
    case usernameTaken
    case serverError(Error)
    case unknown(Error)

    var errorDescription: String? {
        switch self {
        case .notAuthenticated:
            return String(localized: "cloudkit_error_not_authenticated")
        case .networkUnavailable:
            return String(localized: "cloudkit_error_network")
        case .quotaExceeded:
            return String(localized: "cloudkit_error_quota")
        case .recordNotFound:
            return String(localized: "cloudkit_error_not_found")
        case .permissionDenied:
            return String(localized: "cloudkit_error_permission")
        case .usernameTaken:
            return String(localized: "cloudkit_error_username_taken")
        case .serverError(let error):
            return String(localized: "cloudkit_error_server") + ": \(error.localizedDescription)"
        case .unknown(let error):
            return error.localizedDescription
        }
    }
}

/// Manages all CloudKit operations for the friends feature.
@MainActor
final class CloudKitService: ObservableObject {
    static let shared = CloudKitService()

    // MARK: - Published State

    @Published var accountStatus: CKAccountStatus = .couldNotDetermine
    @Published var isAuthenticated = false
    @Published var currentUserID: String?
    @Published var currentUserDisplayName: String = ""
    @Published var lastSyncDate: Date?
    @Published var isSyncing = false
    @Published var lastError: CloudKitError?

    // MARK: - Private Properties

    private let container: CKContainer
    private let publicDatabase: CKDatabase
    private let privateDatabase: CKDatabase
    private var subscriptions: [CKSubscription.ID: CKSubscription] = [:]
    private var cancellables = Set<AnyCancellable>()

    // Offline queue for operations when network is unavailable
    private var offlineQueue: [() async throws -> Void] = []

    private init() {
        container = CKContainer(identifier: CloudKitConfig.containerIdentifier)
        publicDatabase = container.publicCloudDatabase
        privateDatabase = container.privateCloudDatabase

        Task {
            await checkAccountStatus()
        }
    }

    // MARK: - Account Status

    /// Check current iCloud account status
    func checkAccountStatus() async {
        do {
            let status = try await container.accountStatus()
            accountStatus = status
            isAuthenticated = status == .available

            if isAuthenticated {
                try await fetchCurrentUserID()
                // Cache current user's display name for outgoing messages
                if let userID = currentUserID,
                   let profile = try? await fetchUserProfile(userID: userID) {
                    currentUserDisplayName = profile.displayName
                }
                // Set up push notification subscriptions once authenticated
                try? await setupSubscriptions()
            } else {
                currentUserID = nil
            }
        } catch {
            accountStatus = .couldNotDetermine
            isAuthenticated = false
            lastError = .unknown(error)
        }
    }

    /// Fetch the current user's CloudKit record ID
    private func fetchCurrentUserID() async throws {
        let recordID = try await container.userRecordID()
        currentUserID = recordID.recordName
    }

    // MARK: - User Profile Operations

    /// Check if a username is already taken
    func isUsernameTaken(_ username: String) async throws -> Bool {
        let normalizedUsername = username.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedUsername.isEmpty else { return false }

        let predicate = NSPredicate(format: "%K == %@", CloudKitConfig.Field.username, normalizedUsername)
        let query = CKQuery(recordType: CloudKitConfig.RecordType.userProfile, predicate: predicate)

        do {
            let (results, _) = try await publicDatabase.records(matching: query, resultsLimit: 1)
            let records = results.compactMap { try? $0.1.get() }

            // If we find a record, check if it's our own
            if let existingRecord = records.first {
                let existingRecordName = existingRecord.recordID.recordName
                let ourRecordName = "profile_\(currentUserID ?? "")"
                // Username is taken if it belongs to someone else
                return existingRecordName != ourRecordName
            }
            return false
        } catch let error as CKError {
            throw mapCKError(error)
        }
    }

    /// Save or update the user's profile in CloudKit public database
    func saveUserProfile(_ profile: MyCloudProfile) async throws {
        guard isAuthenticated, let userID = currentUserID else {
            throw CloudKitError.notAuthenticated
        }

        // Check username uniqueness
        let normalizedUsername = profile.username.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        if try await isUsernameTaken(normalizedUsername) {
            throw CloudKitError.usernameTaken
        }

        let recordID = CKRecord.ID(recordName: "profile_\(userID)")

        // Try to fetch existing record first, or create new one
        let record: CKRecord
        do {
            record = try await publicDatabase.record(for: recordID)
        } catch let error as CKError where error.code == .unknownItem {
            // Record doesn't exist, create new one
            record = CKRecord(recordType: CloudKitConfig.RecordType.userProfile, recordID: recordID)
        } catch let error as CKError {
            throw mapCKError(error)
        }

        record[CloudKitConfig.Field.username] = normalizedUsername
        record[CloudKitConfig.Field.displayName] = profile.displayName
        record[CloudKitConfig.Field.avatarEmoji] = profile.avatarEmoji
        record[CloudKitConfig.Field.isDiscoverable] = profile.isDiscoverable ? 1 : 0
        record[CloudKitConfig.Field.motivationalQuote] = profile.motivationalQuote

        do {
            _ = try await publicDatabase.save(record)
            profile.cloudRecordID = recordID.recordName
            profile.isSynced = true
            profile.lastSyncedDate = Date()
            currentUserDisplayName = profile.displayName
        } catch let error as CKError {
            throw mapCKError(error)
        }
    }

    /// Fetch a user's profile by their user ID
    func fetchUserProfile(userID: String) async throws -> (displayName: String, avatarEmoji: String)? {
        let recordID = CKRecord.ID(recordName: "profile_\(userID)")
        print("👤 CloudKit: Fetching profile with recordName: profile_\(userID)")

        do {
            let record = try await publicDatabase.record(for: recordID)
            let displayName = record[CloudKitConfig.Field.displayName] as? String ?? ""
            let avatarEmoji = record[CloudKitConfig.Field.avatarEmoji] as? String ?? "😊"
            print("👤 CloudKit: Found profile - name: \(displayName), emoji: \(avatarEmoji)")
            return (displayName, avatarEmoji)
        } catch let error as CKError where error.code == .unknownItem {
            print("👤 CloudKit: Profile not found for \(userID)")
            return nil
        } catch let error as CKError {
            print("👤 CloudKit: Error fetching profile: \(error.localizedDescription)")
            throw mapCKError(error)
        }
    }

    // MARK: - Progress Sharing

    /// Save today's progress to CloudKit public database (visible to friends)
    func saveProgress(completionPercentage: Double, currentStreak: Int) async throws {
        guard isAuthenticated, let userID = currentUserID else {
            print("☁️ CloudKit: saveProgress - not authenticated")
            throw CloudKitError.notAuthenticated
        }

        let today = Calendar.current.startOfDay(for: Date())
        // Use a stable record ID so we update the same record throughout the day
        let recordID = CKRecord.ID(recordName: "progress_\(userID)_\(Int(today.timeIntervalSince1970))")
        print("☁️ CloudKit: Saving progress with recordID: \(recordID.recordName)")

        // Try to fetch existing record first, or create new one
        let record: CKRecord
        do {
            record = try await publicDatabase.record(for: recordID)
        } catch let error as CKError where error.code == .unknownItem {
            record = CKRecord(recordType: CloudKitConfig.RecordType.sharedProgress, recordID: recordID)
        } catch let error as CKError {
            throw mapCKError(error)
        }

        record[CloudKitConfig.Field.date] = today
        record[CloudKitConfig.Field.completionPercentage] = completionPercentage
        record[CloudKitConfig.Field.currentStreak] = currentStreak
        record[CloudKitConfig.Field.lastUpdated] = Date()
        // Store the user ID so friends can query for it
        record["userID"] = userID

        do {
            _ = try await publicDatabase.save(record)
            lastSyncDate = Date()
        } catch let error as CKError {
            // Queue for later if network unavailable
            if error.code == .networkUnavailable || error.code == .networkFailure {
                queueOfflineOperation { [weak self] in
                    try await self?.saveProgress(completionPercentage: completionPercentage, currentStreak: currentStreak)
                }
            }
            throw mapCKError(error)
        }
    }

    /// Fetch a friend's progress for today
    func fetchFriendProgress(friendUserID: String) async throws -> (completionPercentage: Double, currentStreak: Int)? {
        let today = Calendar.current.startOfDay(for: Date())
        let recordID = CKRecord.ID(recordName: "progress_\(friendUserID)_\(Int(today.timeIntervalSince1970))")

        do {
            let record = try await publicDatabase.record(for: recordID)
            let completion = record[CloudKitConfig.Field.completionPercentage] as? Double ?? 0.0
            let streak = record[CloudKitConfig.Field.currentStreak] as? Int ?? 0
            return (completion, streak)
        } catch let error as CKError where error.code == .unknownItem {
            // No progress record for today yet
            return nil
        } catch let error as CKError {
            throw mapCKError(error)
        }
    }

    /// Fetch progress for multiple friends
    func fetchAllFriendsProgress(friendUserIDs: [String]) async -> [String: (completionPercentage: Double, currentStreak: Int)] {
        var results: [String: (Double, Int)] = [:]

        // Fetch in parallel
        await withTaskGroup(of: (String, Double, Int)?.self) { group in
            for friendID in friendUserIDs {
                group.addTask {
                    if let progress = try? await self.fetchFriendProgress(friendUserID: friendID) {
                        return (friendID, progress.completionPercentage, progress.currentStreak)
                    }
                    return nil
                }
            }

            for await result in group {
                if let (friendID, completion, streak) = result {
                    results[friendID] = (completion, streak)
                }
            }
        }

        return results
    }

    /// Fetch a friend's progress for a specific date
    func fetchFriendProgress(friendUserID: String, for date: Date) async -> Double? {
        let dayStart = Calendar.current.startOfDay(for: date)
        let recordID = CKRecord.ID(recordName: "progress_\(friendUserID)_\(Int(dayStart.timeIntervalSince1970))")

        print("☁️ CloudKit: Fetching progress recordID: \(recordID.recordName)")

        do {
            let record = try await publicDatabase.record(for: recordID)
            let progress = record[CloudKitConfig.Field.completionPercentage] as? Double
            print("☁️ CloudKit: Found progress: \(progress ?? -1) for \(friendUserID)")
            return progress
        } catch let error as CKError {
            print("☁️ CloudKit: No progress found for \(recordID.recordName) - \(error.code.rawValue)")
            return nil
        } catch {
            print("☁️ CloudKit: Error fetching progress: \(error)")
            return nil
        }
    }

    /// Fetch a friend's progress for the past 7 days
    func fetchFriendWeekProgress(friendUserID: String) async -> [Date: Double] {
        let calendar = Calendar.current
        var results: [Date: Double] = [:]

        // Fetch all 7 days in parallel
        await withTaskGroup(of: (Date, Double)?.self) { group in
            for dayOffset in 0..<7 {
                guard let date = calendar.date(byAdding: .day, value: -dayOffset, to: Date()) else { continue }
                let dayStart = calendar.startOfDay(for: date)

                group.addTask {
                    if let progress = await self.fetchFriendProgress(friendUserID: friendUserID, for: dayStart) {
                        return (dayStart, progress)
                    }
                    return nil
                }
            }

            for await result in group {
                if let (date, progress) = result {
                    results[date] = progress
                }
            }
        }

        return results
    }

    // MARK: - Debug / Testing

    /// Create test progress data for a fake friend (for testing)
    func debugCreateTestFriendProgress(testFriendUserID: String) async {
        print("🧪 Creating test progress for friend: \(testFriendUserID)")

        let calendar = Calendar.current

        // Create progress for the past 7 days
        for dayOffset in 0..<7 {
            guard let date = calendar.date(byAdding: .day, value: -dayOffset, to: Date()) else { continue }
            let dayStart = calendar.startOfDay(for: date)

            let recordID = CKRecord.ID(recordName: "progress_\(testFriendUserID)_\(Int(dayStart.timeIntervalSince1970))")
            let record = CKRecord(recordType: CloudKitConfig.RecordType.sharedProgress, recordID: recordID)

            // Random progress between 50-100%
            let progress = Double.random(in: 0.5...1.0)
            let streak = 7 - dayOffset

            record[CloudKitConfig.Field.date] = dayStart
            record[CloudKitConfig.Field.completionPercentage] = progress
            record[CloudKitConfig.Field.currentStreak] = streak
            record[CloudKitConfig.Field.lastUpdated] = Date()
            record["userID"] = testFriendUserID

            do {
                _ = try await publicDatabase.save(record)
                print("🧪 ✅ Created progress for \(dayStart.formatted(.dateTime.month().day())): \(Int(progress * 100))%")
            } catch {
                print("🧪 ❌ Failed to create progress for day -\(dayOffset): \(error)")
            }
        }

        print("🧪 Done creating test progress data!")
    }

    /// Debug function to test progress sync - call this to verify everything works
    func debugTestProgressSync() async {
        print("🧪 === DEBUG: Testing Progress Sync ===")
        print("🧪 Current userID: \(currentUserID ?? "nil")")
        print("🧪 Is authenticated: \(isAuthenticated)")

        guard let userID = currentUserID else {
            print("🧪 ❌ Not authenticated - cannot test")
            return
        }

        // Test 1: Save progress
        print("🧪 Step 1: Saving test progress (75%)...")
        do {
            try await saveProgress(completionPercentage: 0.75, currentStreak: 5)
            print("🧪 ✅ Progress saved successfully")
        } catch {
            print("🧪 ❌ Failed to save progress: \(error)")
            return
        }

        // Test 2: Fetch our own progress back
        print("🧪 Step 2: Fetching our own progress back...")
        if let progress = try? await fetchFriendProgress(friendUserID: userID) {
            print("🧪 ✅ Fetched progress: \(Int(progress.completionPercentage * 100))%, streak: \(progress.currentStreak)")
        } else {
            print("🧪 ❌ Could not fetch our own progress - check security roles!")
        }

        // Test 3: List all SharedProgress records we can see
        print("🧪 Step 3: Querying all SharedProgress records...")
        let predicate = NSPredicate(value: true)
        let query = CKQuery(recordType: CloudKitConfig.RecordType.sharedProgress, predicate: predicate)

        do {
            let (results, _) = try await publicDatabase.records(matching: query, resultsLimit: 10)
            print("🧪 Found \(results.count) SharedProgress records:")
            for (recordID, result) in results {
                if let record = try? result.get() {
                    let recordUserID = record["userID"] as? String ?? "unknown"
                    let completion = record[CloudKitConfig.Field.completionPercentage] as? Double ?? 0
                    print("🧪   - \(recordID.recordName): userID=\(recordUserID), completion=\(Int(completion * 100))%")
                }
            }
        } catch {
            print("🧪 ❌ Query failed: \(error)")
        }

        print("🧪 === DEBUG: Test Complete ===")
    }

    /// Debug function to check if a specific friend has ANY progress records
    func debugCheckFriendRecords(friendUserID: String) async {
        print("🔍 === Checking records for user: \(friendUserID) ===")

        // Method 1: Query by userID field
        let predicate = NSPredicate(format: "userID == %@", friendUserID)
        let query = CKQuery(recordType: CloudKitConfig.RecordType.sharedProgress, predicate: predicate)

        do {
            let (results, _) = try await publicDatabase.records(matching: query, resultsLimit: 10)
            print("🔍 Query by userID found \(results.count) records:")
            for (recordID, result) in results {
                if let record = try? result.get() {
                    let date = record[CloudKitConfig.Field.date] as? Date
                    let completion = record[CloudKitConfig.Field.completionPercentage] as? Double ?? 0
                    print("🔍   - \(recordID.recordName)")
                    print("🔍     date: \(date?.formatted() ?? "nil"), completion: \(Int(completion * 100))%")
                }
            }
            if results.isEmpty {
                print("🔍 ⚠️ No records found with userID=\(friendUserID)")
                print("🔍 This means the friend hasn't uploaded their progress yet.")
                print("🔍 They need to be running the updated app version.")
            }
        } catch {
            print("🔍 ❌ Query failed: \(error)")
            print("🔍 This might be a CloudKit security role issue.")
        }

        // Method 2: Try direct fetch for today
        let today = Calendar.current.startOfDay(for: Date())
        let recordName = "progress_\(friendUserID)_\(Int(today.timeIntervalSince1970))"
        print("🔍 Trying direct fetch: \(recordName)")

        let recordID = CKRecord.ID(recordName: recordName)
        do {
            let record = try await publicDatabase.record(for: recordID)
            let completion = record[CloudKitConfig.Field.completionPercentage] as? Double ?? 0
            print("🔍 ✅ Found record directly: \(Int(completion * 100))%")
        } catch let error as CKError {
            print("🔍 ❌ Direct fetch failed: error code \(error.code.rawValue)")
            if error.code == .unknownItem {
                print("🔍    Record doesn't exist - friend hasn't uploaded today's progress")
            }
        } catch {
            print("🔍 ❌ Direct fetch error: \(error)")
        }

        print("🔍 === Check complete ===")
    }

    /// Debug: Create a simple universal subscription (no predicate filter)
    func debugCreateUniversalSubscription() async {
        print("🧪 === Creating UNIVERSAL subscription (fires on ALL messages) ===")

        // Delete any existing test subscription
        do {
            try await publicDatabase.deleteSubscription(withID: "test-all-messages")
            print("🧪 Deleted old test subscription")
        } catch {
            print("🧪 No existing test subscription")
        }

        // Create subscription that fires on ANY MotivationalMessage creation
        let subscription = CKQuerySubscription(
            recordType: CloudKitConfig.RecordType.motivationalMessage,
            predicate: NSPredicate(value: true),  // Matches ALL records
            subscriptionID: "test-all-messages",
            options: [.firesOnRecordCreation]
        )

        let notificationInfo = CKSubscription.NotificationInfo()
        notificationInfo.alertBody = "Test: New message created!"
        notificationInfo.title = "Push Test"
        notificationInfo.soundName = "default"
        notificationInfo.shouldBadge = true
        subscription.notificationInfo = notificationInfo

        do {
            _ = try await publicDatabase.save(subscription)
            print("🧪 ✅ Universal subscription created!")
            print("🧪 This should fire on ANY MotivationalMessage creation")
        } catch {
            print("🧪 ❌ Failed: \(error)")
        }
    }

    /// Debug function to recreate subscriptions with static alert text (for testing)
    func debugRecreateSubscriptionsWithStaticAlert() async {
        print("🧪 === Recreating subscriptions with static alert text ===")

        guard let userID = currentUserID else {
            print("🧪 ❌ Not authenticated")
            return
        }

        // Delete existing subscriptions first
        do {
            try await publicDatabase.deleteSubscription(withID: "messages-\(userID)")
            print("🧪 Deleted old messages subscription")
        } catch {
            print("🧪 No existing messages subscription to delete")
        }

        do {
            try await publicDatabase.deleteSubscription(withID: "friend-requests-\(userID)")
            print("🧪 Deleted old friend-requests subscription")
        } catch {
            print("🧪 No existing friend-requests subscription to delete")
        }

        // Create new subscriptions with static alertBody (not localization keys)
        let messagesSubscription = CKQuerySubscription(
            recordType: CloudKitConfig.RecordType.motivationalMessage,
            predicate: NSPredicate(format: "receiverUserID == %@", userID),
            subscriptionID: "messages-\(userID)",
            options: [.firesOnRecordCreation]
        )

        let messagesNotificationInfo = CKSubscription.NotificationInfo()
        messagesNotificationInfo.title = "New Message"  // Static text
        messagesNotificationInfo.alertBody = "You received a message from a friend!"  // Static text
        messagesNotificationInfo.shouldBadge = true
        messagesNotificationInfo.soundName = "default"
        messagesNotificationInfo.category = "FRIEND_MESSAGE"
        // NOT setting shouldSendContentAvailable to avoid silent push behavior
        messagesSubscription.notificationInfo = messagesNotificationInfo

        let friendRequestsSubscription = CKQuerySubscription(
            recordType: CloudKitConfig.RecordType.friendConnection,
            predicate: NSPredicate(format: "receiverUserID == %@", userID),
            subscriptionID: "friend-requests-\(userID)",
            options: [.firesOnRecordCreation]
        )

        let friendsNotificationInfo = CKSubscription.NotificationInfo()
        friendsNotificationInfo.title = "New Friend Request"  // Static text
        friendsNotificationInfo.alertBody = "Someone wants to connect with you!"  // Static text
        friendsNotificationInfo.shouldBadge = true
        friendsNotificationInfo.soundName = "default"
        friendsNotificationInfo.category = "FRIEND_REQUEST"
        friendRequestsSubscription.notificationInfo = friendsNotificationInfo

        do {
            _ = try await publicDatabase.save(messagesSubscription)
            print("🧪 ✅ Created messages subscription with static alert")
            _ = try await publicDatabase.save(friendRequestsSubscription)
            print("🧪 ✅ Created friend-requests subscription with static alert")
            print("🧪 === Done! Now try 'Send Test Push to Self' ===")
        } catch {
            print("🧪 ❌ Failed to create subscriptions: \(error)")
        }
    }

    /// Debug function to send a test push notification to yourself
    func debugSendTestNotification() async {
        print("🧪 === Sending test notification to self ===")

        guard let userID = currentUserID else {
            print("🧪 ❌ Not authenticated")
            return
        }

        // Create a message record where we are the receiver
        // This should trigger the "messages" subscription
        let recordID = CKRecord.ID(recordName: "test_message_\(UUID().uuidString)")
        let record = CKRecord(recordType: CloudKitConfig.RecordType.motivationalMessage, recordID: recordID)

        record[CloudKitConfig.Field.senderUserID] = "test_sender"
        record[CloudKitConfig.Field.receiverUserID] = userID  // Send to ourselves
        record[CloudKitConfig.Field.templateID] = "encouragement"
        record[CloudKitConfig.Field.sentDate] = Date()
        record[CloudKitConfig.Field.isRead] = 0

        do {
            let savedRecord = try await publicDatabase.save(record)
            print("🧪 ✅ Test message SAVED to CloudKit!")
            print("🧪 Record ID: \(savedRecord.recordID.recordName)")
            print("🧪 Receiver (you): \(userID)")

            // Immediately verify by fetching it back
            let fetched = try await publicDatabase.record(for: recordID)
            let fetchedReceiver = fetched["receiverUserID"] as? String ?? "nil"
            print("🧪 ✅ Verified - fetched back receiverUserID: \(fetchedReceiver)")
        } catch {
            print("🧪 ❌ Failed to create test message: \(error)")
        }
    }

    /// Debug function to list all messages in CloudKit for current user
    func debugListAllMessages() async {
        print("📨 === Listing all messages for current user ===")

        guard let userID = currentUserID else {
            print("📨 ❌ Not authenticated")
            return
        }

        // Query messages where we are the receiver
        let predicate = NSPredicate(format: "receiverUserID == %@", userID)
        let query = CKQuery(recordType: CloudKitConfig.RecordType.motivationalMessage, predicate: predicate)

        do {
            let (results, _) = try await publicDatabase.records(matching: query, resultsLimit: 20)
            print("📨 Found \(results.count) messages for you:")
            for (recordID, result) in results {
                if let record = try? result.get() {
                    let sender = record["senderUserID"] as? String ?? "?"
                    let template = record["templateID"] as? String ?? "?"
                    let date = record["sentDate"] as? Date
                    print("📨   - \(recordID.recordName)")
                    print("📨     from: \(sender), template: \(template), date: \(date?.formatted() ?? "?")")
                }
            }
            if results.isEmpty {
                print("📨 No messages found - records may not be saving correctly")
            }
        } catch {
            print("📨 ❌ Query error: \(error)")
        }
    }

    /// Returns a human-readable push notification diagnostic string for display in the UI
    func debugPushDiagnosticString() async -> String {
        var lines: [String] = []

        // 1. Auth
        lines.append("CloudKit: \(isAuthenticated ? "✅ authenticated" : "❌ NOT authenticated")")
        if let uid = currentUserID { lines.append("User: …\(uid.suffix(8))") }

        // 2. Permission
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        switch settings.authorizationStatus {
        case .authorized:  lines.append("Permission: ✅ authorized")
        case .denied:      lines.append("Permission: ❌ DENIED — enable in iOS Settings")
        case .provisional: lines.append("Permission: ⚠️ provisional (quiet)")
        default:           lines.append("Permission: ⚠️ not determined")
        }

        // 3. Subscriptions
        do {
            let subs = try await publicDatabase.allSubscriptions()
            lines.append("Subscriptions: \(subs.count) registered")
            for sub in subs {
                let hasAlert = (sub as? CKQuerySubscription)?.notificationInfo?.alertBody != nil ||
                               (sub as? CKQuerySubscription)?.notificationInfo?.alertLocalizationKey != nil
                let silent   = (sub as? CKQuerySubscription)?.notificationInfo?.shouldSendContentAvailable ?? false
                let icon = silent ? "🔇" : (hasAlert ? "🔔" : "⚠️ no alert")
                lines.append("  \(icon) \(sub.subscriptionID)")
            }
            if subs.isEmpty { lines.append("  ❌ No subscriptions — tap Nuke & Recreate") }
        } catch {
            lines.append("Subscriptions: ❌ fetch failed — \(error.localizedDescription)")
        }

        // 4. entitlement hint
        lines.append("aps-environment: development (switch to production for TestFlight)")

        return lines.joined(separator: "\n")
    }

    /// Deletes all CloudKit public-database records owned by the current user.
    /// Returns the number of records deleted.
    func debugClearMyCloudKitData() async -> Int {
        guard let userID = currentUserID else { return 0 }
        var deleted = 0

        // Record types and the field that identifies ownership
        let targets: [(recordType: String, field: String)] = [
            (CloudKitConfig.RecordType.motivationalMessage,  CloudKitConfig.Field.senderUserID),
            (CloudKitConfig.RecordType.friendConnection,     CloudKitConfig.Field.initiatorUserID),
            (CloudKitConfig.RecordType.sharedChallenge,      CloudKitConfig.Field.creatorUserID),
            (CloudKitConfig.RecordType.challengeProgress,    CloudKitConfig.Field.userID),
            (CloudKitConfig.RecordType.sharedProgress,       "userID"),
        ]

        for target in targets {
            let predicate = NSPredicate(format: "%K == %@", target.field, userID)
            let query = CKQuery(recordType: target.recordType, predicate: predicate)
            guard let results = try? await publicDatabase.records(matching: query, resultsLimit: 200) else { continue }
            for (_, result) in results.0 {
                guard let record = try? result.get() else { continue }
                try? await publicDatabase.deleteRecord(withID: record.recordID)
                deleted += 1
            }
        }

        // Also delete subscriptions
        if let subs = try? await publicDatabase.allSubscriptions() {
            for sub in subs { try? await publicDatabase.deleteSubscription(withID: sub.subscriptionID) }
            deleted += subs.count
        }

        print("🧹 debugClearMyCloudKitData: deleted \(deleted) records/subscriptions")
        return deleted
    }

    /// Full diagnostic check for push notifications
    func debugFullPushDiagnostic() async {
        print("🔍 === FULL PUSH NOTIFICATION DIAGNOSTIC ===")
        print("")

        // 1. Check authentication
        print("1️⃣ CloudKit Authentication:")
        print("   - isAuthenticated: \(isAuthenticated)")
        print("   - currentUserID: \(currentUserID ?? "nil")")
        print("")

        // 2. Check subscriptions
        print("2️⃣ Subscriptions:")
        do {
            let subs = try await publicDatabase.allSubscriptions()
            print("   - Count: \(subs.count)")
            for sub in subs {
                if let querySub = sub as? CKQuerySubscription {
                    print("   - \(sub.subscriptionID): \(querySub.recordType ?? "?")")
                    print("     Predicate: \(querySub.predicate)")
                }
            }
        } catch {
            print("   - ❌ Error fetching subscriptions: \(error)")
        }
        print("")

        // 3. Check if there are any MotivationalMessage records
        print("3️⃣ Recent MotivationalMessage records:")
        let query = CKQuery(
            recordType: CloudKitConfig.RecordType.motivationalMessage,
            predicate: NSPredicate(value: true)
        )
        do {
            let (results, _) = try await publicDatabase.records(matching: query, resultsLimit: 5)
            print("   - Found \(results.count) records")
            for (recordID, result) in results {
                if let record = try? result.get() {
                    let receiver = record["receiverUserID"] as? String ?? "nil"
                    print("   - \(recordID.recordName): receiverUserID=\(receiver)")
                }
            }
        } catch {
            print("   - ❌ Error querying records: \(error)")
        }
        print("")

        // 4. Container info
        print("4️⃣ Container Info:")
        print("   - Container ID: \(CloudKitConfig.containerIdentifier)")
        print("")

        print("5️⃣ Troubleshooting Tips:")
        print("   - Ensure Push Notifications capability is added in Xcode")
        print("   - Check Apple Developer Portal for APNS key/certificate")
        print("   - For TestFlight: aps-environment must be 'production'")
        print("   - CloudKit Dashboard: Check if receiverUserID field is indexed")
        print("   - Try on a real device (not simulator)")
        print("")
        print("🔍 === DIAGNOSTIC COMPLETE ===")
    }

    /// Debug function to list all active CloudKit subscriptions (full payload details)
    func debugListSubscriptions() async {
        print("🔔 === Listing all CloudKit subscriptions ===")

        do {
            let subscriptions = try await publicDatabase.allSubscriptions()
            print("🔔 Found \(subscriptions.count) subscription(s):")
            for sub in subscriptions {
                print("🔔   - ID: \(sub.subscriptionID)")
                if let querySub = sub as? CKQuerySubscription {
                    print("🔔     Record type: \(querySub.recordType ?? "nil")")
                    if let info = querySub.notificationInfo {
                        print("🔔     alertBody (static): \(info.alertBody ?? "nil")")
                        print("🔔     alertLocalizationKey: \(info.alertLocalizationKey ?? "nil")")
                        print("🔔     titleLocalizationKey: \(info.titleLocalizationKey ?? "nil")")
                        print("🔔     shouldSendContentAvailable: \(info.shouldSendContentAvailable)")
                        print("🔔     sound: \(info.soundName ?? "nil")")
                        print("🔔     category: \(info.category ?? "nil")")
                    } else {
                        print("🔔     ⚠️ No notificationInfo — subscription will fire silently with no payload")
                    }
                }
            }
            if subscriptions.isEmpty {
                print("🔔 ⚠️ No subscriptions found! Push notifications won't work.")
            }
        } catch {
            print("🔔 ❌ Failed to fetch subscriptions: \(error)")
        }

        print("🔔 === Done ===")
    }

    /// Debug: delete every subscription then call setupSubscriptions() fresh.
    /// Use this to fix stale or mis-configured subscriptions.
    func debugNukeAndRecreateSubscriptions() async {
        print("🧹 === Nuking all subscriptions ===")
        do {
            let existing = try await publicDatabase.allSubscriptions()
            for sub in existing {
                try? await publicDatabase.deleteSubscription(withID: sub.subscriptionID)
                print("🧹 Deleted: \(sub.subscriptionID)")
            }
            print("🧹 Deleted \(existing.count) subscription(s)")
        } catch {
            print("🧹 ❌ Error listing subscriptions: \(error)")
        }

        print("🧹 Recreating subscriptions…")
        do {
            try await setupSubscriptions()
            print("🧹 ✅ Subscriptions recreated successfully")
        } catch {
            print("🧹 ❌ Error recreating subscriptions: \(error)")
        }
        print("🧹 === Done ===")
    }

    /// Debug: simulate the background notification handler as if a push arrived.
    /// Lets you verify the sync code path works without sending an actual push.
    /// Write a seed record for every CloudKit record type so that all fields
    /// are registered in the Development schema. Records are deleted immediately after.
    /// Run this once after adding new fields to ensure the schema is up to date.
    func debugSeedCloudKitSchema() async -> String {
        guard isAuthenticated, let userID = currentUserID else {
            return "❌ Not authenticated"
        }

        var seededTypes: [String] = []
        var errors: [String] = []
        let db = publicDatabase
        let now = Date()
        let seedSuffix = "schema_seed_\(userID)"

        // Collect all seed records to save then delete
        var recordsToDelete: [CKRecord.ID] = []

        func seed(_ record: CKRecord) async {
            do {
                let saved = try await db.save(record)
                recordsToDelete.append(saved.recordID)
                seededTypes.append(record.recordType)
            } catch {
                errors.append("\(record.recordType): \(error.localizedDescription)")
            }
        }

        // UserProfile — all fields
        let profileRecord = CKRecord(recordType: CloudKitConfig.RecordType.userProfile,
                                     recordID: CKRecord.ID(recordName: "profile_\(seedSuffix)"))
        profileRecord[CloudKitConfig.Field.username] = "_schema_seed"
        profileRecord[CloudKitConfig.Field.displayName] = "Schema Seed"
        profileRecord[CloudKitConfig.Field.avatarEmoji] = "🔧"
        profileRecord[CloudKitConfig.Field.isDiscoverable] = 0
        profileRecord[CloudKitConfig.Field.motivationalQuote] = ""
        profileRecord[CloudKitConfig.Field.topHabitName] = ""
        profileRecord[CloudKitConfig.Field.hoursSpentThisWeek] = 0.0
        await seed(profileRecord)

        // SharedProgress — all fields
        let progressRecord = CKRecord(recordType: CloudKitConfig.RecordType.sharedProgress,
                                      recordID: CKRecord.ID(recordName: "progress_\(seedSuffix)"))
        progressRecord[CloudKitConfig.Field.date] = now
        progressRecord[CloudKitConfig.Field.completionPercentage] = 0.0
        progressRecord[CloudKitConfig.Field.currentStreak] = 0
        progressRecord[CloudKitConfig.Field.lastUpdated] = now
        await seed(progressRecord)

        // FriendConnection — all fields
        let connRecord = CKRecord(recordType: CloudKitConfig.RecordType.friendConnection,
                                  recordID: CKRecord.ID(recordName: "conn_\(seedSuffix)"))
        connRecord[CloudKitConfig.Field.initiatorUserID] = userID
        connRecord[CloudKitConfig.Field.receiverUserID] = userID
        connRecord[CloudKitConfig.Field.status] = "pending"
        connRecord[CloudKitConfig.Field.requestDate] = now
        connRecord[CloudKitConfig.Field.acceptedDate] = now
        await seed(connRecord)

        // MotivationalMessage — all fields including senderDisplayName
        let msgRecord = CKRecord(recordType: CloudKitConfig.RecordType.motivationalMessage,
                                 recordID: CKRecord.ID(recordName: "msg_\(seedSuffix)"))
        msgRecord[CloudKitConfig.Field.senderUserID] = userID
        msgRecord[CloudKitConfig.Field.senderDisplayName] = "Schema Seed"
        msgRecord[CloudKitConfig.Field.messageReceiverUserID] = userID
        msgRecord[CloudKitConfig.Field.templateID] = "seed"
        msgRecord[CloudKitConfig.Field.customMessageText] = ""
        msgRecord[CloudKitConfig.Field.sentDate] = now
        msgRecord[CloudKitConfig.Field.isRead] = 0
        await seed(msgRecord)

        // SharedChallenge — all fields
        let challengeRecord = CKRecord(recordType: CloudKitConfig.RecordType.sharedChallenge,
                                       recordID: CKRecord.ID(recordName: "challenge_\(seedSuffix)"))
        challengeRecord[CloudKitConfig.Field.challengeID] = "seed"
        challengeRecord[CloudKitConfig.Field.creatorUserID] = userID
        challengeRecord[CloudKitConfig.Field.participantUserID] = userID
        challengeRecord[CloudKitConfig.Field.habitName] = "Schema Seed"
        challengeRecord[CloudKitConfig.Field.habitEmoji] = "🔧"
        challengeRecord[CloudKitConfig.Field.habitColor] = "#000000"
        challengeRecord[CloudKitConfig.Field.targetDays] = 1
        challengeRecord[CloudKitConfig.Field.startDate] = now
        challengeRecord[CloudKitConfig.Field.endDate] = now
        challengeRecord[CloudKitConfig.Field.createdDate] = now
        challengeRecord[CloudKitConfig.Field.isCollaborative] = 0
        await seed(challengeRecord)

        // ChallengeProgress — all fields
        let cpRecord = CKRecord(recordType: CloudKitConfig.RecordType.challengeProgress,
                                recordID: CKRecord.ID(recordName: "cprogress_\(seedSuffix)"))
        cpRecord[CloudKitConfig.Field.challengeID] = "seed"
        cpRecord[CloudKitConfig.Field.userID] = userID
        cpRecord[CloudKitConfig.Field.date] = now
        cpRecord[CloudKitConfig.Field.isCompleted] = 0
        cpRecord[CloudKitConfig.Field.completedAt] = now
        cpRecord[CloudKitConfig.Field.isCollaborative] = 0
        cpRecord[CloudKitConfig.Field.hkValue] = 0.0
        await seed(cpRecord)

        // Delete all seed records
        for recordID in recordsToDelete {
            try? await db.deleteRecord(withID: recordID)
        }

        if errors.isEmpty {
            return "✅ Schema seeded & cleaned up for: \(seededTypes.joined(separator: ", "))"
        } else {
            let ok = seededTypes.isEmpty ? "" : "✅ OK: \(seededTypes.joined(separator: ", "))\n"
            return "\(ok)❌ Errors:\n\(errors.joined(separator: "\n"))"
        }
    }

    func debugSimulateBackgroundPush(type subscriptionPrefix: String) async {
        guard let container = StickApp.sharedContainer else {
            print("🔵 ❌ No model container — launch the app fully before testing")
            return
        }
        let context = container.mainContext
        print("🔵 Simulating background push for prefix: \(subscriptionPrefix)")

        if subscriptionPrefix.hasPrefix("challenge-progress") {
            print("🔵 → Running ChallengeSyncService.syncChallenges")
            await ChallengeSyncService.shared.syncChallenges(context: context)
        } else {
            print("🔵 → Running FriendSyncService.performInitialSync")
            await FriendSyncService.shared.performInitialSync(context: context)
        }
        print("🔵 ✅ Simulation complete — check Friends/Challenges tabs")
    }

    // MARK: - Friend Connections

    /// Send a friend request to another user
    func sendFriendRequest(toUserID receiverID: String) async throws {
        guard isAuthenticated, let userID = currentUserID else {
            print("❌ CloudKit: Cannot send friend request - not authenticated or no userID")
            throw CloudKitError.notAuthenticated
        }

        print("📤 CloudKit: Creating friend connection from \(userID) to \(receiverID)")

        let recordID = CKRecord.ID(recordName: "connection_\(userID)_\(receiverID)")
        let record = CKRecord(recordType: CloudKitConfig.RecordType.friendConnection, recordID: recordID)

        record[CloudKitConfig.Field.initiatorUserID] = userID
        record[CloudKitConfig.Field.receiverUserID] = receiverID
        record[CloudKitConfig.Field.status] = FriendConnectionStatus.pending.rawValue
        record[CloudKitConfig.Field.requestDate] = Date()

        do {
            let savedRecord = try await publicDatabase.save(record)
            print("✅ CloudKit: Friend connection saved successfully: \(savedRecord.recordID.recordName)")
        } catch let error as CKError {
            print("❌ CloudKit: Failed to save friend connection: \(error.localizedDescription)")
            print("❌ CloudKit: Error code: \(error.code.rawValue)")
            if let partialErrors = error.userInfo[CKPartialErrorsByItemIDKey] as? [CKRecord.ID: Error] {
                for (id, partialError) in partialErrors {
                    print("❌ CloudKit: Partial error for \(id.recordName): \(partialError)")
                }
            }
            throw mapCKError(error)
        }
    }

    /// Accept a friend request
    func acceptFriendRequest(connectionRecordID: String) async throws {
        let recordID = CKRecord.ID(recordName: connectionRecordID)

        do {
            let record = try await publicDatabase.record(for: recordID)
            record[CloudKitConfig.Field.status] = FriendConnectionStatus.accepted.rawValue
            record[CloudKitConfig.Field.acceptedDate] = Date()
            _ = try await publicDatabase.save(record)
        } catch let error as CKError {
            throw mapCKError(error)
        }
    }

    /// Delete a friend connection record (remove friend)
    func deleteFriendConnection(recordName: String) async throws {
        let recordID = CKRecord.ID(recordName: recordName)
        do {
            try await publicDatabase.deleteRecord(withID: recordID)
        } catch let error as CKError {
            throw mapCKError(error)
        }
    }

    /// Decline a friend request
    func declineFriendRequest(connectionRecordID: String) async throws {
        let recordID = CKRecord.ID(recordName: connectionRecordID)

        do {
            let record = try await publicDatabase.record(for: recordID)
            record[CloudKitConfig.Field.status] = FriendConnectionStatus.declined.rawValue
            _ = try await publicDatabase.save(record)
        } catch let error as CKError {
            throw mapCKError(error)
        }
    }

    /// Fetch all friend connections for the current user
    func fetchFriendConnections() async throws -> [CKRecord] {
        guard isAuthenticated, let userID = currentUserID else {
            print("🔍 CloudKit: fetchFriendConnections - not authenticated")
            throw CloudKitError.notAuthenticated
        }

        print("🔍 CloudKit: fetchFriendConnections - querying for userID: \(userID)")

        // CloudKit doesn't support OR predicates, so run two separate queries
        var allRecords: [CKRecord] = []

        // Query where we are the initiator
        let initiatorPredicate = NSPredicate(format: "%K == %@", CloudKitConfig.Field.initiatorUserID, userID)
        let initiatorQuery = CKQuery(recordType: CloudKitConfig.RecordType.friendConnection, predicate: initiatorPredicate)

        do {
            let (results, _) = try await publicDatabase.records(matching: initiatorQuery)
            let records = results.compactMap { try? $0.1.get() }
            print("🔍 CloudKit: Found \(records.count) records as initiator")
            allRecords.append(contentsOf: records)
        } catch let error as CKError {
            print("🔍 CloudKit: Error querying initiator: \(error.localizedDescription)")
            throw mapCKError(error)
        }

        // Query where we are the receiver
        let receiverPredicate = NSPredicate(format: "%K == %@", CloudKitConfig.Field.receiverUserID, userID)
        let receiverQuery = CKQuery(recordType: CloudKitConfig.RecordType.friendConnection, predicate: receiverPredicate)

        do {
            let (results, _) = try await publicDatabase.records(matching: receiverQuery)
            let records = results.compactMap { try? $0.1.get() }
            print("🔍 CloudKit: Found \(records.count) records as receiver")
            allRecords.append(contentsOf: records)
        } catch let error as CKError {
            print("🔍 CloudKit: Error querying receiver: \(error.localizedDescription)")
            throw mapCKError(error)
        }

        print("🔍 CloudKit: Total connections found: \(allRecords.count)")
        return allRecords
    }

    // MARK: - Messaging

    /// Send a motivational message to a friend
    func sendMessage(toUserID receiverID: String, templateID: String) async throws {
        guard isAuthenticated, let userID = currentUserID else {
            throw CloudKitError.notAuthenticated
        }

        let recordID = CKRecord.ID(recordName: "message_\(UUID().uuidString)")
        let record = CKRecord(recordType: CloudKitConfig.RecordType.motivationalMessage, recordID: recordID)

        record[CloudKitConfig.Field.senderUserID] = userID
        record[CloudKitConfig.Field.receiverUserID] = receiverID
        record[CloudKitConfig.Field.templateID] = templateID
        record[CloudKitConfig.Field.sentDate] = Date()
        record[CloudKitConfig.Field.isRead] = 0

        let displayName = currentUserDisplayName
        if !displayName.isEmpty {
            record[CloudKitConfig.Field.senderDisplayName] = displayName
        }

        try await saveMessageRecord(record, withDisplayName: !displayName.isEmpty)
    }

    /// Send a custom text message to a friend
    func sendCustomMessage(toUserID receiverID: String, message: String) async throws {
        guard isAuthenticated, let userID = currentUserID else {
            throw CloudKitError.notAuthenticated
        }

        let recordID = CKRecord.ID(recordName: "message_\(UUID().uuidString)")
        let record = CKRecord(recordType: CloudKitConfig.RecordType.motivationalMessage, recordID: recordID)

        record[CloudKitConfig.Field.senderUserID] = userID
        record[CloudKitConfig.Field.receiverUserID] = receiverID
        record[CloudKitConfig.Field.templateID] = "custom"
        record[CloudKitConfig.Field.customMessageText] = message
        record[CloudKitConfig.Field.sentDate] = Date()
        record[CloudKitConfig.Field.isRead] = 0

        let displayName = currentUserDisplayName
        if !displayName.isEmpty {
            record[CloudKitConfig.Field.senderDisplayName] = displayName
        }

        try await saveMessageRecord(record, withDisplayName: !displayName.isEmpty)
    }

    /// Save a message record, falling back to a save without senderDisplayName if the schema
    /// field isn't yet promoted to Production.
    private func saveMessageRecord(_ record: CKRecord, withDisplayName: Bool) async throws {
        do {
            _ = try await publicDatabase.save(record)
        } catch let error as CKError where withDisplayName {
            // senderDisplayName field may not exist in Production schema yet — retry without it
            print("⚠️ Message save failed (possibly schema), retrying without senderDisplayName: \(error.localizedDescription)")
            record[CloudKitConfig.Field.senderDisplayName] = nil
            do {
                _ = try await publicDatabase.save(record)
            } catch let retryError as CKError {
                throw mapCKError(retryError)
            }
        } catch let error as CKError {
            throw mapCKError(error)
        }
    }

    /// Fetch unread messages for the current user
    func fetchUnreadMessages() async throws -> [CKRecord] {
        guard isAuthenticated, let userID = currentUserID else {
            throw CloudKitError.notAuthenticated
        }

        let predicate = NSPredicate(
            format: "%K == %@ AND %K == %d",
            CloudKitConfig.Field.receiverUserID, userID,
            CloudKitConfig.Field.isRead, 0
        )

        let query = CKQuery(recordType: CloudKitConfig.RecordType.motivationalMessage, predicate: predicate)
        query.sortDescriptors = [NSSortDescriptor(key: CloudKitConfig.Field.sentDate, ascending: false)]

        do {
            let (results, _) = try await publicDatabase.records(matching: query)
            return results.compactMap { try? $0.1.get() }
        } catch let error as CKError {
            throw mapCKError(error)
        }
    }

    /// Mark a message as read
    func markMessageAsRead(recordID: String) async throws {
        let ckRecordID = CKRecord.ID(recordName: recordID)

        do {
            let record = try await publicDatabase.record(for: ckRecordID)
            record[CloudKitConfig.Field.isRead] = 1
            _ = try await publicDatabase.save(record)
        } catch let error as CKError {
            throw mapCKError(error)
        }
    }

    // MARK: - Subscriptions

    /// Set up subscriptions for real-time updates
    func setupSubscriptions() async throws {
        guard isAuthenticated, let userID = currentUserID else { return }

        print("🔔 CloudKit: Setting up subscriptions for user: \(userID)")

        // Subscribe to new friend requests (where we are the receiver)
        try await createSubscription(
            id: "friend-requests-\(userID)",
            recordType: CloudKitConfig.RecordType.friendConnection,
            predicate: NSPredicate(format: "%K == %@", CloudKitConfig.Field.receiverUserID, userID),
            options: [.firesOnRecordCreation],
            titleKey: "notification_friend_request_title",
            bodyKey: "notification_friend_request_body",
            category: "FRIEND_REQUEST"
        )

        // Subscribe to friend request accepted (where we are the initiator)
        try await createSubscription(
            id: "friend-accepted-\(userID)",
            recordType: CloudKitConfig.RecordType.friendConnection,
            predicate: NSPredicate(format: "%K == %@ AND %K == %@",
                CloudKitConfig.Field.initiatorUserID, userID,
                CloudKitConfig.Field.status, "accepted"),
            options: [.firesOnRecordUpdate],
            titleKey: "notification_friend_request_title",
            bodyKey: "notification_friend_request_body",
            category: "FRIEND_REQUEST"
        )

        // Subscribe to new messages — show sender name dynamically in push body
        try await createSubscription(
            id: "messages-\(userID)",
            recordType: CloudKitConfig.RecordType.motivationalMessage,
            predicate: NSPredicate(format: "%K == %@", CloudKitConfig.Field.receiverUserID, userID),
            options: [.firesOnRecordCreation],
            titleKey: "notification_message_title",
            bodyKey: "notification_message_body_from",
            category: "FRIEND_MESSAGE",
            bodyArgs: [CloudKitConfig.Field.senderDisplayName],
            desiredKeys: [CloudKitConfig.Field.senderDisplayName]
        )

        // Subscribe to challenge invites (where user is participant and status is pending)
        try await createSubscription(
            id: "challenge-invites-\(userID)",
            recordType: CloudKitConfig.RecordType.sharedChallenge,
            predicate: NSPredicate(format: "%K == %@ AND %K == %@",
                CloudKitConfig.Field.participantUserID, userID,
                CloudKitConfig.Field.status, ChallengeStatus.pending.rawValue),
            options: [.firesOnRecordCreation],
            titleKey: "notification_challenge_invite_title",
            bodyKey: "notification_challenge_invite_body",
            category: "CHALLENGE_INVITE"
        )

        print("🔔 CloudKit: Subscriptions set up successfully")
    }

    /// Create or update a CloudKit subscription
    private func createSubscription(
        id: String,
        recordType: String,
        predicate: NSPredicate,
        options: CKQuerySubscription.Options,
        titleKey: String,
        bodyKey: String,
        category: String,
        bodyArgs: [String]? = nil,
        desiredKeys: [String]? = nil
    ) async throws {
        let subscription = CKQuerySubscription(
            recordType: recordType,
            predicate: predicate,
            subscriptionID: id,
            options: options
        )

        let notificationInfo = CKSubscription.NotificationInfo()
        notificationInfo.titleLocalizationKey = titleKey
        notificationInfo.alertLocalizationKey = bodyKey
        if let bodyArgs = bodyArgs {
            notificationInfo.alertLocalizationArgs = bodyArgs
        }
        if let desiredKeys = desiredKeys {
            notificationInfo.desiredKeys = desiredKeys
        }
        // Do NOT set shouldSendContentAvailable = true — that routes delivery as a
        // silent background push, which never shows a visible notification banner.
        notificationInfo.shouldBadge = true
        notificationInfo.category = category
        notificationInfo.soundName = "default"
        subscription.notificationInfo = notificationInfo

        // Always delete first to ensure updated notification info (e.g., new bodyArgs) takes effect
        try? await publicDatabase.deleteSubscription(withID: id)

        do {
            _ = try await publicDatabase.save(subscription)
            print("🔔 CloudKit: Created subscription: \(id)")
        } catch let error as CKError {
            throw mapCKError(error)
        }
    }

    /// Remove all subscriptions (for sign out or disabling notifications)
    func removeAllSubscriptions() async {
        do {
            let subscriptions = try await publicDatabase.allSubscriptions()
            for subscription in subscriptions {
                try await publicDatabase.deleteSubscription(withID: subscription.subscriptionID)
            }
            print("🔔 CloudKit: Removed all subscriptions")
        } catch {
            print("🔔 CloudKit: Error removing subscriptions: \(error)")
        }
    }

    // MARK: - User Search

    /// Search for users by username
    func searchUsers(query: String) async throws -> [(userID: String, username: String, displayName: String, avatarEmoji: String)] {
        guard isAuthenticated, let currentUser = currentUserID else {
            throw CloudKitError.notAuthenticated
        }

        // Remove @ prefix if user typed it
        var searchQuery = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if searchQuery.hasPrefix("@") {
            searchQuery = String(searchQuery.dropFirst())
        }
        guard !searchQuery.isEmpty else { return [] }

        // Query for discoverable users
        let predicate = NSPredicate(format: "%K == %d", CloudKitConfig.Field.isDiscoverable, 1)
        let ckQuery = CKQuery(recordType: CloudKitConfig.RecordType.userProfile, predicate: predicate)

        do {
            let (results, _) = try await publicDatabase.records(matching: ckQuery)
            let records = results.compactMap { try? $0.1.get() }

            // Filter client-side by username (CloudKit doesn't support case-insensitive contains)
            return records.compactMap { record -> (String, String, String, String)? in
                let username = record[CloudKitConfig.Field.username] as? String ?? ""
                let displayName = record[CloudKitConfig.Field.displayName] as? String ?? ""
                let avatarEmoji = record[CloudKitConfig.Field.avatarEmoji] as? String ?? "😊"

                // Extract userID from record name (format: "profile_USERID")
                let recordName = record.recordID.recordName
                let userID = recordName.hasPrefix("profile_") ? String(recordName.dropFirst(8)) : recordName

                // Don't include ourselves
                guard userID != currentUser else { return nil }

                // Check if username contains search query
                guard username.lowercased().contains(searchQuery) else { return nil }

                return (userID, username, displayName, avatarEmoji)
            }
        } catch let error as CKError {
            throw mapCKError(error)
        }
    }

    // MARK: - Invite Link Generation

    /// Generate an invite link for sharing
    func generateInviteLink() -> URL? {
        guard let userID = currentUserID else { return nil }

        var components = URLComponents()
        components.scheme = "stick"
        components.host = "friend"
        components.path = "/invite"
        components.queryItems = [
            URLQueryItem(name: "id", value: userID)
        ]

        return components.url
    }

    /// Generate a universal link for sharing (for iOS 14+)
    func generateUniversalInviteLink() -> URL? {
        guard let userID = currentUserID else { return nil }

        var components = URLComponents()
        components.scheme = "https"
        components.host = "stick-app.com"
        components.path = "/friend/invite"
        components.queryItems = [
            URLQueryItem(name: "id", value: userID)
        ]

        return components.url
    }

    // MARK: - Shared Challenges

    /// Save a new challenge to CloudKit
    func saveChallenge(_ challenge: SharedChallenge) async throws {
        guard isAuthenticated, currentUserID != nil else {
            throw CloudKitError.notAuthenticated
        }

        let recordID = CKRecord.ID(recordName: "challenge_\(challenge.challengeID)")
        let record = CKRecord(recordType: CloudKitConfig.RecordType.sharedChallenge, recordID: recordID)

        record[CloudKitConfig.Field.challengeID] = challenge.challengeID
        record[CloudKitConfig.Field.creatorUserID] = challenge.creatorUserID
        record[CloudKitConfig.Field.participantUserID] = challenge.participantUserID
        record[CloudKitConfig.Field.habitName] = challenge.habitName
        record[CloudKitConfig.Field.habitEmoji] = challenge.habitEmoji
        record[CloudKitConfig.Field.habitColor] = challenge.habitColor
        record[CloudKitConfig.Field.targetDays] = challenge.targetDays
        record[CloudKitConfig.Field.status] = challenge.statusRaw
        record[CloudKitConfig.Field.createdDate] = challenge.createdDate
        record[CloudKitConfig.Field.isCollaborative] = challenge.isCollaborative ? 1 : 0

        if let startDate = challenge.startDate {
            record[CloudKitConfig.Field.startDate] = startDate
        }
        if let endDate = challenge.endDate {
            record[CloudKitConfig.Field.endDate] = endDate
        }

        do {
            _ = try await publicDatabase.save(record)
            challenge.cloudRecordID = recordID.recordName
            print("Challenge saved: \(challenge.challengeID)")
        } catch let error as CKError {
            throw mapCKError(error)
        }
    }

    /// Fetch all challenges where user is creator OR participant
    func fetchChallenges() async throws -> [CKRecord] {
        guard isAuthenticated, let userID = currentUserID else {
            throw CloudKitError.notAuthenticated
        }

        print("Fetching challenges for user: \(userID)")

        var allRecords: [CKRecord] = []

        // Query where user is creator
        let creatorPredicate = NSPredicate(format: "%K == %@", CloudKitConfig.Field.creatorUserID, userID)
        let creatorQuery = CKQuery(recordType: CloudKitConfig.RecordType.sharedChallenge, predicate: creatorPredicate)

        do {
            let (results, _) = try await publicDatabase.records(matching: creatorQuery)
            let records = results.compactMap { try? $0.1.get() }
            print("Found \(records.count) challenges as creator")
            allRecords.append(contentsOf: records)
        } catch let error as CKError {
            print("Error fetching creator challenges: \(error)")
            throw mapCKError(error)
        }

        // Query where user is participant
        let participantPredicate = NSPredicate(format: "%K == %@", CloudKitConfig.Field.participantUserID, userID)
        let participantQuery = CKQuery(recordType: CloudKitConfig.RecordType.sharedChallenge, predicate: participantPredicate)

        do {
            let (results, _) = try await publicDatabase.records(matching: participantQuery)
            let records = results.compactMap { try? $0.1.get() }
            print("Found \(records.count) challenges as participant")
            allRecords.append(contentsOf: records)
        } catch let error as CKError {
            print("Error fetching participant challenges: \(error)")
            throw mapCKError(error)
        }

        print("Total challenges found: \(allRecords.count)")
        return allRecords
    }

    /// Update challenge status in CloudKit
    func updateChallengeStatus(challengeID: String, status: ChallengeStatus, startDate: Date? = nil, endDate: Date? = nil) async throws {
        let recordID = CKRecord.ID(recordName: "challenge_\(challengeID)")

        do {
            let record = try await publicDatabase.record(for: recordID)
            record[CloudKitConfig.Field.status] = status.rawValue

            if let startDate = startDate {
                record[CloudKitConfig.Field.startDate] = startDate
            }
            if let endDate = endDate {
                record[CloudKitConfig.Field.endDate] = endDate
            }

            _ = try await publicDatabase.save(record)
            print("Challenge status updated: \(challengeID) -> \(status.rawValue)")
        } catch let error as CKError {
            throw mapCKError(error)
        }
    }

    /// Save challenge progress (mark a day complete).
    /// Uses upsert so an existing HK-snapshot record for the same day is updated rather than rejected.
    func saveChallengeProgress(challengeID: String, date: Date) async throws {
        guard isAuthenticated, let userID = currentUserID else {
            throw CloudKitError.notAuthenticated
        }

        let dayStart = Calendar.current.startOfDay(for: date)
        let recordName = "cp_\(challengeID)_\(userID)_\(Int(dayStart.timeIntervalSince1970))"
        let recordID = CKRecord.ID(recordName: recordName)

        // Upsert: reuse an existing record (e.g. HK snapshot) to avoid serverRecordChanged errors
        let record: CKRecord
        if let existing = try? await publicDatabase.record(for: recordID) {
            record = existing
        } else {
            record = CKRecord(recordType: CloudKitConfig.RecordType.challengeProgress, recordID: recordID)
            record[CloudKitConfig.Field.challengeID] = challengeID
            record[CloudKitConfig.Field.userID] = userID
            record[CloudKitConfig.Field.date] = dayStart
        }
        record[CloudKitConfig.Field.isCompleted] = true
        record[CloudKitConfig.Field.completedAt] = Date()

        do {
            _ = try await publicDatabase.save(record)
            print("Challenge progress saved: \(recordName)")
        } catch let error as CKError {
            throw mapCKError(error)
        }
    }

    /// Set up a silent push subscription so the app is woken when the partner marks a challenge day complete.
    /// Safe to call multiple times — duplicate subscriptions are silently ignored.
    func setupChallengeProgressSubscription(challengeID: String, partnerUserID: String) async {
        let subscriptionID = "challenge-progress-\(challengeID)-\(partnerUserID)"
        let predicate = NSPredicate(format: "%K == %@ AND %K == %@",
            CloudKitConfig.Field.challengeID, challengeID,
            CloudKitConfig.Field.userID, partnerUserID)

        let subscription = CKQuerySubscription(
            recordType: CloudKitConfig.RecordType.challengeProgress,
            predicate: predicate,
            subscriptionID: subscriptionID,
            options: [.firesOnRecordCreation, .firesOnRecordUpdate]
        )

        let notificationInfo = CKSubscription.NotificationInfo()
        notificationInfo.shouldSendContentAvailable = true  // silent background push
        subscription.notificationInfo = notificationInfo

        do {
            _ = try await publicDatabase.save(subscription)
            print("🔔 CloudKit: Created ChallengeProgress subscription: \(subscriptionID)")
        } catch let error as CKError {
            // serverRejectedRequest = already exists — that's fine
            if error.code != .serverRejectedRequest {
                print("🔔 CloudKit: Failed to create ChallengeProgress subscription: \(error)")
            }
        } catch {
            print("🔔 CloudKit: Failed to create ChallengeProgress subscription: \(error)")
        }
    }

    /// Fetch all progress records for a challenge
    func fetchChallengeProgress(challengeID: String) async throws -> [CKRecord] {
        let predicate = NSPredicate(format: "%K == %@", CloudKitConfig.Field.challengeID, challengeID)
        let query = CKQuery(recordType: CloudKitConfig.RecordType.challengeProgress, predicate: predicate)

        do {
            let (results, _) = try await publicDatabase.records(matching: query)
            let records = results.compactMap { try? $0.1.get() }
            print("Found \(records.count) progress records for challenge \(challengeID)")
            return records
        } catch let error as CKError {
            throw mapCKError(error)
        }
    }

    /// Fetch progress for a specific user in a challenge
    func fetchChallengeProgress(challengeID: String, userID: String) async throws -> [CKRecord] {
        let predicate = NSPredicate(format: "%K == %@ AND %K == %@",
            CloudKitConfig.Field.challengeID, challengeID,
            CloudKitConfig.Field.userID, userID)
        let query = CKQuery(recordType: CloudKitConfig.RecordType.challengeProgress, predicate: predicate)

        do {
            let (results, _) = try await publicDatabase.records(matching: query)
            return results.compactMap { try? $0.1.get() }
        } catch let error as CKError {
            throw mapCKError(error)
        }
    }

    /// Upload today's HealthKit value for a challenge (best-effort upsert).
    /// Uses the same deterministic record name as saveChallengeProgress so the
    /// value lives on the same record when the user later marks complete.
    func saveHKSnapshot(challengeID: String, value: Double) async throws {
        guard isAuthenticated, let userID = currentUserID else {
            throw CloudKitError.notAuthenticated
        }

        let dayStart = Calendar.current.startOfDay(for: Date())
        let recordName = "cp_\(challengeID)_\(userID)_\(Int(dayStart.timeIntervalSince1970))"
        let recordID = CKRecord.ID(recordName: recordName)

        // Fetch existing record or create new one
        let record: CKRecord
        if let existing = try? await publicDatabase.record(for: recordID) {
            record = existing
        } else {
            record = CKRecord(recordType: CloudKitConfig.RecordType.challengeProgress, recordID: recordID)
            record[CloudKitConfig.Field.challengeID] = challengeID
            record[CloudKitConfig.Field.userID] = userID
            record[CloudKitConfig.Field.date] = dayStart
        }
        record[CloudKitConfig.Field.hkValue] = value

        do {
            _ = try await publicDatabase.save(record)
        } catch let error as CKError {
            throw mapCKError(error)
        }
    }

    /// Fetch the friend's most recent HealthKit snapshot value for today.
    /// Returns nil if not available (friend hasn't opened app today).
    func fetchFriendHKSnapshot(challengeID: String, friendUserID: String) async -> Double? {
        let dayStart = Calendar.current.startOfDay(for: Date())
        let recordName = "cp_\(challengeID)_\(friendUserID)_\(Int(dayStart.timeIntervalSince1970))"
        let recordID = CKRecord.ID(recordName: recordName)

        guard let record = try? await publicDatabase.record(for: recordID) else { return nil }
        return record[CloudKitConfig.Field.hkValue] as? Double
    }

    /// Check if today is already completed for a challenge
    func isChallengeCompletedToday(challengeID: String) async -> Bool {
        guard let userID = currentUserID else { return false }

        let dayStart = Calendar.current.startOfDay(for: Date())
        let recordName = "cp_\(challengeID)_\(userID)_\(Int(dayStart.timeIntervalSince1970))"
        let recordID = CKRecord.ID(recordName: recordName)

        do {
            _ = try await publicDatabase.record(for: recordID)
            return true
        } catch {
            return false
        }
    }

    // MARK: - Offline Queue

    private func queueOfflineOperation(_ operation: @escaping () async throws -> Void) {
        offlineQueue.append(operation)
    }

    /// Process queued operations when network becomes available
    func processOfflineQueue() async {
        let operations = offlineQueue
        offlineQueue.removeAll()

        for operation in operations {
            do {
                try await operation()
            } catch {
                // Re-queue if still offline
                if let ckError = error as? CloudKitError,
                   case .networkUnavailable = ckError {
                    offlineQueue.append(operation)
                }
            }
        }
    }

    // MARK: - Error Mapping

    private func mapCKError(_ error: CKError) -> CloudKitError {
        switch error.code {
        case .notAuthenticated:
            return .notAuthenticated
        case .networkUnavailable, .networkFailure:
            return .networkUnavailable
        case .quotaExceeded:
            return .quotaExceeded
        case .unknownItem:
            return .recordNotFound
        case .permissionFailure:
            return .permissionDenied
        case .serverResponseLost, .serviceUnavailable, .requestRateLimited:
            return .serverError(error)
        default:
            return .unknown(error)
        }
    }
}
