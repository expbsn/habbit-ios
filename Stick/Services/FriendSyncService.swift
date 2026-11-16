//
//  FriendSyncService.swift
//  Stick
//
//  Background service for syncing friend progress data.
//

import Foundation
import CloudKit
import SwiftData
import Combine

/// Service responsible for syncing friend progress data in the background.
@MainActor
final class FriendSyncService: ObservableObject {
    static let shared = FriendSyncService()

    // MARK: - Published State

    @Published var isSyncing = false
    @Published var lastSyncDate: Date?
    @Published var syncError: CloudKitError?
    @Published var unreadMessageCount = 0

    // MARK: - Private Properties

    private let cloudKitService = CloudKitService.shared
    private var syncTimer: Timer?
    private var cancellables = Set<AnyCancellable>()
    private var lastProgressUploadDate: Date?
    private var isUploadingProgress = false
    private var lastFullSyncDate: Date?
    /// Minimum seconds between full syncs (prevents redundant calls on tab-switch/foreground)
    private let fullSyncDebounceInterval: TimeInterval = 30

    private init() {
        setupObservers()
    }

    private func setupObservers() {
        // Listen for account status changes
        cloudKitService.$isAuthenticated
            .sink { [weak self] isAuthenticated in
                if isAuthenticated {
                    Task {
                        await self?.performInitialSync()
                    }
                }
            }
            .store(in: &cancellables)
    }

    // MARK: - Sync Operations

    /// Perform initial sync when app launches or user authenticates
    func performInitialSync(context: ModelContext? = nil) async {
        guard cloudKitService.isAuthenticated else { return }

        // Debounce: skip if we ran a full sync recently
        if let last = lastFullSyncDate, Date().timeIntervalSince(last) < fullSyncDebounceInterval {
            return
        }

        isSyncing = true
        defer { isSyncing = false }

        do {
            // Sync all friend connections
            try await syncFriendConnections(context: context)

            // Sync friend progress data
            await syncFriendProgress(context: context)

            // Fetch unread messages
            try await syncMessages(context: context)

            // Sync shared challenges
            if let context = context {
                await ChallengeSyncService.shared.syncChallenges(context: context)
            }

            lastSyncDate = Date()
            lastFullSyncDate = Date()
            syncError = nil
        } catch let error as CloudKitError {
            syncError = error
            print("Initial sync failed: \(error.localizedDescription ?? "Unknown error")")
        } catch {
            syncError = .unknown(error)
            print("Initial sync failed: \(error)")
        }
    }

    /// Sync progress data for all accepted friends
    func syncFriendProgress(context: ModelContext? = nil) async {
        guard let context = context else { return }

        // Fetch all accepted friends
        let descriptor = FetchDescriptor<FriendProfile>(
            predicate: #Predicate { $0.connectionStatus == "accepted" }
        )

        do {
            let friends = try context.fetch(descriptor)
            guard !friends.isEmpty else { return }

            let friendIDs = friends.map { $0.cloudUserID }

            // Step 1: Fetch today's progress for all friends (batch)
            let progressData = await cloudKitService.fetchAllFriendsProgress(friendUserIDs: friendIDs)

            // Step 2: Apply today's progress to all friends immediately, then save
            for friend in friends {
                if let progress = progressData[friend.cloudUserID] {
                    friend.todayCompletionPercentage = progress.completionPercentage
                    friend.currentStreak = progress.currentStreak
                    friend.lastProgressUpdate = Date()
                } else {
                    // No progress record for today - reset to 0 (new day or no habits completed yet)
                    friend.todayCompletionPercentage = 0.0
                    friend.lastProgressUpdate = Date()
                }
            }
            try context.save()

            // Step 3: Fetch week progress for ALL friends concurrently
            let cloudKitService = self.cloudKitService
            var weekProgressByFriend: [String: [Date: Double]] = [:]
            await withTaskGroup(of: (String, [Date: Double]).self) { group in
                for friend in friends {
                    let friendID = friend.cloudUserID
                    group.addTask {
                        let weekProgress = await cloudKitService.fetchFriendWeekProgress(friendUserID: friendID)
                        return (friendID, weekProgress)
                    }
                }
                for await (friendID, weekProgress) in group {
                    weekProgressByFriend[friendID] = weekProgress
                }
            }

            // Step 4: Apply week results to friends, then save
            for friend in friends {
                let weekProgress = weekProgressByFriend[friend.cloudUserID] ?? [:]
                if !weekProgress.isEmpty {
                    friend.setWeekProgress(weekProgress)

                    // Calculate weekly average from fetched data
                    let validProgress = weekProgress.values.filter { $0 >= 0 }
                    if !validProgress.isEmpty {
                        let average = validProgress.reduce(0.0, +) / Double(validProgress.count)
                        friend.weeklyAverageCompletion = average
                        // For now, use the same for monthly (we only have 7 days of data)
                        friend.monthlyAverageCompletion = average
                        print("📊 FriendSync: Calculated weekly average for \(friend.displayName): \(Int(average * 100))%")
                    }

                    print("📊 FriendSync: Fetched \(weekProgress.count) days of progress for \(friend.displayName)")
                } else if friend.todayCompletionPercentage > 0 {
                    // No week history available, use today's progress as fallback
                    friend.weeklyAverageCompletion = friend.todayCompletionPercentage
                    friend.monthlyAverageCompletion = friend.todayCompletionPercentage
                    print("📊 FriendSync: Using today's progress as weekly average for \(friend.displayName): \(Int(friend.todayCompletionPercentage * 100))%")
                }
            }

            try context.save()
            print("📊 FriendSync: Updated progress for \(progressData.count) friends")
        } catch {
            print("📊 FriendSync: Error syncing friend progress: \(error)")
        }
    }

