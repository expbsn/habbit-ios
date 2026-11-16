//
//  FriendsView.swift
//  Stick
//
//  Main Friends tab view showing friend list, leaderboard, and messages.
//

import SwiftUI
import SwiftData

struct FriendsView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.scenePhase) private var scenePhase
    @Query private var preferences: [UserPreferences]
    @Query(filter: #Predicate<FriendProfile> { $0.connectionStatus == "accepted" },
           sort: \FriendProfile.todayCompletionPercentage,
           order: .reverse) private var acceptedFriends: [FriendProfile]
    @Query(filter: #Predicate<FriendProfile> { $0.connectionStatus == "pending" }) private var pendingFriends: [FriendProfile]
    @Query(sort: \ReceivedMessage.sentDate, order: .reverse) private var messages: [ReceivedMessage]
    @Query private var myProfile: [MyCloudProfile]

    @StateObject private var cloudKitService = CloudKitService.shared
    @StateObject private var friendSyncService = FriendSyncService.shared

    @State private var showingAddFriend = false
    @State private var showingPendingRequests = false
    @State private var showingProfileSetup = false
    @State private var showingEditProfile = false
    @State private var showingLeaderboard = false
    @State private var showingCreateChallenge = false
    @State private var selectedFriend: FriendProfile?
    @State private var selectedMessage: ReceivedMessage?
    @State private var selectedChallenge: SharedChallenge?

    @StateObject private var challengeSyncService = ChallengeSyncService.shared
    @Query private var allChallenges: [SharedChallenge]

    @Query(sort: \SentMessage.sentDate, order: .reverse) private var sentMessages: [SentMessage]


    // Debug mode for testing
    #if DEBUG
    @State private var showingDebugMenu = false
    #endif

    private var accentColor: Color {
        let colorValue = preferences.first?.appAccentColor ?? UserPreferences.adaptiveAccentColor
        if colorValue == UserPreferences.adaptiveAccentColor {
            return Color.primary
        }
        return Color(hex: colorValue)
    }

    private var currentProfile: MyCloudProfile? {
        myProfile.first
    }

    private var pendingIncomingRequests: [FriendProfile] {
        pendingFriends.filter { $0.isPendingIncoming }
    }

    private var unreadMessages: [ReceivedMessage] {
        messages.filter { !$0.isRead }
    }

    var body: some View {
        NavigationStack {
            Group {
                if !cloudKitService.isAuthenticated {
                    notAuthenticatedView
                } else if currentProfile == nil || !(currentProfile?.isComplete ?? false) {
                    profileSetupPrompt
                } else {
                    mainContent
                }
            }
            .dimThemeBackground()
            .navigationTitle(String(localized: "friends_title"))
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showingAddFriend = true
                    } label: {
                        Image(systemName: "person.badge.plus")
                    }
                    .tint(.primary)
                    .disabled(!cloudKitService.isAuthenticated)
                }
            }
            .sheet(isPresented: $showingAddFriend) {
                AddFriendSheet()
            }
            .sheet(isPresented: $showingPendingRequests) {
                PendingRequestsView()
            }
            .sheet(isPresented: $showingProfileSetup) {
                FriendProfileSetupView()
            }
            .sheet(isPresented: $showingEditProfile) {
                EditProfileSheet()
            }
            .sheet(isPresented: $showingLeaderboard) {
                LeaderboardView()
            }
            .sheet(isPresented: $showingCreateChallenge) {
                CreateChallengeSheet()
            }
            .sheet(item: $selectedFriend) { friend in
                FriendChatView(friend: friend)
            }
            .sheet(item: $selectedChallenge) { challenge in
                ChallengeDetailView(challenge: challenge)
            }
            .onAppear {
                Task {
                    await cloudKitService.checkAccountStatus()
                    if cloudKitService.isAuthenticated {
                        await friendSyncService.performInitialSync(context: modelContext)
                    }
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: .cloudKitDataChanged)) { notification in
                // Sync when CloudKit push notification arrives — route to targeted sync based on subscriptionID
                let subscriptionID = notification.userInfo?["subscriptionID"] as? String ?? ""
                Task {
                    if subscriptionID.contains("messages-") {
                        await friendSyncService.syncMessagesOnly(context: modelContext)
                    } else if subscriptionID.contains("challenge-") {
                        await challengeSyncService.syncChallengesNow(context: modelContext)
                    } else if subscriptionID.contains("friend-") {
                        try? await friendSyncService.syncFriendConnections(context: modelContext)
                    } else {
                        await friendSyncService.performInitialSync(context: modelContext)
                    }
                }
            }
            .onChange(of: scenePhase) { _, newPhase in
                if newPhase == .active {
                    Task {
                        // Fast path: messages + today's progress (no 7-day history fetch)
                        await friendSyncService.syncMessagesOnly(context: modelContext)
                        await friendSyncService.syncTodayProgress(context: modelContext)
                        await challengeSyncService.syncChallenges(context: modelContext)
                    }
                }
            }
            // Periodic background poll: keeps friend progress current without manual refresh.
            // CloudKit push covers messages/challenges/requests in real-time; progress
            // records don't have a subscription so we poll every 60s while active.
            .task {
                while !Task.isCancelled {
                    try? await Task.sleep(for: .seconds(60))
                    guard !Task.isCancelled,
                          scenePhase == .active,
                          cloudKitService.isAuthenticated else { continue }
                    await friendSyncService.syncTodayProgress(context: modelContext)
                }
            }
            #if DEBUG
            .sheet(isPresented: $showingDebugMenu) {
                debugMenuSheet
            }
            #endif
        }
    }

    // MARK: - Debug Menu

    #if DEBUG
    private var debugMenuSheet: some View {
        NavigationStack {
            List {
                Section("Test Data") {
                    Button("Setup All Demo Data") {
                        setupDemoData()
                        showingDebugMenu = false
                    }

                    Button("Setup Friends Only") {
                        setupFriendsOnlyData()
                        showingDebugMenu = false
                    }

                    Button("Add Pending Request") {
                        addPendingRequest()
                        showingDebugMenu = false
                    }
                }

                Section("Challenges") {
                    Button("Add Active Challenge") {
                        addDebugActiveChallenge()
                        showingDebugMenu = false
                    }

                    Button("Add Pending Challenge Invite (as receiver)") {
                        addDebugPendingChallengeInvite()
                        showingDebugMenu = false
                    }

                    Button("Clear Challenges", role: .destructive) {
                        clearDebugChallenges()
                        showingDebugMenu = false
                    }
                }

                Section("Clear Data") {
                    Button("Clear Friends Only", role: .destructive) {
                        clearFriendsOnlyData()
                        showingDebugMenu = false
                    }

                    Button("Clear All Data", role: .destructive) {
                        clearAllData()
                        showingDebugMenu = false
                    }
                }

                Section("Debug Info") {
                    LabeledContent("CloudKit Auth", value: cloudKitService.isAuthenticated ? "Yes" : "No")
                    LabeledContent("User ID", value: cloudKitService.currentUserID ?? "None")
                    LabeledContent("Profile Complete", value: currentProfile?.isComplete == true ? "Yes" : "No")
                    LabeledContent("Friends Count", value: "\(acceptedFriends.count)")
                }
            }
            .navigationTitle("Debug Menu")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { showingDebugMenu = false }
                }
            }
        }
    }

    private func setupDemoData() {
        // Clear existing test data first
        clearAllData()

        // Create sample habits with completions
        createSampleHabits()

        // Create 3 friends with fixed IDs so messages link properly
        let sarahID = "demo_sarah"
        let mikeID = "demo_mike"
        let alexID = "demo_alex"

        // Sarah - high performer with quote
        let sarah = FriendProfile(
            cloudUserID: sarahID,
            displayName: "Sarah",
            avatarEmoji: "😊",
            connectionStatus: .accepted,
            isInitiator: true
        )
        sarah.todayCompletionPercentage = 0.92
        sarah.currentStreak = 21
        sarah.weeklyAverageCompletion = 0.87
        sarah.acceptedDate = Calendar.current.date(byAdding: .month, value: -2, to: Date())
        sarah.topHabitName = "Morning Meditation"
        sarah.hoursSpentThisWeek = 4.5
        sarah.motivationalQuote = "Every day is a new opportunity to grow."
        modelContext.insert(sarah)

        // Mike - active runner
        let mike = FriendProfile(
            cloudUserID: mikeID,
            displayName: "Mike",
            avatarEmoji: "🏃",
            connectionStatus: .accepted,
            isInitiator: false
        )
        mike.todayCompletionPercentage = 0.78
        mike.currentStreak = 5
        mike.weeklyAverageCompletion = 0.73
        mike.acceptedDate = Calendar.current.date(byAdding: .weekOfYear, value: -3, to: Date())
        mike.topHabitName = "Running"
        mike.hoursSpentThisWeek = 3.2
        mike.motivationalQuote = "Keep moving forward!"
        modelContext.insert(mike)

        // Alex - reader
        let alex = FriendProfile(
            cloudUserID: alexID,
            displayName: "Alex",
            avatarEmoji: "🎯",
            connectionStatus: .accepted,
            isInitiator: true
        )
        alex.todayCompletionPercentage = 0.65
        alex.currentStreak = 8
        alex.weeklyAverageCompletion = 0.60
        alex.acceptedDate = Calendar.current.date(byAdding: .weekOfYear, value: -1, to: Date())
        alex.topHabitName = "Reading"
        alex.hoursSpentThisWeek = 2.0
        modelContext.insert(alex)

        // Add conversation with Sarah
        let sarahMsg1 = ReceivedMessage(
            senderUserID: sarahID,
            senderDisplayName: "Sarah",
            senderAvatarEmoji: "😊",
            templateID: "custom",
            customMessageText: "Hey! How's your morning routine going?",
            sentDate: Date().addingTimeInterval(-3600 * 48)
        )
        modelContext.insert(sarahMsg1)

        let mySentToSarah1 = SentMessage(
            recipientUserID: sarahID,
            templateID: "custom",
            customMessageText: "Pretty good! Finally hit my 10-day streak",
            sentDate: Date().addingTimeInterval(-3600 * 47)
        )
        modelContext.insert(mySentToSarah1)

        let sarahMsg2 = ReceivedMessage(
            senderUserID: sarahID,
            senderDisplayName: "Sarah",
            senderAvatarEmoji: "😊",
            templateID: "custom",
            customMessageText: "That's awesome! Keep it up 💪",
            sentDate: Date().addingTimeInterval(-3600 * 2)
        )
        modelContext.insert(sarahMsg2)

        // Add conversation with Mike
        let mikeMsg1 = ReceivedMessage(
            senderUserID: mikeID,
            senderDisplayName: "Mike",
            senderAvatarEmoji: "🏃",
            templateID: "custom",
            customMessageText: "Just finished a 5k run!",
            sentDate: Date().addingTimeInterval(-3600 * 5)
        )
        modelContext.insert(mikeMsg1)

        let mySentToMike = SentMessage(
            recipientUserID: mikeID,
            templateID: "custom",
            customMessageText: "Nice! What was your time?",
            sentDate: Date().addingTimeInterval(-3600 * 4)
        )
        modelContext.insert(mySentToMike)

        try? modelContext.save()
    }

    private func addPendingRequest() {
        let friend = FriendProfile(
            cloudUserID: "test_pending_\(UUID().uuidString)",
            displayName: "Jordan",
            avatarEmoji: "🌟",
            connectionStatus: .pending,
            isInitiator: false
        )
        modelContext.insert(friend)
        try? modelContext.save()
    }

    private func addDebugActiveChallenge() {
        let myID = cloudKitService.currentUserID ?? "debug_me"
        let friendID = "demo_sarah"

        let challenge = SharedChallenge(
            challengeID: "debug_active_\(UUID().uuidString)",
            creatorUserID: friendID,
            participantUserID: myID,
            habitName: "Morning Run",
            habitEmoji: "🏃",
            habitColor: "#FF6B35",
            targetDays: 30
        )
        challenge.statusRaw = ChallengeStatus.active.rawValue
        challenge.startDate = Calendar.current.date(byAdding: .day, value: -10, to: Date())
        challenge.endDate = Calendar.current.date(byAdding: .day, value: 19, to: Date())
        challenge.creatorDisplayName = "Sarah"
        challenge.creatorAvatarEmoji = "😊"
        challenge.participantDisplayName = "You"
        challenge.myCompletedDays = 7
        challenge.friendCompletedDays = 8
        challenge.isCollaborative = false
        modelContext.insert(challenge)
        try? modelContext.save()
    }

    private func addDebugPendingChallengeInvite() {
        let myID = cloudKitService.currentUserID ?? "debug_me"
        let friendID = "demo_mike"

        let challenge = SharedChallenge(
            challengeID: "debug_pending_\(UUID().uuidString)",
            creatorUserID: friendID,
            participantUserID: myID,
            habitName: "Read 20 Pages",
            habitEmoji: "📚",
            habitColor: "#5856D6",
            targetDays: 14
        )
        challenge.statusRaw = ChallengeStatus.pending.rawValue
        challenge.creatorDisplayName = "Mike"
        challenge.creatorAvatarEmoji = "🏃"
        challenge.participantDisplayName = "You"
        modelContext.insert(challenge)
        try? modelContext.save()
    }

    private func clearDebugChallenges() {
        let descriptor = FetchDescriptor<SharedChallenge>()
        if let challenges = try? modelContext.fetch(descriptor) {
            for c in challenges { modelContext.delete(c) }
        }
        let progressDescriptor = FetchDescriptor<ChallengeCompletion>()
        if let completions = try? modelContext.fetch(progressDescriptor) {
            for c in completions { modelContext.delete(c) }
        }
        try? modelContext.save()
    }

    private func clearAllData() {
        // Clear friends
        for friend in acceptedFriends {
            modelContext.delete(friend)
        }
        for friend in pendingFriends {
            modelContext.delete(friend)
        }

        // Clear messages
        for message in messages {
            modelContext.delete(message)
        }
        let sentDescriptor = FetchDescriptor<SentMessage>()
        if let sentMessages = try? modelContext.fetch(sentDescriptor) {
            for msg in sentMessages {
                modelContext.delete(msg)
            }
        }

        // Clear habits and completions
        let habitDescriptor = FetchDescriptor<Habit>()
        if let habits = try? modelContext.fetch(habitDescriptor) {
            for habit in habits {
                modelContext.delete(habit)
            }
        }

        // Clear completions (in case any orphaned)
        let completionDescriptor = FetchDescriptor<HabitCompletion>()
        if let completions = try? modelContext.fetch(completionDescriptor) {
            for completion in completions {
                modelContext.delete(completion)
            }
        }

        try? modelContext.save()
    }

    private func clearFriendsOnlyData() {
        // Clear friends only (keep habits)
        for friend in acceptedFriends {
            modelContext.delete(friend)
        }
        for friend in pendingFriends {
            modelContext.delete(friend)
        }

        // Clear messages
        for message in messages {
            modelContext.delete(message)
        }
        let sentDescriptor = FetchDescriptor<SentMessage>()
        if let sentMessages = try? modelContext.fetch(sentDescriptor) {
            for msg in sentMessages {
                modelContext.delete(msg)
            }
        }

        try? modelContext.save()
    }

    private func setupFriendsOnlyData() {
        // Clear existing friends data first (keep habits)
        clearFriendsOnlyData()

        // Create 3 friends with fixed IDs so messages link properly
        let sarahID = "demo_sarah"
        let mikeID = "demo_mike"
        let alexID = "demo_alex"

        // Sarah - high performer with quote
        let sarah = FriendProfile(
            cloudUserID: sarahID,
            displayName: "Sarah",
            avatarEmoji: "😊",
            connectionStatus: .accepted,
            isInitiator: true
        )
        sarah.todayCompletionPercentage = 0.92
        sarah.currentStreak = 21
        sarah.weeklyAverageCompletion = 0.87
        sarah.acceptedDate = Calendar.current.date(byAdding: .month, value: -2, to: Date())
        sarah.topHabitName = "Morning Meditation"
        sarah.hoursSpentThisWeek = 4.5
        sarah.motivationalQuote = "Every day is a new opportunity to grow."
        modelContext.insert(sarah)

        // Mike - active runner
        let mike = FriendProfile(
            cloudUserID: mikeID,
            displayName: "Mike",
            avatarEmoji: "🏃",
            connectionStatus: .accepted,
            isInitiator: false
        )
        mike.todayCompletionPercentage = 0.78
        mike.currentStreak = 5
        mike.weeklyAverageCompletion = 0.73
        mike.acceptedDate = Calendar.current.date(byAdding: .weekOfYear, value: -3, to: Date())
        mike.topHabitName = "Running"
        mike.hoursSpentThisWeek = 3.2
        mike.motivationalQuote = "Keep moving forward!"
        modelContext.insert(mike)

        // Alex - reader
        let alex = FriendProfile(
            cloudUserID: alexID,
            displayName: "Alex",
            avatarEmoji: "🎯",
            connectionStatus: .accepted,
            isInitiator: true
        )
        alex.todayCompletionPercentage = 0.65
        alex.currentStreak = 8
        alex.weeklyAverageCompletion = 0.60
        alex.acceptedDate = Calendar.current.date(byAdding: .weekOfYear, value: -1, to: Date())
        alex.topHabitName = "Reading"
        alex.hoursSpentThisWeek = 2.0
        modelContext.insert(alex)

        // Add conversation with Sarah
        let sarahMsg1 = ReceivedMessage(
            senderUserID: sarahID,
            senderDisplayName: "Sarah",
            senderAvatarEmoji: "😊",
            templateID: "custom",
            customMessageText: "Hey! How's your morning routine going?",
            sentDate: Date().addingTimeInterval(-3600 * 48)
        )
        modelContext.insert(sarahMsg1)

        let mySentToSarah1 = SentMessage(
            recipientUserID: sarahID,
            templateID: "custom",
            customMessageText: "Pretty good! Finally hit my 10-day streak",
            sentDate: Date().addingTimeInterval(-3600 * 47)
        )
        modelContext.insert(mySentToSarah1)

        let sarahMsg2 = ReceivedMessage(
            senderUserID: sarahID,
            senderDisplayName: "Sarah",
            senderAvatarEmoji: "😊",
            templateID: "custom",
            customMessageText: "That's awesome! Keep it up 💪",
            sentDate: Date().addingTimeInterval(-3600 * 2)
        )
        modelContext.insert(sarahMsg2)

        // Add conversation with Mike
        let mikeMsg1 = ReceivedMessage(
            senderUserID: mikeID,
            senderDisplayName: "Mike",
            senderAvatarEmoji: "🏃",
            templateID: "custom",
            customMessageText: "Just finished a 5k run!",
            sentDate: Date().addingTimeInterval(-3600 * 5)
        )
        modelContext.insert(mikeMsg1)

        let mySentToMike = SentMessage(
            recipientUserID: mikeID,
            templateID: "custom",
            customMessageText: "Nice! What was your time?",
            sentDate: Date().addingTimeInterval(-3600 * 4)
        )
        modelContext.insert(mySentToMike)

        try? modelContext.save()
    }

    private func createSampleHabits() {
        let calendar = Calendar.current

        // Clear existing habits
        let habitDescriptor = FetchDescriptor<Habit>()
        if let existingHabits = try? modelContext.fetch(habitDescriptor) {
            for habit in existingHabits {
                modelContext.delete(habit)
            }
        }

        // 1. Morning Meditation (timer-based, 10 min)
        let meditation = Habit(
            name: "Morning Meditation",
            description: "Start the day with mindfulness",
            color: "#5856D6",
            emoji: "🧘",
            frequency: .daily,
            duration: 600 // 10 minutes
        )
        meditation.createdDate = calendar.date(byAdding: .day, value: -30, to: Date()) ?? Date()
        modelContext.insert(meditation)

        // Add completions for past 12 days (streak)
        for dayOffset in 0..<12 {
            if let date = calendar.date(byAdding: .day, value: -dayOffset, to: Date()) {
                let completion = HabitCompletion(
                    habit: meditation,
                    completionDate: date,
                    actualDuration: 600,
                    source: "timer"
                )
                modelContext.insert(completion)
            }
        }

        // 2. Read 30 Minutes (timer-based)
        let reading = Habit(
            name: "Read 30 Minutes",
            description: "Daily reading habit",
            color: "#FF9500",
            emoji: "📚",
            frequency: .daily,
            duration: 1800 // 30 minutes
        )
        reading.createdDate = calendar.date(byAdding: .day, value: -20, to: Date()) ?? Date()
        modelContext.insert(reading)

        // Add completions (missed some days)
        for dayOffset in [0, 1, 2, 4, 5, 7, 8, 9] {
            if let date = calendar.date(byAdding: .day, value: -dayOffset, to: Date()) {
                let completion = HabitCompletion(
                    habit: reading,
                    completionDate: date,
                    actualDuration: 1800,
                    source: "timer"
                )
                modelContext.insert(completion)
            }
        }

        // 3. Exercise (simple daily)
        let exercise = Habit(
            name: "Exercise",
            description: "Stay active every day",
            color: "#34C759",
            emoji: "💪",
            frequency: .daily
        )
        exercise.createdDate = calendar.date(byAdding: .day, value: -14, to: Date()) ?? Date()
        modelContext.insert(exercise)

        // Add completions for past 7 days
        for dayOffset in 0..<7 {
            if let date = calendar.date(byAdding: .day, value: -dayOffset, to: Date()) {
                let completion = HabitCompletion(
                    habit: exercise,
                    completionDate: date,
                    source: "manual"
                )
                modelContext.insert(completion)
            }
        }

        // 4. Drink Water (count-based)
        let water = Habit(
            name: "Drink Water",
            description: "8 glasses a day",
            color: "#5AC8FA",
            emoji: "💧",
            frequency: .daily,
            targetCount: 8
        )
        water.createdDate = calendar.date(byAdding: .day, value: -10, to: Date()) ?? Date()
        modelContext.insert(water)

        // Add completions
        for dayOffset in 0..<5 {
            if let date = calendar.date(byAdding: .day, value: -dayOffset, to: Date()) {
                let completion = HabitCompletion(
                    habit: water,
                    completionDate: date,
                    count: dayOffset == 0 ? 6 : 8, // Today: 6/8, others: complete
                    source: "manual"
                )
                modelContext.insert(completion)
            }
        }

        // 5. Journal (simple daily)
        let journal = Habit(
            name: "Journal",
            description: "Reflect on the day",
            color: "#FF2D55",
            emoji: "✍️",
            frequency: .daily
        )
        journal.createdDate = calendar.date(byAdding: .day, value: -7, to: Date()) ?? Date()
        modelContext.insert(journal)

        // Add some completions
        for dayOffset in [1, 2, 3, 5, 6] {
            if let date = calendar.date(byAdding: .day, value: -dayOffset, to: Date()) {
                let completion = HabitCompletion(
                    habit: journal,
                    completionDate: date,
                    source: "manual"
                )
                modelContext.insert(completion)
            }
        }

        // 6. Learn Spanish (weekly - specific days: Mon, Wed, Fri)
        let spanish = Habit(
            name: "Learn Spanish",
            description: "Practice 15 minutes",
            color: "#AF52DE",
            emoji: "🇪🇸",
            frequency: .weekly,
            scheduledDays: [2, 4, 6], // Mon, Wed, Fri
            duration: 900 // 15 minutes
        )
        spanish.createdDate = calendar.date(byAdding: .day, value: -21, to: Date()) ?? Date()
        modelContext.insert(spanish)

        // Add some completions for scheduled days
        for dayOffset in 0..<21 {
            if let date = calendar.date(byAdding: .day, value: -dayOffset, to: Date()) {
                let weekday = calendar.component(.weekday, from: date)
                if [2, 4, 6].contains(weekday) && dayOffset % 2 == 0 { // Complete ~half
                    let completion = HabitCompletion(
                        habit: spanish,
                        completionDate: date,
                        actualDuration: 900,
                        source: "timer"
                    )
                    modelContext.insert(completion)
                }
            }
        }

        try? modelContext.save()
    }
    #endif

    // MARK: - Not Authenticated View

    private var notAuthenticatedView: some View {
        ContentUnavailableView {
            Label(String(localized: "friends_icloud_required"), systemImage: "icloud.slash")
        } description: {
            Text(String(localized: "friends_icloud_description"))
        } actions: {
            Button(String(localized: "friends_open_settings")) {
                if let url = URL(string: UIApplication.openSettingsURLString) {
                    UIApplication.shared.open(url)
                }
            }
            .buttonStyle(.borderedProminent)
        }
    }

    // MARK: - Profile Setup Prompt

    private var profileSetupPrompt: some View {
        ContentUnavailableView {
            Label(String(localized: "friends_setup_profile"), systemImage: "person.crop.circle.badge.plus")
        } description: {
            Text(String(localized: "friends_setup_description"))
        } actions: {
            Button {
                showingProfileSetup = true
            } label: {
                Text(String(localized: "friends_create_profile"))
                    .fontWeight(.semibold)
            }
            .buttonStyle(.borderless)
        }
    }

    // MARK: - Main Content

    private var mainContent: some View {
        List {
            // My Progress Section
            myProgressSection

            // Pending Requests Banner
            if !pendingIncomingRequests.isEmpty {
                pendingRequestsBanner
            }

            // Leaderboard Section
            leaderboardSection

            // Challenges Section
            SharedChallengesSection(
                accentColor: accentColor,
                showingCreateChallenge: $showingCreateChallenge,
                selectedChallenge: $selectedChallenge
            )

            // Messages Section
            if !latestMessagesPerFriend.isEmpty {
                messagesSection
            }

            // Friends List Section
            friendsListSection
        }
        .listStyle(.insetGrouped)
    }

    // MARK: - My Progress Section

    private var myProgressSection: some View {
        Section {
            Button {
                showingEditProfile = true
            } label: {
                HStack(spacing: 16) {
                    // Avatar
                    Text(currentProfile?.avatarEmoji ?? "😊")
                        .font(.system(size: 40))
                        .frame(width: 60, height: 60)
                        .background(accentColor.opacity(0.15))
                        .clipShape(Circle())

                    VStack(alignment: .leading, spacing: 4) {
                        Text(currentProfile?.displayName ?? "You")
                            .font(.headline)
                            .foregroundStyle(.primary)

                        Text(String(localized: "friends_your_progress"))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    Spacer()

                    // Today's progress
                    VStack(alignment: .trailing, spacing: 4) {
                        Text("\(Int(todayProgress * 100))%")
                            .font(.title2.bold())
                            .foregroundStyle(todayProgress >= 1.0 ? .green : .primary)

                        HStack(spacing: 4) {
                            Image(systemName: "flame.fill")
                                .foregroundStyle(.orange)
                            Text("\(currentStreak)")
                                .font(.caption.bold())
                                .foregroundStyle(.orange)
                        }
                    }
                }
                .padding(.vertical, 4)
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: - Pending Requests Banner

    private var pendingRequestsBanner: some View {
        Section {
            Button {
                showingPendingRequests = true
            } label: {
                HStack {
                    Image(systemName: "person.fill.checkmark")
                        .foregroundStyle(.secondary)

                    Text(String(format: String(localized: "friends_pending_requests"), pendingIncomingRequests.count))
                        .foregroundStyle(.primary)

                    Spacer()

                    Image(systemName: "chevron.right")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: - Leaderboard Section

    private var leaderboardSection: some View {
        Section {
            Button {
                showingLeaderboard = true
            } label: {
                HStack {
                    Image(systemName: "trophy.fill")
                        .foregroundStyle(.yellow)

                    Text(String(localized: "friends_weekly_leaderboard"))
                        .foregroundStyle(.primary)

                    Spacer()

                    // Top 3 preview
                    if !acceptedFriends.isEmpty {
                        HStack(spacing: -8) {
                            ForEach(Array(acceptedFriends.prefix(3).enumerated()), id: \.element.id) { _, friend in
                                Text(friend.avatarEmoji)
                                    .font(.caption)
                                    .frame(width: 24, height: 24)
                                    .background(Color(.systemGray5))
                                    .clipShape(Circle())
                                    .overlay(
                                        Circle()
                                            .stroke(Color(.systemBackground), lineWidth: 2)
                                    )
                            }
                        }
                    }

                    Image(systemName: "chevron.right")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: - Friends List Section

    private var friendsListSection: some View {
        Section {
            if acceptedFriends.isEmpty {
                emptyFriendsView
            } else {
                ForEach(acceptedFriends) { friend in
                    FriendRowView(friend: friend, accentColor: accentColor)
                        .contentShape(Rectangle())
                        .onTapGesture {
                            selectedFriend = friend
                        }
                }
            }
        } header: {
            HStack {
                Text(String(localized: "friends_section_title"))
                Spacer()
                Text("\(acceptedFriends.count)")
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var emptyFriendsView: some View {
        VStack(spacing: 12) {
            Image(systemName: "person.2")
                .font(.system(size: 40))
                .foregroundStyle(.secondary)

            Text(String(localized: "friends_no_friends_yet"))
                .font(.headline)

            Text(String(localized: "friends_add_friends_description"))
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            Button {
                showingAddFriend = true
            } label: {
                Text(String(localized: "friends_add_friend"))
                    .fontWeight(.semibold)
            }
            .buttonStyle(.borderless)
            .padding(.top, 8)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 24)
    }


    // MARK: - Messages Section

    /// Unified message type for combining sent and received messages
    struct ChatPreviewMessage: Identifiable {
        let id: String
        let friendUserID: String
        let friendDisplayName: String
        let friendAvatarEmoji: String
        let messageText: String
        let sentDate: Date
        let isFromMe: Bool
        let isRead: Bool

        var relativeTime: String {
            let formatter = RelativeDateTimeFormatter()
            formatter.unitsStyle = .abbreviated
            return formatter.localizedString(for: sentDate, relativeTo: Date())
        }
    }

    /// Get the latest message per friend conversation (sent or received)
    private var latestMessagesPerFriend: [ChatPreviewMessage] {
        var latestByFriend: [String: ChatPreviewMessage] = [:]

        // Process received messages
        for message in messages {
            let friendID = message.senderUserID
            let preview = ChatPreviewMessage(
                id: "received_\(friendID)_\(message.sentDate.timeIntervalSince1970)",
                friendUserID: friendID,
                friendDisplayName: message.senderDisplayName,
                friendAvatarEmoji: message.senderAvatarEmoji,
                messageText: message.displayText,
                sentDate: message.sentDate,
                isFromMe: false,
                isRead: message.isRead
            )

            if let existing = latestByFriend[friendID] {
                if preview.sentDate > existing.sentDate {
                    latestByFriend[friendID] = preview
                }
            } else {
                latestByFriend[friendID] = preview
            }
        }

        // Process sent messages
        for message in sentMessages {
            let friendID = message.recipientUserID

            // Find friend info for this recipient
            let friend = acceptedFriends.first { $0.cloudUserID == friendID }
            let friendName = friend?.displayName ?? "Friend"
            let friendEmoji = friend?.avatarEmoji ?? "😊"

            let preview = ChatPreviewMessage(
                id: "sent_\(friendID)_\(message.sentDate.timeIntervalSince1970)",
                friendUserID: friendID,
                friendDisplayName: friendName,
                friendAvatarEmoji: friendEmoji,
                messageText: message.displayText,
                sentDate: message.sentDate,
                isFromMe: true,
                isRead: true // Sent messages are always "read"
            )

            if let existing = latestByFriend[friendID] {
                if preview.sentDate > existing.sentDate {
                    latestByFriend[friendID] = preview
                }
            } else {
                latestByFriend[friendID] = preview
            }
        }

        // Sort by date (newest first) and return
        return latestByFriend.values.sorted { $0.sentDate > $1.sentDate }
    }

    /// Legacy property for backward compatibility
    private var latestMessagesPerSender: [ReceivedMessage] {
        var seenSenders: Set<String> = []
        var result: [ReceivedMessage] = []

        // Messages are already sorted by date (newest first from @Query)
        for message in messages {
            if !seenSenders.contains(message.senderUserID) {
                seenSenders.insert(message.senderUserID)
                result.append(message)
            }
        }
        return result
    }

    private var messagesSection: some View {
        Section {
            ForEach(latestMessagesPerFriend) { preview in
                ChatPreviewRowView(preview: preview, accentColor: accentColor)
                    .contentShape(Rectangle())
                    .onTapGesture {
                        // Find the friend and open chat
                        if let friend = acceptedFriends.first(where: { $0.cloudUserID == preview.friendUserID }) {
                            selectedFriend = friend
                        }
                        // Mark received messages as read
                        if !preview.isFromMe {
                            if let receivedMessage = messages.first(where: { $0.senderUserID == preview.friendUserID && $0.sentDate == preview.sentDate }) {
                                Task {
                                    await friendSyncService.markMessageAsRead(receivedMessage, context: modelContext)
                                }
                            }
                        }
                    }
            }
        } header: {
            HStack {
                Text(String(localized: "friends_messages"))
                Spacer()
                if !unreadMessages.isEmpty {
                    Text("\(unreadMessages.count) \(String(localized: "friends_new"))")
                        .foregroundStyle(Color.primary)
                }
            }
        }
    }

    // MARK: - Computed Properties

    @Query private var habits: [Habit]
    @Query private var skippedDays: [SkippedDay]

    private var activeHabits: [Habit] {
        habits.filter { $0.isActive }
    }

    private var skippedDateSet: Set<Date> {
        Set(skippedDays.map { Calendar.current.startOfDay(for: $0.date) })
    }

    private var isTodaySkipped: Bool {
        let today = Calendar.current.startOfDay(for: Date())
        return skippedDateSet.contains(today)
    }

    private var todayProgress: Double {
        // If today is skipped, show 0% progress
        if isTodaySkipped {
            return 0.0
        }
        // If no habits at all, show 0%
        if habits.isEmpty {
            return 0.0
        }
        // Use ProgressTracker - returns -1 if no habits scheduled for today
        let progress = ProgressTracker.progress(for: Date(), habits: activeHabits)
        // If no habits scheduled for today (but user has habits), show as 100%
        return progress < 0 ? 1.0 : progress
    }

    private var currentStreak: Int {
        let threshold = preferences.first?.streakThreshold ?? 1.0
        return ProgressTracker.calculateStreak(habits: activeHabits, skippedDates: skippedDateSet, threshold: threshold)
    }
}

// MARK: - Friend Row View

struct FriendRowView: View {
    let friend: FriendProfile
    let accentColor: Color

    var body: some View {
        HStack(spacing: 12) {
            // Avatar with progress indicator
            ZStack(alignment: .bottomTrailing) {
                Text(friend.avatarEmoji)
                    .font(.title2)
                    .frame(width: 44, height: 44)
                    .background(Color(.systemGray5))
                    .clipShape(Circle())

                Text(friend.progressIndicator)
                    .font(.caption2)
                    .offset(x: 4, y: 4)
            }

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 4) {
                    if let badge = friend.rankBadge {
                        Text(badge)
                            .font(.caption)
                    }
                    Text(friend.displayName)
                        .font(.body.weight(.medium))
                }

                Text(String(localized: "friends_streak_count", defaultValue: "\(friend.currentStreak) day streak"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            // Today's completion
            Text(friend.formattedTodayCompletion)
                .font(.headline)
                .foregroundStyle(friend.todayCompletionPercentage >= 1.0 ? .green : .primary)
        }
        .padding(.vertical, 4)
    }
}

// MARK: - Chat Preview Row View

struct ChatPreviewRowView: View {
    let preview: FriendsView.ChatPreviewMessage
    let accentColor: Color

    var body: some View {
        HStack(spacing: 12) {
            Text(preview.friendAvatarEmoji)
                .font(.title3)
                .frame(width: 36, height: 36)
                .background(Color(.systemGray5))
                .clipShape(Circle())

            VStack(alignment: .leading, spacing: 2) {
                HStack {
                    Text(preview.friendDisplayName)
                        .font(.subheadline.weight(.medium))

                    if !preview.isRead && !preview.isFromMe {
                        Circle()
                            .fill(.blue)
                            .frame(width: 8, height: 8)
                    }
                }

                HStack(spacing: 4) {
                    if preview.isFromMe {
                        Text(String(localized: "friends_you_prefix"))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Text(preview.messageText)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }

            Spacer()

            Text(preview.relativeTime)
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
        .padding(.vertical, 2)
    }
}

// MARK: - Message Row View (Legacy)

struct MessageRowView: View {
    let message: ReceivedMessage

    var body: some View {
        HStack(spacing: 12) {
            Text(message.senderAvatarEmoji)
                .font(.title3)
                .frame(width: 36, height: 36)
                .background(Color(.systemGray5))
                .clipShape(Circle())

            VStack(alignment: .leading, spacing: 2) {
                HStack {
                    Text(message.senderDisplayName)
                        .font(.subheadline.weight(.medium))

                    if !message.isRead {
                        Circle()
                            .fill(.blue)
                            .frame(width: 8, height: 8)
                    }
                }

                Text(message.displayText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Text(message.relativeTime)
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
        .padding(.vertical, 2)
    }
}

// MARK: - Preview

#Preview {
    FriendsView()
        .modelContainer(.preview)
}
