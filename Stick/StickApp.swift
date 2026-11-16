//
//  StickApp.swift
//  Stick
//
//  Created by Kian Jain on 02.02.26.
//

import SwiftUI
import SwiftData
import UserNotifications
import HealthKit
import RevenueCat
import PostHog
import CloudKit
import BackgroundTasks
import WidgetKit

@main
struct StickApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @Environment(\.scenePhase) private var scenePhase
    @State private var sessionStartTime: Date?

    init() {
        Purchases.configure(withAPIKey: "appl_qIcBZJfLcczArlcVCpgXJDcqgIN")

        // Set up HealthKit background delivery
        Task { @MainActor in
            HealthKitManager.shared.setupBackgroundDelivery()
        }

        // Initialize CloudKit early so it's ready for deep links
        Task { @MainActor in
            _ = CloudKitService.shared
        }

        // Debug: Check CloudKit sync status after a delay
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 3_000_000_000) // Wait 3 seconds for sync
            await Self.logCloudKitSyncStatus()
        }
    }

    /// Log CloudKit sync status for debugging
    @MainActor
    private static func logCloudKitSyncStatus() async {
        print("☁️ SwiftData Sync Status:")

        // Check iCloud account
        do {
            let accountStatus = try await CKContainer(identifier: "iCloud.com.kianjain.stick").accountStatus()
            switch accountStatus {
            case .available:
                print("  ✅ iCloud account: Available")
            case .noAccount:
                print("  ❌ iCloud account: No account signed in")
            case .restricted:
                print("  ⚠️ iCloud account: Restricted")
            case .couldNotDetermine:
                print("  ⚠️ iCloud account: Could not determine")
            case .temporarilyUnavailable:
                print("  ⚠️ iCloud account: Temporarily unavailable")
            @unknown default:
                print("  ⚠️ iCloud account: Unknown status")
            }
        } catch {
            print("  ❌ iCloud account check failed: \(error)")
        }
    }

    // Exposed so AppDelegate can access the container for background push syncs
    nonisolated(unsafe) static var sharedContainer: ModelContainer?

    var sharedModelContainer: ModelContainer = {
        let schema = Schema([
            Habit.self,
            Goal.self,
            HabitCompletion.self,
            UserPreferences.self,
            WeeklyWrap.self,
            SkippedDay.self,
            DailyNote.self,
            // Friends feature models
            MyCloudProfile.self,
            FriendProfile.self,
            ReceivedMessage.self,
            SentMessage.self,
            // Shared challenges models
            SharedChallenge.self,
            ChallengeCompletion.self
        ])

        let modelConfiguration = ModelConfiguration(
            schema: schema,
            isStoredInMemoryOnly: false,
            allowsSave: true,
            cloudKitDatabase: .private("iCloud.com.kianjain.stick")  // Enable iCloud sync to private database for backup/restore
        )

        do {
            let container = try ModelContainer(for: schema, configurations: [modelConfiguration])
            print("☁️ SwiftData: ModelContainer created with CloudKit sync enabled")
            StickApp.sharedContainer = container
            return container
        } catch {
            fatalError("Could not create ModelContainer: \(error)")
        }
    }()

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .modelContainer(sharedModelContainer)
        .onChange(of: scenePhase) { oldPhase, newPhase in
            if newPhase == .active {
                // Track daily active user and session start
                sessionStartTime = Date()
                AnalyticsService.shared.trackDailyActiveUser()
                AnalyticsService.shared.trackSessionStarted()
                AnalyticsService.shared.trackDaysSinceInstall()

                // Set up HealthKit background sync callback
                HealthKitManager.shared.onBackgroundUpdate = { [self] in
                    await syncHealthKitHabits()
                    await syncWidgets()
                }

                // Clear badge when app becomes active
                Task {
                    await NotificationManager.shared.clearBadge()
                }

                // User is active — cancel any pending re-engagement nudge
                NotificationManager.cancelReEngagementNotification()

                // Sync HealthKit habits when app becomes active
                Task {
                    await syncHealthKitHabits()
                }

                // Reschedule smart reminders with current incomplete habit list
                Task {
                    let context = sharedModelContainer.mainContext
                    let prefs = (try? context.fetch(FetchDescriptor<UserPreferences>()))?.first
                    guard prefs?.smartRemindersEnabled == true else { return }
                    let frequency = prefs?.smartRemindersFrequency ?? 2
                    let allActive = (try? context.fetch(FetchDescriptor<Habit>(
                        predicate: #Predicate { $0.isActive }
                    ))) ?? []
                    let today = Date()
                    let incomplete = allActive.filter { !$0.isEffectivelyCompleted(for: today) }
                    let habits = incomplete.isEmpty ? allActive : incomplete
                    await NotificationManager.shared.scheduleSmartReminders(habits: habits, frequency: frequency)
                }

                // Sync widgets when app becomes active
                Task {
                    await syncWidgets()
                }

                // Check for completed timers and dismiss Live Activities
                Task {
                    await checkAndCompleteExpiredTimers()
                    await TimerActivityManager.shared.dismissCompletedActivities()
                }
            } else if newPhase == .background {
                if let startTime = sessionStartTime {
                    // Track session end with duration
                    let duration = Int(Date().timeIntervalSince(startTime))
                    AnalyticsService.shared.trackSessionEnded(durationSeconds: duration)
                }
                // Schedule background widget refresh so progress stays current
                AppDelegate.scheduleWidgetRefresh()

                // Schedule re-engagement notification — fires if user doesn't return in 3 days
                Task {
                    let context = sharedModelContainer.mainContext
                    let habits = (try? context.fetch(FetchDescriptor<Habit>(
                        predicate: #Predicate { $0.isActive }
                    ))) ?? []
                    let goals = (try? context.fetch(FetchDescriptor<Goal>())) ?? []
                    let habitNames = habits.prefix(3).map { $0.name }
                    let goalNames = goals.prefix(2).map { $0.name }
                    NotificationManager.scheduleReEngagementNotification(habitNames: Array(habitNames), goalNames: Array(goalNames))
                }
            }
        }
    }

    /// Sync all HealthKit-linked habits
    @MainActor
    private func syncHealthKitHabits() async {
        let context = sharedModelContainer.mainContext

        // Fetch all active habits
        let descriptor = FetchDescriptor<Habit>(
            predicate: #Predicate { $0.isActive }
        )

        do {
            let habits = try context.fetch(descriptor)
            await HealthKitManager.shared.syncAllHealthKitHabits(habits: habits, context: context)
            await HealthKitManager.shared.refreshTodayData()
        } catch {
            print("Failed to fetch habits for HealthKit sync: \(error)")
        }
    }

    /// Sync habit data to home screen widgets
    @MainActor
    private func syncWidgets() async {
        let context = sharedModelContainer.mainContext

        let descriptor = FetchDescriptor<Habit>(
            predicate: #Predicate { $0.isActive }
        )

        do {
            let habits = try context.fetch(descriptor)
            let todayNote = fetchTodayNote(context: context)
            WidgetDataService.shared.syncHabits(habits, todayNote: todayNote)
        } catch {
            print("Failed to sync widgets: \(error)")
        }
    }

    /// Fetch today's daily note (if any) for widget syncing.
    @MainActor
    private func fetchTodayNote(context: ModelContext) -> DailyNote? {
        let start = Calendar.current.startOfDay(for: Date())
        let end = Calendar.current.date(byAdding: .day, value: 1, to: start) ?? start
        let descriptor = FetchDescriptor<DailyNote>(
            predicate: #Predicate { $0.date >= start && $0.date < end }
        )
        return try? context.fetch(descriptor).first
    }

    /// Check if any timer has expired while app was in background and complete the habit
    @MainActor
    private func checkAndCompleteExpiredTimers() async {
        let manager = TimerActivityManager.shared

        // Check if there's an active timer that should have completed
        guard let habitId = manager.activeHabitId else { return }

        let remainingSeconds = manager.getCurrentRemainingSeconds()

        // Timer has expired
        if remainingSeconds <= 0 {
            let context = sharedModelContainer.mainContext

            // Find the habit
            let descriptor = FetchDescriptor<Habit>(
                predicate: #Predicate { $0.id == habitId }
            )

            do {
                if let habit = try context.fetch(descriptor).first {
                    // Check if already completed today
                    let calendar = Calendar.current
                    let alreadyCompleted = habit.safeCompletions.contains { completion in
                        calendar.isDateInToday(completion.completionDate) && completion.source == "timer"
                    }

                    if !alreadyCompleted {
                        // Create completion record
                        let completion = HabitCompletion(
                            habit: habit,
                            count: 1,
                            actualDuration: manager.targetDuration,
                            source: "timer"
                        )
                        context.insert(completion)
                        habit.safeCompletions.append(completion)
                        try context.save()
                        print("Auto-completed timer habit: \(habit.name)")
                    }
                }
            } catch {
                print("Failed to auto-complete timer habit: \(error)")
            }

            // Mark the activity as completed
            await manager.completeActivity()
        }
    }
}