    /// Fast sync: today's progress only (no 7-day history). Use on foreground to avoid N×7 CloudKit calls.
    func syncTodayProgress(context: ModelContext?) async {
        guard let context = context, cloudKitService.isAuthenticated else { return }

        let descriptor = FetchDescriptor<FriendProfile>(
            predicate: #Predicate { $0.connectionStatus == "accepted" }
        )

        do {
            let friends = try context.fetch(descriptor)
            guard !friends.isEmpty else { return }

            let progressData = await cloudKitService.fetchAllFriendsProgress(
                friendUserIDs: friends.map { $0.cloudUserID }
            )

            for friend in friends {
                if let progress = progressData[friend.cloudUserID] {
                    friend.todayCompletionPercentage = progress.completionPercentage
                    friend.currentStreak = progress.currentStreak
                    friend.lastProgressUpdate = Date()
                } else {
                    friend.todayCompletionPercentage = 0.0
                    friend.lastProgressUpdate = Date()
                }
            }
            try context.save()
        } catch {
            print("📊 FriendSync: Error syncing today's progress: \(error)")
        }
    }

    /// Sync messages only — lightweight refresh for message push notifications
    func syncMessagesOnly(context: ModelContext?) async {
        try? await syncMessages(context: context)
    }

    /// Sync friend connections from CloudKit to local SwiftData
    func syncFriendConnections(context: ModelContext? = nil) async throws {
        guard cloudKitService.isAuthenticated else {
            print("🔄 FriendSync: Not authenticated, skipping sync")
            return
        }

        print("🔄 FriendSync: Fetching friend connections...")
        let records = try await cloudKitService.fetchFriendConnections()
        print("🔄 FriendSync: Found \(records.count) connection records")

        guard let context = context else {
            print("🔄 FriendSync: No context provided, skipping processing")
            return
        }

        for record in records {
            await processFriendConnectionRecord(record, context: context)
        }

        try context.save()
        print("🔄 FriendSync: Saved \(records.count) connections to local storage")
    }

    /// Process a single friend connection record
    private func processFriendConnectionRecord(_ record: CKRecord, context: ModelContext) async {
        guard let currentUserID = cloudKitService.currentUserID else {
            print("🔄 FriendSync: No currentUserID, skipping record")
            return
        }

        let initiatorID = record[CloudKitConfig.Field.initiatorUserID] as? String ?? ""
        let receiverID = record[CloudKitConfig.Field.receiverUserID] as? String ?? ""
        let statusString = record[CloudKitConfig.Field.status] as? String ?? ""
        let status = FriendConnectionStatus(rawValue: statusString) ?? .pending

        print("🔄 FriendSync: Processing connection - initiator: \(initiatorID), receiver: \(receiverID), status: \(statusString)")
        print("🔄 FriendSync: Current user: \(currentUserID)")

        // Determine if we are the initiator
        let isInitiator = initiatorID == currentUserID
        let friendUserID = isInitiator ? receiverID : initiatorID

        print("🔄 FriendSync: isInitiator: \(isInitiator), friendUserID: \(friendUserID)")

        // Check if this friend already exists locally
        let descriptor = FetchDescriptor<FriendProfile>(
            predicate: #Predicate { $0.cloudUserID == friendUserID }
        )

        do {
            let existingFriends = try context.fetch(descriptor)

            if let existingFriend = existingFriends.first {
                // Update existing friend
                print("🔄 FriendSync: Updating existing friend - old status: \(existingFriend.connectionStatus), new status: \(status.rawValue), isInitiator: \(isInitiator)")
                existingFriend.status = status
                // If we're the receiver of a pending request, mark as incoming (not initiator)
                // This is important for showing the request in the correct section
                if status == .pending && !isInitiator {
                    existingFriend.isInitiator = false
                }
                if let acceptedDate = record[CloudKitConfig.Field.acceptedDate] as? Date {
                    existingFriend.acceptedDate = acceptedDate
                }

                // Re-fetch profile info if we have placeholder data
                if existingFriend.displayName == "Friend" || existingFriend.avatarEmoji == "😊" {
                    if let profileInfo = try? await cloudKitService.fetchUserProfile(userID: friendUserID) {
                        print("🔄 FriendSync: Updated profile info - name: \(profileInfo.displayName)")
                        existingFriend.displayName = profileInfo.displayName
                        existingFriend.avatarEmoji = profileInfo.avatarEmoji
                    }
                }
            } else {
                // Create new friend profile
                print("🔄 FriendSync: Creating new friend profile for \(friendUserID)")
                // First fetch their profile info
                if let profileInfo = try? await cloudKitService.fetchUserProfile(userID: friendUserID) {
                    print("🔄 FriendSync: Got profile info - name: \(profileInfo.displayName)")
                    let friend = FriendProfile(
                        cloudUserID: friendUserID,
                        displayName: profileInfo.displayName,
                        avatarEmoji: profileInfo.avatarEmoji,
                        connectionStatus: status,
                        isInitiator: isInitiator
                    )
                    context.insert(friend)
                    print("🔄 FriendSync: Inserted friend with status: \(status.rawValue), isInitiator: \(isInitiator)")
                } else {
                    // Create with placeholder info
                    print("🔄 FriendSync: No profile found, using placeholder")
                    let friend = FriendProfile(
                        cloudUserID: friendUserID,
                        displayName: "Friend",
                        avatarEmoji: "😊",
                        connectionStatus: status,
                        isInitiator: isInitiator
                    )
                    context.insert(friend)
                    print("🔄 FriendSync: Inserted placeholder friend with status: \(status.rawValue)")
                }
            }
        } catch {
            print("❌ FriendSync: Error processing friend connection: \(error)")
        }
    }

    /// Sync messages from CloudKit
    func syncMessages(context: ModelContext? = nil) async throws {
        guard cloudKitService.isAuthenticated else { return }

        let records = try await cloudKitService.fetchUnreadMessages()
        guard let context = context else {
            unreadMessageCount = records.count
            return
        }

        for record in records {
            await processMessageRecord(record, context: context)
        }

        try context.save()

        // Update unread count
        unreadMessageCount = ReceivedMessage.unreadCount(in: context)
    }

    /// Process a single message record
    private func processMessageRecord(_ record: CKRecord, context: ModelContext) async {
        let recordID = record.recordID.recordName
        let senderUserID = record[CloudKitConfig.Field.senderUserID] as? String ?? ""
        let templateID = record[CloudKitConfig.Field.templateID] as? String ?? ""
        let customMessageText = record[CloudKitConfig.Field.customMessageText] as? String
        let sentDate = record[CloudKitConfig.Field.sentDate] as? Date ?? Date()
        // Use embedded display name if available (stored since push-notification update)
        let embeddedDisplayName = record[CloudKitConfig.Field.senderDisplayName] as? String ?? ""

        // Check if message already exists
        let descriptor = FetchDescriptor<ReceivedMessage>(
            predicate: #Predicate { $0.cloudRecordID == recordID }
        )

        do {
            let existingMessages = try context.fetch(descriptor)
            if existingMessages.isEmpty {
                var senderName = embeddedDisplayName.isEmpty ? "Friend" : embeddedDisplayName
                var senderEmoji = "😊"

                // Only fetch profile if display name wasn't embedded in the record
                if embeddedDisplayName.isEmpty,
                   let profileInfo = try? await cloudKitService.fetchUserProfile(userID: senderUserID) {
                    senderName = profileInfo.displayName
                    senderEmoji = profileInfo.avatarEmoji
                } else if let profileInfo = try? await cloudKitService.fetchUserProfile(userID: senderUserID) {
                    // Still fetch emoji even if we have the name
                    senderEmoji = profileInfo.avatarEmoji
                }

                // Create new message
                let message = ReceivedMessage(
                    cloudRecordID: recordID,
                    senderUserID: senderUserID,
                    senderDisplayName: senderName,
                    senderAvatarEmoji: senderEmoji,
                    templateID: templateID,
                    customMessageText: customMessageText,
                    sentDate: sentDate
                )
                context.insert(message)
            }
        } catch {
            print("Error processing message: \(error)")
        }
    }