// MARK: - App Delegate

#if os(iOS)
import CloudKit

class AppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {
    static let widgetRefreshTaskID = "com.kianjain.Stick.widgetRefresh"

    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        // Set notification delegate
        UNUserNotificationCenter.current().delegate = self

        // Register for remote notifications (required for CloudKit push)
        application.registerForRemoteNotifications()

        // Register background widget-refresh task
        BGTaskScheduler.shared.register(
            forTaskWithIdentifier: AppDelegate.widgetRefreshTaskID,
            using: nil
        ) { task in
            Task { @MainActor in
                await AppDelegate.runWidgetRefreshTask(task as! BGAppRefreshTask)
            }
        }

        // Initialize PostHog Analytics
        let config = PostHogConfig(
            apiKey: "phc_VNqWId30sjuMob0uqyvog7f6Lrg9v2a9IFyDvBwkW9F",
            host: "https://us.i.posthog.com"
        )
        config.captureScreenViews = true
        config.captureApplicationLifecycleEvents = true
        config.flushAt = 1  // Send events immediately
        config.debug = true // Enable debug logging to console
        PostHogSDK.shared.setup(config)

        // Schedule first background widget refresh
        AppDelegate.scheduleWidgetRefresh()

        return true
    }

    // MARK: - Remote Notifications

    func application(
        _ application: UIApplication,
        didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data
    ) {
        print("📱 Registered for remote notifications")
        // Set up CloudKit subscriptions when we have a device token
        Task { @MainActor in
            if CloudKitService.shared.isAuthenticated {
                try? await CloudKitService.shared.setupSubscriptions()
            }
        }
    }

    func application(
        _ application: UIApplication,
        didFailToRegisterForRemoteNotificationsWithError error: Error
    ) {
        print("📱 Failed to register for remote notifications: \(error)")
    }

    func application(
        _ application: UIApplication,
        didReceiveRemoteNotification userInfo: [AnyHashable: Any],
        fetchCompletionHandler completionHandler: @escaping (UIBackgroundFetchResult) -> Void
    ) {
        print("📬 Received remote notification!")
        if let aps = userInfo["aps"] as? [String: Any] {
            print("📬 APS payload: \(aps)")
            if aps["alert"] != nil {
                print("📬 ✅ Has alert - visible notification")
            } else if aps["content-available"] != nil {
                print("📬 Silent push (content-available)")
            }
        }

        guard let notification = CKNotification(fromRemoteNotificationDictionary: userInfo) else {
            completionHandler(.noData)
            return
        }

        // Await the sync so the OS doesn't cut off our background time before it finishes
        Task { @MainActor in
            await handleCloudKitNotification(notification)
            completionHandler(.newData)
        }
    }

    /// Handle an incoming CloudKit push and run the appropriate sync immediately.
    /// Running the sync here (rather than delegating to a NotificationCenter observer)
    /// ensures data is fetched even when the app is backgrounded and no views are active.
    @MainActor
    private func handleCloudKitNotification(_ notification: CKNotification) async {
        guard notification.notificationType == .query,
              let queryNotification = notification as? CKQueryNotification else { return }

        let subscriptionID = queryNotification.subscriptionID ?? ""
        print("🔔 CloudKit push: \(subscriptionID)")

        // Get a context from the shared container
        guard let container = StickApp.sharedContainer else {
            print("🔔 ⚠️ No model container available for background sync")
            // Still notify UI in case app is foregrounded
            NotificationCenter.default.post(name: .cloudKitDataChanged, object: nil,
                                            userInfo: ["subscriptionID": subscriptionID])
            return
        }
        let context = container.mainContext

        // Sync based on which subscription fired
        if subscriptionID.hasPrefix("challenge-progress-") {
            // Partner marked a challenge day complete → sync then notify (bypass debounce for real-time)
            await ChallengeSyncService.shared.syncChallengesNow(context: context)
            fireChallengeDoneNotification(subscriptionID: subscriptionID, context: context)
        } else if subscriptionID.hasPrefix("challenge-invites-") {
            // New challenge invite → sync challenges and friend connections (bypass debounce)
            try? await FriendSyncService.shared.syncFriendConnections(context: context)
            await ChallengeSyncService.shared.syncChallengesNow(context: context)
        } else if subscriptionID.hasPrefix("messages-") {
            // New message → only sync messages, no debounce
            await FriendSyncService.shared.syncMessagesOnly(context: context)
        } else if subscriptionID.hasPrefix("friend-requests-") || subscriptionID.hasPrefix("friend-accepted-") {
            // Friend request or acceptance → sync friend connections only (bypass debounce)
            try? await FriendSyncService.shared.syncFriendConnections(context: context)
        } else {
            // Unknown subscription → full sync (debounced)
            await FriendSyncService.shared.performInitialSync(context: context)
        }

        // Also signal any active UI observers (e.g. FriendsView when foregrounded)
        NotificationCenter.default.post(name: .cloudKitDataChanged, object: nil,
                                        userInfo: ["subscriptionID": subscriptionID])
    }

    // MARK: - Challenge Done Notification

    /// Look up the partner's display name from the subscriptionID and fire a local notification.
    /// SubscriptionID format: "challenge-progress-{challengeID}-{partnerUserID}"
    private func fireChallengeDoneNotification(subscriptionID: String, context: ModelContext) {
        guard let currentUserID = CloudKitService.shared.currentUserID else { return }

        let prefix = "challenge-progress-"
        let suffix = subscriptionID.dropFirst(prefix.count) // "{challengeID}-{partnerUserID}"

        // Fetch all active challenges and find the one whose subscription ID matches
        let descriptor = FetchDescriptor<SharedChallenge>()
        guard let challenges = try? context.fetch(descriptor) else { return }

        let match = challenges.first { challenge in
            let expectedSuffix = "\(challenge.challengeID)-\(challenge.friendUserID(for: currentUserID))"
            return suffix == expectedSuffix
        }

        let partnerName = match?.friendDisplayName(for: currentUserID) ?? String(localized: "challenge_partner_fallback")
        NotificationManager.scheduleChallengeDoneNotification(partnerName: partnerName)
    }

    // MARK: - Background Widget Refresh

    /// Schedule the next background widget-refresh task.
    /// Call this whenever the app enters background and after each task completes.
    static func scheduleWidgetRefresh() {
        let request = BGAppRefreshTaskRequest(identifier: widgetRefreshTaskID)
        // Earliest begin: 15 minutes from now — iOS decides exact timing
        request.earliestBeginDate = Date(timeIntervalSinceNow: 15 * 60)
        try? BGTaskScheduler.shared.submit(request)
    }

    /// Background task handler: sync widget data from SwiftData and reload timelines.
    @MainActor
    static func runWidgetRefreshTask(_ task: BGAppRefreshTask) async {
        // Schedule the NEXT refresh immediately so the chain continues
        scheduleWidgetRefresh()

        // Expiry handler: mark incomplete if iOS needs the time back
        task.expirationHandler = {
            task.setTaskCompleted(success: false)
        }

        guard let container = StickApp.sharedContainer else {
            task.setTaskCompleted(success: false)
            return
        }

        let context = container.mainContext
        let descriptor = FetchDescriptor<Habit>(predicate: #Predicate { $0.isActive })
        let habits = (try? context.fetch(descriptor)) ?? []
        WidgetDataService.shared.syncHabits(habits)

        task.setTaskCompleted(success: true)
    }

    // MARK: - Local Notifications

    // Handle notification when app is in foreground
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        // Show notification even when app is in foreground
        completionHandler([.banner, .sound, .badge])
    }

    // Handle notification tap
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        let userInfo = response.notification.request.content.userInfo
        let category = response.notification.request.content.categoryIdentifier

        // Handle friend-related notifications
        if category == "FRIEND_REQUEST" || category == "FRIEND_MESSAGE" {
            NotificationCenter.default.post(
                name: .friendNotificationTapped,
                object: nil,
                userInfo: ["category": category]
            )
        } else if let habitIdString = userInfo["habitId"] as? String {
            // Post notification to navigate to habit
            NotificationCenter.default.post(
                name: .habitNotificationTapped,
                object: nil,
                userInfo: ["habitId": habitIdString]
            )
        }

        completionHandler()
    }
}
#else
class AppDelegate: NSObject {
    // Empty delegate for non-iOS platforms
}
#endif