    /// Upload local progress to CloudKit (throttled to prevent rapid duplicate uploads)
    func uploadProgress(habits: [Habit], skippedDates: Set<Date>, threshold: Double = 1.0) async {
        guard cloudKitService.isAuthenticated else {
            print("📤 FriendSync: Not uploading progress - not authenticated")
            return
        }

        // Throttle: don't upload if we uploaded within the last 5 seconds
        if let lastUpload = lastProgressUploadDate,
           Date().timeIntervalSince(lastUpload) < 5.0 {
            print("📤 FriendSync: Skipping upload - throttled (last upload was \(Int(Date().timeIntervalSince(lastUpload)))s ago)")
            return
        }

        // Prevent concurrent uploads
        guard !isUploadingProgress else {
            print("📤 FriendSync: Skipping upload - already in progress")
            return
        }

        isUploadingProgress = true
        defer { isUploadingProgress = false }

        let progress = ProgressTracker.progress(for: Date(), habits: habits)
        let completion = progress < 0 ? 0.0 : progress
        let streak = ProgressTracker.calculateStreak(habits: habits, skippedDates: skippedDates, threshold: threshold)

        print("📤 FriendSync: Uploading progress - completion: \(Int(completion * 100))%, streak: \(streak)")

        do {
            try await cloudKitService.saveProgress(completionPercentage: completion, currentStreak: streak)
            lastProgressUploadDate = Date()
            print("📤 FriendSync: Progress uploaded successfully")
        } catch {
            // Server Record Changed is not a real error - it means another upload just succeeded
            if "\(error)".contains("Server Record Changed") {
                print("📤 FriendSync: Record already updated (race condition), ignoring")
                lastProgressUploadDate = Date()
            } else {
                print("📤 FriendSync: Failed to upload progress: \(error)")
            }
        }
    }

    // MARK: - Periodic Sync

    /// Start periodic sync (every 5 minutes)
    func startPeriodicSync() {
        stopPeriodicSync()

        syncTimer = Timer.scheduledTimer(withTimeInterval: 300, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                await self?.performInitialSync()
            }
        }
    }

    /// Stop periodic sync
    func stopPeriodicSync() {
        syncTimer?.invalidate()
        syncTimer = nil
    }

    // MARK: - Message Actions

    /// Mark a message as read both locally and in CloudKit
    func markMessageAsRead(_ message: ReceivedMessage, context: ModelContext) async {
        message.markAsRead()

        do {
            try context.save()
            unreadMessageCount = ReceivedMessage.unreadCount(in: context)

            // Also mark as read in CloudKit
            if let recordID = message.cloudRecordID {
                try await cloudKitService.markMessageAsRead(recordID: recordID)
            }
        } catch {
            print("Error marking message as read: \(error)")
        }
    }

    /// Send a message to a friend
    func sendMessage(to friend: FriendProfile, template: MessageTemplate, context: ModelContext? = nil) async throws {
        try await cloudKitService.sendMessage(toUserID: friend.cloudUserID, templateID: template.rawValue)

        // Save sent message locally for chat display
        if let context = context {
            let sentMessage = SentMessage(
                recipientUserID: friend.cloudUserID,
                templateID: template.rawValue
            )
            context.insert(sentMessage)
            try? context.save()
        }
    }

    /// Send a custom message to a friend
    func sendCustomMessage(to friend: FriendProfile, message: String, context: ModelContext? = nil) async throws {
        try await cloudKitService.sendCustomMessage(toUserID: friend.cloudUserID, message: message)

        // Save sent message locally for chat display
        if let context = context {
            let sentMessage = SentMessage(
                recipientUserID: friend.cloudUserID,
                templateID: "custom",
                customMessageText: message
            )
            context.insert(sentMessage)
            try? context.save()
        }
    }

    // MARK: - Friend Actions

    /// Accept a friend request
    func acceptFriendRequest(_ friend: FriendProfile, context: ModelContext) async throws {
        // Find the connection record ID
        // Format: connection_<initiator>_<receiver>
        // For incoming requests, friend.cloudUserID is the initiator, we are the receiver
        let connectionID = "connection_\(friend.cloudUserID)_\(cloudKitService.currentUserID ?? "")"

        print("✅ FriendSync: Accepting request - connectionID: \(connectionID)")
        print("✅ FriendSync: friend.cloudUserID: \(friend.cloudUserID), currentUserID: \(cloudKitService.currentUserID ?? "nil")")

        do {
            try await cloudKitService.acceptFriendRequest(connectionRecordID: connectionID)
            print("✅ FriendSync: CloudKit accept succeeded")
        } catch {
            print("❌ FriendSync: CloudKit accept failed: \(error)")
            throw error
        }

        friend.status = .accepted
        friend.acceptedDate = Date()

        try context.save()
        print("✅ FriendSync: Local status updated to accepted")
    }

    /// Decline a friend request
    func declineFriendRequest(_ friend: FriendProfile, context: ModelContext) async throws {
        let connectionID = "connection_\(friend.cloudUserID)_\(cloudKitService.currentUserID ?? "")"

        try await cloudKitService.declineFriendRequest(connectionRecordID: connectionID)

        friend.status = .declined

        try context.save()
    }

    /// Remove an accepted friend — deletes locally immediately, best-effort CloudKit delete
    func removeFriend(_ friend: FriendProfile, context: ModelContext) async {
        // Delete local record first
        context.delete(friend)
        try? context.save()

        // Best-effort: delete the CloudKit connection record.
        // The record name depends on who initiated — try both variants.
        guard let myID = cloudKitService.currentUserID else { return }
        let friendID = friend.cloudUserID

        let recordName: String
        if friend.isInitiator {
            recordName = "connection_\(myID)_\(friendID)"
        } else {
            recordName = "connection_\(friendID)_\(myID)"
        }

        try? await cloudKitService.deleteFriendConnection(recordName: recordName)
    }

    /// Send a friend request (with profile data already known)
    func sendFriendRequest(toUserID userID: String, displayName: String, avatarEmoji: String, context: ModelContext) async throws {
        print("📤 FriendSync: Sending friend request to \(userID) (\(displayName))")

        try await cloudKitService.sendFriendRequest(toUserID: userID)
        print("📤 FriendSync: CloudKit request sent")

        // Create local friend profile with the data we already have
        let friend = FriendProfile(
            cloudUserID: userID,
            displayName: displayName,
            avatarEmoji: avatarEmoji,
            connectionStatus: .pending,
            isInitiator: true
        )
        context.insert(friend)
        try context.save()
        print("✅ FriendSync: Friend profile saved locally with name: \(displayName)")
    }

    /// Send a friend request (fetches profile data)
    func sendFriendRequest(toUserID userID: String, context: ModelContext) async throws {
        print("📤 FriendSync: Sending friend request to \(userID)")

        try await cloudKitService.sendFriendRequest(toUserID: userID)
        print("📤 FriendSync: CloudKit request sent, now fetching profile...")

        // Fetch the user's profile
        if let profileInfo = try? await cloudKitService.fetchUserProfile(userID: userID) {
            print("📤 FriendSync: Got profile - name: \(profileInfo.displayName), emoji: \(profileInfo.avatarEmoji)")
            let friend = FriendProfile(
                cloudUserID: userID,
                displayName: profileInfo.displayName,
                avatarEmoji: profileInfo.avatarEmoji,
                connectionStatus: .pending,
                isInitiator: true
            )
            context.insert(friend)
            try context.save()
            print("✅ FriendSync: Friend profile saved locally")
        } else {
            print("⚠️ FriendSync: Could not fetch profile for \(userID), creating placeholder")
            let friend = FriendProfile(
                cloudUserID: userID,
                displayName: "Friend",
                avatarEmoji: "😊",
                connectionStatus: .pending,
                isInitiator: true
            )
            context.insert(friend)
            try context.save()
            print("✅ FriendSync: Placeholder friend profile saved locally")
        }
    }

    // MARK: - Handle Incoming Invite

    /// Handle an invite URL and send friend request
    func handleInviteURL(_ url: URL, context: ModelContext) async throws -> Bool {
        // Parse the URL to extract user ID
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let userIDItem = components.queryItems?.first(where: { $0.name == "id" }),
              let userID = userIDItem.value else {
            return false
        }

        // Don't add ourselves
        guard userID != cloudKitService.currentUserID else {
            return false
        }

        // Check if already connected
        let descriptor = FetchDescriptor<FriendProfile>(
            predicate: #Predicate { $0.cloudUserID == userID }
        )

        let existingFriends = try context.fetch(descriptor)
        if !existingFriends.isEmpty {
            return false // Already connected or pending
        }

        // Send friend request
        try await sendFriendRequest(toUserID: userID, context: context)
        return true
    }
}