// MARK: - Notification Names

extension Notification.Name {
    static let habitNotificationTapped = Notification.Name("habitNotificationTapped")
    static let friendNotificationTapped = Notification.Name("friendNotificationTapped")
    static let cloudKitDataChanged = Notification.Name("cloudKitDataChanged")
}

// MARK: - ModelContainer Extension

extension ModelContainer {
    /// Convenience initializer for previews and testing
    static var preview: ModelContainer {
        let schema = Schema([
            Habit.self,
            Goal.self,
            HabitCompletion.self,
            UserPreferences.self,
            WeeklyWrap.self,
            SkippedDay.self,
            DailyNote.self,
            // Friends feature models
            MyCloudProfile.self,
            FriendProfile.self,
            ReceivedMessage.self,
            SentMessage.self,
            // Shared challenges models
            SharedChallenge.self,
            ChallengeCompletion.self
        ])

        let configuration = ModelConfiguration(
            schema: schema,
            isStoredInMemoryOnly: true
        )

        do {
            let container = try ModelContainer(for: schema, configurations: [configuration])

            // Add sample data for previews
            Task { @MainActor in
                let context = container.mainContext

                // Create sample goal
                let healthGoal = Goal(name: "Healthy Body", description: "Physical health habits")
                context.insert(healthGoal)

                // Create sample habits
                let waterHabit = Habit(
                    name: "Drink Water",
                    description: "8 glasses per day",
                    color: "#007AFF",
                    emoji: "💧",
                    frequency: .daily,
                    goal: healthGoal
                )
                context.insert(waterHabit)

                let exerciseHabit = Habit(
                    name: "Exercise",
                    description: "30 minutes workout",
                    color: "#FF3B30",
                    emoji: "🏃",
                    frequency: .weekly,
                    scheduledDays: [2, 4, 6], // Mon, Wed, Fri
                    duration: 1800, // 30 minutes
                    goal: healthGoal
                )
                context.insert(exerciseHabit)

                let readHabit = Habit(
                    name: "Read",
                    description: "Read for 20 minutes",
                    color: "#34C759",
                    symbolName: "book.fill",
                    frequency: .daily,
                    duration: 1200 // 20 minutes
                )
                context.insert(readHabit)

                // Create sample preferences
                let preferences = UserPreferences.createDefault()
                context.insert(preferences)
            }

            return container
        } catch {
            fatalError("Could not create preview ModelContainer: \(error)")
        }
    }
}
