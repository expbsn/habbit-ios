//
//  SettingsView.swift
//  Stick
//
//  Created by Kian Jain on 02.02.26.
//

import SwiftUI
import SwiftData
import UserNotifications
import RevenueCat
#if canImport(UIKit)
import UIKit
#endif

struct SettingsView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.colorScheme) private var colorScheme

    @Query(sort: \Goal.createdDate, order: .forward) private var goals: [Goal]
    @Query(filter: #Predicate<Habit> { !$0.isActive }) private var archivedHabits: [Habit]
    @Query private var cloudProfiles: [MyCloudProfile]

    @ObservedObject private var subscriptionService = SubscriptionService.shared
    @ObservedObject private var healthKitManager = HealthKitManager.shared
    @State private var showingPaywall = false
    @State private var preferences: UserPreferences?
    @State private var showingResetConfirmation = false
    @State private var showingExportSheet = false
    @State private var goalToDelete: Goal?
    @State private var showingGoalDeleteConfirmation = false
    @State private var showingEditProfile = false

    // Local state for bindings
    @State private var userName: String = ""
    @State private var motivationQuote: String = ""
    @State private var notificationsEnabled: Bool = true
    @State private var friendMessageNotifications: Bool = true
    @State private var friendCompletionNotifications: Bool = true
    @State private var friendRequestNotifications: Bool = true
    @State private var hapticsEnabled: Bool = true
    @State private var selectedTheme: AppTheme = .system
    @State private var selectedAccentColor: String = UserPreferences.adaptiveAccentColor
    @State private var firstDayOfWeek: Int = 1
    @State private var defaultNotificationTime: Date = Date()
    @State private var streakThreshold: Double = 1.0
    @State private var smartRemindersEnabled: Bool = false
    @State private var smartRemindersFrequency: Int = 2
    @FocusState private var isFocused: Bool
    
    /// Accent color from local state
    private var accentColor: Color {
        if selectedAccentColor == UserPreferences.adaptiveAccentColor {
            return Color.primary
        }
        return Color(hex: selectedAccentColor)
    }

    var body: some View {
        NavigationStack {
            Form {
                // Profile Section
                profileSection

                // Subscription Section
                subscriptionSection

                // Appearance Section
                appearanceSection

                // Streak Section
                streakSection

                // Health Section
                healthSection

                // Goals Section
                goalsSection

                // Notifications Section
                notificationsSection

                // Friend Notifications Section
                friendNotificationsSection

                // Smart Reminders Section
                smartRemindersSection

                // Haptics Section
                hapticsSection

                // Data Section
                dataSection

                // About Section
                aboutSection

                // Debug Section (disabled — re-enable by uncommenting)
                // #if DEBUG
                // debugSection
                // #endif
            }
            .dimThemeBackground()
            .tint(Color(red: 0.4, green: 0.4, blue: 0.45))
            .navigationTitle(String(localized: "settings_title"))
            .scrollDismissesKeyboard(.immediately)
            .onAppear {
                loadPreferences()
            }
            .onChange(of: cloudProfiles.first?.displayName) { _, newName in
                // If CloudKit data arrives after view loaded and local name is empty, sync it
                if userName.isEmpty, let name = newName, !name.isEmpty {
                    userName = name
                    preferences?.userName = name
                    savePreferences()
                }
            }
            .onChange(of: cloudProfiles.first?.motivationalQuote) { _, newQuote in
                // If CloudKit data arrives after view loaded and local quote is empty, sync it
                if motivationQuote.isEmpty, let quote = newQuote, !quote.isEmpty {
                    motivationQuote = quote
                    preferences?.motivationQuote = quote
                    savePreferences()
                }
            }
            .sheet(isPresented: $showingPaywall) {
                PaywallView(source: "settings")
            }
            .sheet(isPresented: $showingEditProfile) {
                EditProfileSheet()
            }
            .onChange(of: showingEditProfile) { _, isShowing in
                if !isShowing {
                    // Reload data when edit sheet is dismissed
                    loadPreferences()
                }
            }
        }
    }

    // MARK: - Profile Section

    private var profileSection: some View {
        Section {
            Button {
                showingEditProfile = true
            } label: {
                HStack {
                    // Avatar emoji from cloud profile, fallback to initials
                    if let emoji = cloudProfiles.first?.avatarEmoji, !emoji.isEmpty {
                        Text(emoji)
                            .font(.system(size: 32))
                            .frame(width: 60, height: 60)
                            .background(accentColor.opacity(0.15))
                            .clipShape(Circle())
                    } else {
                        ZStack {
                            Circle()
                                .fill(accentColor.gradient)
                                .frame(width: 60, height: 60)

                            Text(userInitials)
                                .font(.title2.bold())
                                .foregroundStyle(selectedAccentColor == UserPreferences.adaptiveAccentColor ? Color(.systemBackground) : .white)
                        }
                    }

                    VStack(alignment: .leading, spacing: 4) {
                        Text(userName.isEmpty ? String(localized: "settings_your_name") : userName)
                            .font(.headline)
                            .foregroundStyle(userName.isEmpty ? .secondary : .primary)

                        if let username = cloudProfiles.first?.username, !username.isEmpty {
                            Text("@\(username)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        } else {
                            Text(String(localized: "settings_user"))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(.leading, 8)

                    Spacer()

                    Image(systemName: "chevron.right")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .buttonStyle(.plain)

            if !motivationQuote.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    Text(String(localized: "settings_motivation_quote"))
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    Text(motivationQuote)
                        .font(.subheadline)
                        .foregroundStyle(.primary)
                }
            }
        } header: {
            Text(String(localized: "settings_profile"))
        }
    }

    private var userInitials: String {
        let name = userName.isEmpty ? "User" : userName
        let components = name.split(separator: " ")
        if components.count >= 2 {
            return "\(components[0].prefix(1))\(components[1].prefix(1))".uppercased()
        }
        return String(name.prefix(2)).uppercased()
    }

    // MARK: - Subscription Section

    private var subscriptionSection: some View {
        Section {
            if subscriptionService.isSubscribed {
                // Subscribed state
                HStack(spacing: 16) {
                    ZStack {
                        Circle()
                            .fill(Color.yellow.opacity(0.2))
                            .frame(width: 50, height: 50)

                        Image(systemName: "crown.fill")
                            .font(.title2)
                            .foregroundStyle(.yellow)
                    }

                    VStack(alignment: .leading, spacing: 4) {
                        Text(String(localized: "settings_pro_active"))
                            .font(.headline)

                        Text(String(localized: "settings_pro_thanks"))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    Spacer()
                }
                .padding(.vertical, 4)

                Button {
                    openSubscriptionManagement()
                } label: {
                    Label(String(localized: "settings_manage_subscription"), systemImage: "gear")
                }
                .foregroundStyle(.primary)
            } else {
                // Not subscribed - show upgrade prompt
                Button {
                    showingPaywall = true
                } label: {
                    HStack(spacing: 16) {
                        ZStack {
                            Circle()
                                .fill(Color.yellow.opacity(0.2))
                                .frame(width: 50, height: 50)

                            Image(systemName: "crown.fill")
                                .font(.title2)
                                .foregroundStyle(.yellow)
                        }

                        VStack(alignment: .leading, spacing: 4) {
                            Text(String(localized: "settings_upgrade_pro"))
                                .font(.headline)
                                .foregroundStyle(.primary)

                            Text(String(localized: "settings_upgrade_subtitle"))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }

                        Spacer()

                        Image(systemName: "chevron.right")
                            .font(.body.weight(.semibold))
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 4)
                }
                .buttonStyle(.plain)

                Button {
                    Task {
                        await subscriptionService.restorePurchases()
                    }
                } label: {
                    Label(String(localized: "settings_restore_purchases"), systemImage: "arrow.clockwise")
                }
                .foregroundStyle(.primary)
            }
        } header: {
            Text(String(localized: "settings_subscription"))
        }
    }

    private func openSubscriptionManagement() {
        #if canImport(UIKit)
        if let url = URL(string: "https://apps.apple.com/account/subscriptions") {
            UIApplication.shared.open(url)
        }
        #endif
    }

    // MARK: - Appearance Section

    private var appearanceSection: some View {
        Section {
            // Theme picker
            Picker(String(localized: "settings_theme"), selection: $selectedTheme) {
                ForEach(AppTheme.allCases, id: \.self) { theme in
                    Label(theme.localizedName, systemImage: theme.icon)
                        .tag(theme)
                }
            }
            .tint(.primary)
            .onChange(of: selectedTheme) { _, newValue in
                preferences?.theme = newValue
                savePreferences()
            }

            // Accent color picker
            NavigationLink {
                AccentColorPicker(selectedColor: $selectedAccentColor) {
                    preferences?.appAccentColor = selectedAccentColor
                    savePreferences()
                }
            } label: {
                HStack {
                    Text(String(localized: "settings_accent_color"))
                    Spacer()
                    Circle()
                        .fill(accentColor)
                        .frame(width: 24, height: 24)
                }
            }
        } header: {
            Text(String(localized: "settings_appearance"))
        }
    }

    // MARK: - Goals Section

    private var goalsSection: some View {
        Section {
            if goals.isEmpty {
                Text(String(localized: "settings_no_goals"))
                    .foregroundStyle(.secondary)
            } else {
                ForEach(goals) { goal in
                    NavigationLink {
                        GoalEditView(goal: goal)
                    } label: {
                        HStack {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(goal.name)
                                    .font(.body)

                                let habitCount = goal.safeHabits.count
                                Text(String(format: habitCount == 1 ? String(localized: "settings_habit_count") : String(localized: "settings_habits_count"), habitCount))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }

                            Spacer()
                        }
                    }
                    .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                        Button {
                            goalToDelete = goal
                            showingGoalDeleteConfirmation = true
                        } label: {
                            Image(systemName: "trash")
                        }
                        .tint(.red)
                    }
                }
            }
        } header: {
            Text(String(localized: "settings_goals"))
        } footer: {
            Text(String(localized: "settings_goals_footer"))
        }
        .confirmationDialog(
            String(localized: "settings_delete_goal"),
            isPresented: $showingGoalDeleteConfirmation,
            titleVisibility: .visible
        ) {
            Button(String(localized: "settings_delete"), role: .destructive) {
                if let goal = goalToDelete {
                    modelContext.delete(goal)
                    try? modelContext.save()
                }
                goalToDelete = nil
            }
            Button(String(localized: "settings_cancel"), role: .cancel) {
                goalToDelete = nil
            }
        } message: {
            if let goal = goalToDelete {
                Text(String(format: String(localized: "settings_delete_goal_message"), goal.name))
            }
        }
    }

    // MARK: - Notifications Section

    @ObservedObject private var notificationManager = NotificationManager.shared

    private var notificationsSection: some View {
        Section {
            Toggle(String(localized: "settings_enable_notifications"), isOn: $notificationsEnabled)
                .onChange(of: notificationsEnabled) { _, newValue in
                    preferences?.notificationsEnabled = newValue
                    savePreferences()
                    if newValue {
                        Task {
                            let granted = await notificationManager.requestAuthorization()
                            if !granted {
                                await MainActor.run {
                                    notificationsEnabled = false
                                    preferences?.notificationsEnabled = false
                                    savePreferences()
                                }
                            }
                        }
                    }
                }

            if notificationsEnabled {
                // Authorization status
                HStack {
                    Text(String(localized: "settings_permission_status"))
                    Spacer()
                    Text(authorizationStatusText)
                        .foregroundStyle(authorizationStatusColor)
                }

                DatePicker(
                    String(localized: "settings_default_reminder"),
                    selection: $defaultNotificationTime,
                    displayedComponents: .hourAndMinute
                )
                .tint(.primary)
                .onChange(of: defaultNotificationTime) { _, newValue in
                    preferences?.defaultNotificationDate = newValue
                    savePreferences()
                }
            }
        } header: {
            Text(String(localized: "settings_notifications"))
        } footer: {
            if notificationManager.authorizationStatus == .denied {
                Text(String(localized: "settings_notifications_denied"))
            } else {
                Text(String(localized: "settings_notifications_footer"))
            }
        }
    }

    private var authorizationStatusText: String {
        switch notificationManager.authorizationStatus {
        case .authorized: return String(localized: "settings_status_allowed")
        case .denied: return String(localized: "settings_status_denied")
        case .provisional: return String(localized: "settings_status_provisional")
        case .ephemeral: return String(localized: "settings_status_ephemeral")
        case .notDetermined: return String(localized: "settings_status_not_set")
        @unknown default: return String(localized: "settings_status_unknown")
        }
    }

    private var authorizationStatusColor: Color {
        switch notificationManager.authorizationStatus {
        case .authorized, .provisional, .ephemeral: return .green
        case .denied: return .red
        case .notDetermined: return .secondary
        @unknown default: return .secondary
        }
    }

    // MARK: - Friend Notifications Section

    private var friendNotificationsSection: some View {
        Section {
            Toggle(String(localized: "settings_friend_messages"), isOn: $friendMessageNotifications)
                .onChange(of: friendMessageNotifications) { _, newValue in
                    preferences?.friendMessageNotificationsEnabled = newValue
                    savePreferences()
                }

            Toggle(String(localized: "settings_friend_completion"), isOn: $friendCompletionNotifications)
                .onChange(of: friendCompletionNotifications) { _, newValue in
                    preferences?.friendCompletionNotificationsEnabled = newValue
                    savePreferences()
                }

            Toggle(String(localized: "settings_friend_requests"), isOn: $friendRequestNotifications)
                .onChange(of: friendRequestNotifications) { _, newValue in
                    preferences?.friendRequestNotificationsEnabled = newValue
                    savePreferences()
                }
        } header: {
            Text(String(localized: "settings_friend_notifications"))
        } footer: {
            Text(String(localized: "settings_friend_notifications_footer"))
        }
    }

    // MARK: - Smart Reminders Section

    private var smartRemindersSection: some View {
        Section {
            Toggle(isOn: $smartRemindersEnabled) {
                HStack(spacing: 12) {
                    Image(systemName: "bell.badge")
                    Text(String(localized: "smart_reminders_title"))
                }
            }
            .onChange(of: smartRemindersEnabled) { _, newValue in
                preferences?.smartRemindersEnabled = newValue
                savePreferences()
                rescheduleSmartReminders()
            }

            if smartRemindersEnabled {
                Picker(String(localized: "smart_reminders_picker_label"), selection: $smartRemindersFrequency) {
                    Text(String(localized: "smart_reminders_freq_1")).tag(1)
                    Text(String(localized: "smart_reminders_freq_2")).tag(2)
                    Text(String(localized: "smart_reminders_freq_3")).tag(3)
                    Text(String(localized: "smart_reminders_freq_4")).tag(4)
                    Text(String(localized: "smart_reminders_freq_5")).tag(5)
                }
                .onChange(of: smartRemindersFrequency) { _, newValue in
                    preferences?.smartRemindersFrequency = newValue
                    savePreferences()
                    rescheduleSmartReminders()
                }
            }
        } header: {
            Text(String(localized: "smart_reminders_title"))
        } footer: {
            Text(String(localized: "smart_reminders_footer"))
                .foregroundStyle(.secondary)
        }
    }

    private func rescheduleSmartReminders() {
        guard smartRemindersEnabled else {
            Task { await notificationManager.cancelSmartReminders() }
            return
        }
        Task {
            let allActive = (try? modelContext.fetch(FetchDescriptor<Habit>(
                predicate: #Predicate { $0.isActive }
            ))) ?? []
            let today = Date()
            let incomplete = allActive.filter { !$0.isEffectivelyCompleted(for: today) }
            let habits = incomplete.isEmpty ? allActive : incomplete
            await notificationManager.scheduleSmartReminders(habits: habits, frequency: smartRemindersFrequency)
        }
    }

    // MARK: - Haptics Section

    private var hapticsSection: some View {
        Section {
            Toggle(String(localized: "settings_haptic_feedback"), isOn: $hapticsEnabled)
                .onChange(of: hapticsEnabled) { _, newValue in
                    preferences?.hapticsEnabled = newValue
                    savePreferences()

                    // Give feedback when enabling
                    if newValue {
                        #if os(iOS)
                        let generator = UIImpactFeedbackGenerator(style: .medium)
                        generator.impactOccurred()
                        #endif
                    }
                }
        } header: {
            Text(String(localized: "settings_feedback"))
        } footer: {
            Text(String(localized: "settings_haptic_footer"))
        }
    }

    // MARK: - Streak Section

    private var streakSection: some View {
        Section {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text(String(localized: "settings_streak_threshold"))
                    Spacer()
                    Text("\(Int(streakThreshold * 100))%")
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }

                Slider(value: $streakThreshold, in: 0.5...1.0, step: 0.05)
                    .tint(Color(.systemGray3))
                    .onChange(of: streakThreshold) { _, newValue in
                        preferences?.streakThreshold = newValue
                        savePreferences()
                    }

                // Quick select buttons
                HStack(spacing: 8) {
                    ForEach([0.5, 0.75, 0.9, 1.0], id: \.self) { value in
                        Button {
                            streakThreshold = value
                            preferences?.streakThreshold = value
                            savePreferences()
                        } label: {
                            Text("\(Int(value * 100))%")
                                .font(.caption)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 6)
                                .background(streakThreshold == value ? Color(.systemGray3) : Color(.systemGray6))
                                .foregroundStyle(.primary)
                                .clipShape(Capsule())
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .padding(.vertical, 4)
        } header: {
            Text(String(localized: "settings_streak"))
        } footer: {
            Text(String(localized: "settings_streak_footer"))
        }
    }

    // MARK: - Health Section

    private var healthSection: some View {
        Section {
            if healthKitManager.isHealthKitAvailable {
                HStack {
                    Label(String(localized: "settings_health_integration"), systemImage: "heart.fill")
                        .foregroundStyle(.primary)

                    Spacer()

                    if healthKitManager.isAuthorized {
                        Text(String(localized: "settings_health_active"))
                            .font(.caption.weight(.medium))
                            .foregroundStyle(.green)
                    } else {
                        Button(String(localized: "settings_health_enable")) {
                            Task { await healthKitManager.requestAuthorization() }
                        }
                        .font(.subheadline)
                        .buttonStyle(.borderedProminent)
                        .tint(.red)
                        .controlSize(.small)
                    }
                }

                if healthKitManager.isAuthorized {
                    Button {
                        if let url = URL(string: "x-apple-health://") {
                            UIApplication.shared.open(url)
                        }
                    } label: {
                        HStack {
                            Text(String(localized: "settings_health_open_app"))
                            Spacer()
                            Image(systemName: "arrow.up.right")
                                .font(.caption)
                        }
                    }
                    .foregroundStyle(.primary)
                }
            } else {
                Text(String(localized: "settings_health_unavailable"))
                    .foregroundStyle(.secondary)
                    .font(.subheadline)
            }
        } header: {
            Text(String(localized: "settings_health"))
        } footer: {
            Text(String(localized: "settings_health_footer"))
        }
    }

    // MARK: - Data Section

    private var dataSection: some View {
        Section {
            NavigationLink {
                SavedWrapsView()
            } label: {
                Label(String(localized: "settings_weekly_wraps"), systemImage: "calendar.badge.checkmark")
            }
            .foregroundStyle(.primary)

            NavigationLink {
                ArchivedHabitsView()
            } label: {
                HStack {
                    Label(String(localized: "settings_archived_habits"), systemImage: "archivebox")
                    Spacer()
                    Text("\(archivedHabits.count)")
                        .foregroundStyle(.secondary)
                }
            }
            .foregroundStyle(.primary)

            Button {
                showingExportSheet = true
            } label: {
                Label(String(localized: "settings_export_data"), systemImage: "square.and.arrow.up")
            }
            .foregroundStyle(.primary)
            .sheet(isPresented: $showingExportSheet) {
                ExportDataView()
            }

            Button(role: .destructive) {
                showingResetConfirmation = true
            } label: {
                Label(String(localized: "settings_reset_data"), systemImage: "trash")
                    .foregroundStyle(.red)
            }
            .confirmationDialog(
                String(localized: "settings_reset_title"),
                isPresented: $showingResetConfirmation,
                titleVisibility: .visible
            ) {
                Button(String(localized: "settings_reset_confirm"), role: .destructive) {
                    resetAllData()
                }
                Button(String(localized: "settings_cancel"), role: .cancel) {}
            } message: {
                Text(String(localized: "settings_reset_message"))
            }
        } header: {
            Text(String(localized: "settings_data"))
        }
    }

    // MARK: - About Section

    private var aboutSection: some View {
        Section {
            HStack {
                Text(String(localized: "settings_version"))
                Spacer()
                Text(appVersion)
                    .foregroundStyle(.secondary)
            }

            Link(destination: URL(string: "https://get-habbit.com/support")!) {
                Label(String(localized: "settings_support"), systemImage: "questionmark.circle")
            }
            .foregroundStyle(.primary)

            Link(destination: URL(string: "https://get-habbit.com/privacy")!) {
                Label(String(localized: "settings_privacy"), systemImage: "hand.raised")
            }
            .foregroundStyle(.primary)

            Link(destination: URL(string: "https://get-habbit.com/terms")!) {
                Label(String(localized: "settings_terms"), systemImage: "doc.text")
            }
            .foregroundStyle(.primary)

            Link(destination: URL(string: "https://apps.apple.com/app/idYOUR_APP_ID")!) {
                Label(String(localized: "settings_rate_app"), systemImage: "star")
            }
            .foregroundStyle(.primary)
        } header: {
            Text(String(localized: "settings_about"))
        } footer: {
            Text(String(localized: "settings_copyright"))
                .frame(maxWidth: .infinity)
                .padding(.top, 16)
                .padding(.bottom, 32)
        }
    }

    private var appVersion: String {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"
        return "\(version) (\(build))"
    }

    // MARK: - Debug Section

    #if DEBUG
    @State private var debugResult: String = ""
    @State private var pushTestObserver: NSObjectProtocol?

    private var debugSection: some View {
        Section {
            // CloudKit ID
            if let userID = CloudKitService.shared.currentUserID {
                VStack(alignment: .leading, spacing: 2) {
                    Text("CloudKit ID").font(.caption).foregroundStyle(.secondary)
                    Text(userID).font(.caption2.monospaced()).foregroundStyle(.secondary).textSelection(.enabled)
                }
            }

            // Result output
            if !debugResult.isEmpty {
                Text(debugResult)
                    .font(.caption)
                    .foregroundStyle(debugResult.hasPrefix("❌") ? .red : debugResult.hasPrefix("⏳") ? .orange : .green)
                    .fixedSize(horizontal: false, vertical: true)
            }

            // MARK: Push Notifications
            Text("Push Notifications").font(.caption.bold()).foregroundStyle(.secondary)

            Button("Run Diagnostic") {
                Task {
                    debugResult = "⏳ Running..."
                    debugResult = await CloudKitService.shared.debugPushDiagnosticString()
                }
            }

            // Local notification smoke test (fires in 5s — works on same device)
            Button("Test Local Notification (5s delay)") {
                Task {
                    let center = UNUserNotificationCenter.current()
                    let content = UNMutableNotificationContent()
                    content.title = "Push works ✅"
                    content.body = "Local notification delivered successfully."
                    content.sound = .default
                    let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 5, repeats: false)
                    let request = UNNotificationRequest(identifier: "debug-test-\(UUID())", content: content, trigger: trigger)
                    do {
                        try await center.add(request)
                        debugResult = "⏳ Background the app — notification fires in 5s"
                    } catch {
                        debugResult = "❌ Failed: \(error.localizedDescription)"
                    }
                }
            }

            // Write a CloudKit record so a SECOND DEVICE receives the push
            Button("Write CloudKit Record (trigger push on 2nd device)") {
                Task {
                    debugResult = "⏳ Writing record to CloudKit..."
                    await CloudKitService.shared.debugSendTestNotification()
                    debugResult = "✅ Record written. Check your 2nd device for push."
                }
            }

            Text("⚠️ CloudKit never pushes to the device that wrote the record. To test: run 'Write CloudKit Record' here, then check a second device (or simulator) logged into the same iCloud account.")
                .font(.caption2)
                .foregroundStyle(.secondary)

            Button("Nuke & Recreate Subscriptions") {
                Task {
                    debugResult = "⏳ Deleting all subscriptions..."
                    await CloudKitService.shared.debugNukeAndRecreateSubscriptions()
                    debugResult = "✅ Subscriptions recreated. Run Test Push to verify."
                }
            }

            Button("Simulate Background Push") {
                Task {
                    debugResult = "⏳ Simulating..."
                    await CloudKitService.shared.debugSimulateBackgroundPush(type: "friend-requests")
                    debugResult = "✅ Background sync ran — check Friends tab"
                }
            }

            // MARK: Schema Setup
            Text("Schema Setup").font(.caption.bold()).foregroundStyle(.secondary)

            Button("Seed CloudKit Schema") {
                Task {
                    debugResult = "⏳ Writing seed records for all record types..."
                    debugResult = await CloudKitService.shared.debugSeedCloudKitSchema()
                }
            }

            Text("Writes a record with every field for each CloudKit record type, then deletes them. Run this once after adding new fields so the Development schema is updated. Only needed in Development — Production schema is promoted via the CloudKit Dashboard.")
                .font(.caption2)
                .foregroundStyle(.secondary)

            // MARK: Data Sync
            Text("Data Sync").font(.caption.bold()).foregroundStyle(.secondary)

            Button("Sync Everything Now") {
                Task {
                    debugResult = "⏳ Syncing..."
                    await FriendSyncService.shared.performInitialSync(context: modelContext)
                    await ChallengeSyncService.shared.syncChallenges(context: modelContext)
                    debugResult = "✅ Sync complete"
                }
            }

            // MARK: Smart Reminders
            Text("Smart Reminders").font(.caption.bold()).foregroundStyle(.secondary)

            Button("Test Habit Reminder (10s)") {
                Task {
                    let center = UNUserNotificationCenter.current()
                    let allActive = (try? modelContext.fetch(FetchDescriptor<Habit>(
                        predicate: #Predicate { $0.isActive }
                    ))) ?? []
                    let today = Date()
                    let incomplete = allActive.filter { !$0.isEffectivelyCompleted(for: today) }
                    let habits = incomplete.isEmpty ? allActive : incomplete
                    let habit = habits.first
                    let name = habit?.name ?? "your habit"
                    let emoji = habit?.emoji ?? "✨"

                    let (title, body) = NotificationManager.randomHabitTemplate(name: name, emoji: emoji)
                    let content = UNMutableNotificationContent()
                    content.title = title
                    content.body = body
                    content.sound = .default
                    let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 10, repeats: false)
                    let request = UNNotificationRequest(identifier: "debug-smart-\(UUID())", content: content, trigger: trigger)
                    do {
                        try await center.add(request)
                        debugResult = "⏳ Background the app — habit reminder fires in 10s"
                    } catch {
                        debugResult = "❌ Failed: \(error.localizedDescription)"
                    }
                }
            }

            Button("Test Goal Reminder (10s)") {
                Task {
                    let center = UNUserNotificationCenter.current()
                    let allActive = (try? modelContext.fetch(FetchDescriptor<Habit>(
                        predicate: #Predicate { $0.isActive }
                    ))) ?? []
                    let today = Date()
                    let incomplete = allActive.filter { !$0.isEffectivelyCompleted(for: today) }
                    let habits = incomplete.isEmpty ? allActive : incomplete
                    let habit = habits.first
                    let name = habit?.name ?? "your habit"
                    let emoji = habit?.emoji ?? "✨"
                    let goalName = habit?.goal?.name ?? name

                    let (title, body) = NotificationManager.randomGoalTemplate(name: name, emoji: emoji, goal: goalName)
                    let content = UNMutableNotificationContent()
                    content.title = title
                    content.body = body
                    content.sound = .default
                    let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 10, repeats: false)
                    let request = UNNotificationRequest(identifier: "debug-goal-\(UUID())", content: content, trigger: trigger)
                    do {
                        try await center.add(request)
                        debugResult = "⏳ Background the app — goal reminder fires in 10s (habit: \(name), goal: \(goalName))"
                    } catch {
                        debugResult = "❌ Failed: \(error.localizedDescription)"
                    }
                }
            }

            // MARK: Cleanup
            Text("Cleanup").font(.caption.bold()).foregroundStyle(.secondary)

            Button("Clear All Local Data", role: .destructive) {
                Task {
                    debugResult = "⏳ Clearing local data..."
                    debugClearLocalData()
                    debugResult = "✅ Local data cleared"
                }
            }

            Button("Clear My CloudKit Data", role: .destructive) {
                Task {
                    debugResult = "⏳ Deleting CloudKit records..."
                    let count = await CloudKitService.shared.debugClearMyCloudKitData()
                    debugResult = "✅ Deleted \(count) CloudKit records"
                }
            }

        } header: {
            Text("Debug (Dev Only)")
        }
    }

    private func debugClearLocalData() {
        if let r = try? modelContext.fetch(FetchDescriptor<FriendProfile>())         { r.forEach { modelContext.delete($0) } }
        if let r = try? modelContext.fetch(FetchDescriptor<SharedChallenge>())       { r.forEach { modelContext.delete($0) } }
        if let r = try? modelContext.fetch(FetchDescriptor<ChallengeCompletion>())   { r.forEach { modelContext.delete($0) } }
        if let r = try? modelContext.fetch(FetchDescriptor<ReceivedMessage>())       { r.forEach { modelContext.delete($0) } }
        if let r = try? modelContext.fetch(FetchDescriptor<SentMessage>())           { r.forEach { modelContext.delete($0) } }
        try? modelContext.save()
    }
    #endif

    // MARK: - Data Management

    private func loadPreferences() {
        preferences = UserPreferences.shared(in: modelContext)

        if let prefs = preferences {
            // If UserPreferences is missing name/quote but MyCloudProfile has them (after reinstall),
            // sync from cloud profile to local preferences
            if let cloudProfile = cloudProfiles.first {
                if prefs.userName == nil && !cloudProfile.displayName.isEmpty {
                    prefs.userName = cloudProfile.displayName
                }
                if prefs.motivationQuote == nil, let quote = cloudProfile.motivationalQuote, !quote.isEmpty {
                    prefs.motivationQuote = quote
                }
            }

            userName = prefs.userName ?? ""
            motivationQuote = prefs.motivationQuote ?? ""
            notificationsEnabled = prefs.notificationsEnabled
            friendMessageNotifications = prefs.friendMessageNotificationsEnabled
            friendCompletionNotifications = prefs.friendCompletionNotificationsEnabled
            friendRequestNotifications = prefs.friendRequestNotificationsEnabled
            hapticsEnabled = prefs.hapticsEnabled
            selectedTheme = prefs.theme
            selectedAccentColor = prefs.appAccentColor
            firstDayOfWeek = prefs.firstDayOfWeek
            defaultNotificationTime = prefs.defaultNotificationDate ?? defaultTime()
            streakThreshold = prefs.streakThreshold
            smartRemindersEnabled = prefs.smartRemindersEnabled
            smartRemindersFrequency = prefs.smartRemindersFrequency
        }
    }

    private func defaultTime() -> Date {
        var components = DateComponents()
        components.hour = 9
        components.minute = 0
        return Calendar.current.date(from: components) ?? Date()
    }

    private func savePreferences() {
        do {
            try modelContext.save()
        } catch {
            print("Failed to save preferences: \(error)")
        }
    }

    /// Syncs profile changes to MyCloudProfile for the Friends feature
    private func syncToCloudProfile() {
        if let cloudProfile = cloudProfiles.first {
            let trimmedName = userName.trimmingCharacters(in: .whitespacesAndNewlines)
            let trimmedQuote = motivationQuote.trimmingCharacters(in: .whitespacesAndNewlines)

            cloudProfile.displayName = trimmedName.isEmpty ? cloudProfile.displayName : trimmedName
            cloudProfile.motivationalQuote = trimmedQuote.isEmpty ? nil : trimmedQuote
            cloudProfile.isSynced = false // Mark as needing re-sync to CloudKit

            // Async sync to CloudKit
            Task {
                do {
                    try await CloudKitService.shared.saveUserProfile(cloudProfile)
                } catch {
                    print("Failed to sync profile to CloudKit: \(error)")
                }
            }
        }
    }

    private func resetAllData() {
        // Cancel all notifications
        NotificationManager.shared.cancelAllNotifications()

        // Delete all habits (cascade deletes completions)
        let habitDescriptor = FetchDescriptor<Habit>()
        if let habits = try? modelContext.fetch(habitDescriptor) {
            for habit in habits {
                modelContext.delete(habit)
            }
        }

        // Delete all goals
        let goalDescriptor = FetchDescriptor<Goal>()
        if let goals = try? modelContext.fetch(goalDescriptor) {
            for goal in goals {
                modelContext.delete(goal)
            }
        }

        // Reset preferences to default
        if let prefs = preferences {
            prefs.hasCompletedOnboarding = false
            prefs.userName = nil
            prefs.motivationQuote = nil
        }

        savePreferences()
        loadPreferences()
    }
}

// MARK: - Accent Color Picker

struct AccentColorPicker: View {
    @Binding var selectedColor: String
    let onSave: () -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme

    private let colors: [(name: String, hex: String)] = [
        // Vibrant colors
        ("Blue", "#007AFF"),
        ("Purple", "#5856D6"),
        ("Pink", "#FF2D55"),
        ("Red", "#FF3B30"),
        ("Orange", "#FF9500"),
        ("Yellow", "#FFCC00"),
        ("Green", "#34C759"),
        ("Teal", "#5AC8FA"),
        ("Indigo", "#5E5CE6"),
        ("Mint", "#00C7BE"),
        ("Cyan", "#32ADE6"),
        // Neutral colors
        ("Brown", "#A2845E"),
        ("Graphite", "#8E8E93"),
        ("Slate", "#636366"),
        ("Charcoal", "#48484A"),
        ("Stone", "#AEAEB2"),
        ("Taupe", "#9A8C7B"),
        ("Sage", "#8A9A8A"),
        ("Steel", "#6B7B8C")
    ]

    var body: some View {
        List {
            // Adaptive option at the top
            Section {
                Button {
                    selectedColor = UserPreferences.adaptiveAccentColor
                    onSave()
                } label: {
                    HStack {
                        ZStack {
                            Circle()
                                .fill(Color.primary)
                                .frame(width: 32, height: 32)
                        }

                        Text(String(localized: "settings_adaptive"))

                        Spacer()

                        Text(String(localized: "settings_auto"))
                            .font(.caption)
                            .foregroundStyle(.secondary)

                        if selectedColor == UserPreferences.adaptiveAccentColor {
                            Image(systemName: "checkmark")
                                .foregroundStyle(.primary)
                                .fontWeight(.semibold)
                        }
                    }
                }
                .buttonStyle(.plain)
            } footer: {
                Text(String(localized: "settings_adaptive_description"))
            }

            Section(String(localized: "settings_colors")) {
                ForEach(colors, id: \.hex) { color in
                    Button {
                        selectedColor = color.hex
                        onSave()
                    } label: {
                        HStack {
                            Circle()
                                .fill(Color(hex: color.hex))
                                .frame(width: 32, height: 32)

                            Text(color.name)

                            Spacer()

                            if selectedColor == color.hex {
                                Image(systemName: "checkmark")
                                    .foregroundStyle(Color(hex: color.hex))
                                    .fontWeight(.semibold)
                            }
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .dimThemeBackground()
        .navigationTitle(String(localized: "settings_accent_color"))
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
    }
}

// MARK: - Goal Edit View

struct GoalEditView: View {
    @Bindable var goal: Goal
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @State private var goalName: String = ""
    @State private var goalDescription: String = ""

    var body: some View {
        Form {
            Section {
                TextField(String(localized: "settings_goal_name"), text: $goalName)
                    .submitLabel(.done)

                TextField(String(localized: "settings_description_optional"), text: $goalDescription, axis: .vertical)
                    .lineLimit(2...4)
                    .submitLabel(.done)
                    .onSubmit {
                        #if canImport(UIKit)
                        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
                        #endif
                    }
            } header: {
                Text(String(localized: "settings_goal_details"))
            }

            Section {
                HStack {
                    Text(String(localized: "tab_habits"))
                    Spacer()
                    Text("\(goal.safeHabits.count)")
                        .foregroundStyle(.secondary)
                }

                HStack {
                    Text(String(localized: "settings_created"))
                    Spacer()
                    Text(goal.createdDate.formatted(date: .abbreviated, time: .omitted))
                        .foregroundStyle(.secondary)
                }
            } header: {
                Text(String(localized: "settings_info"))
            }
        }
        .dimThemeBackground()
        .navigationTitle(String(localized: "settings_edit_goal"))
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button(String(localized: "settings_save")) {
                    saveGoal()
                }
                .fontWeight(.semibold)
                .disabled(goalName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .onAppear {
            goalName = goal.name
            goalDescription = goal.goalDescription ?? ""
        }
    }

    private func saveGoal() {
        goal.name = goalName.trimmingCharacters(in: .whitespacesAndNewlines)
        goal.goalDescription = goalDescription.isEmpty ? nil : goalDescription

        do {
            try modelContext.save()
            dismiss()
        } catch {
            print("Failed to save goal: \(error)")
        }
    }
}

// MARK: - Export Data View

struct ExportDataView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @Query private var habits: [Habit]
    @Query private var goals: [Goal]
    @Query private var completions: [HabitCompletion]

    @State private var exportFormat: ExportFormat = .json
    @State private var isExporting = false

    enum ExportFormat: String, CaseIterable {
        case json = "JSON"
        case csv = "CSV"
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("Format", selection: $exportFormat) {
                        ForEach(ExportFormat.allCases, id: \.self) { format in
                            Text(format.rawValue).tag(format)
                        }
                    }
                    .pickerStyle(.segmented)
                } header: {
                    Text(String(localized: "settings_export_format"))
                }

                Section {
                    HStack {
                        Text(String(localized: "tab_habits"))
                        Spacer()
                        Text("\(habits.count)")
                            .foregroundStyle(.secondary)
                    }

                    HStack {
                        Text(String(localized: "settings_goals"))
                        Spacer()
                        Text("\(goals.count)")
                            .foregroundStyle(.secondary)
                    }

                    HStack {
                        Text(String(localized: "settings_completions"))
                        Spacer()
                        Text("\(completions.count)")
                            .foregroundStyle(.secondary)
                    }
                } header: {
                    Text(String(localized: "settings_data_summary"))
                }

                Section {
                    if let url = generateExportURL() {
                        ShareLink(item: url) {
                            Label(String(localized: "settings_export"), systemImage: "square.and.arrow.up")
                                .foregroundStyle(.primary)
                        }
                    } else {
                        Button {
                            // Fallback
                        } label: {
                            Label(String(localized: "settings_export"), systemImage: "square.and.arrow.up")
                                .foregroundStyle(.primary)
                        }
                        .disabled(true)
                    }
                }
            }
            .dimThemeBackground()
            .navigationTitle(String(localized: "settings_export_title"))
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(String(localized: "settings_cancel")) {
                        dismiss()
                    }
                }
            }
        }
        .presentationDetents([.medium])
    }

    private func generateExportURL() -> URL? {
        let exportData = ExportData(
            exportDate: Date(),
            habits: habits.map { HabitExport(from: $0) },
            goals: goals.map { GoalExport(from: $0) },
            completions: completions.map { CompletionExport(from: $0) }
        )

        let fileName: String
        let data: Data?

        switch exportFormat {
        case .json:
            fileName = "stick_export_\(dateString()).json"
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            data = try? encoder.encode(exportData)

        case .csv:
            fileName = "stick_habits_\(dateString()).csv"
            data = generateCSV().data(using: .utf8)
        }

        guard let exportData = data else { return nil }

        let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent(fileName)
        try? exportData.write(to: tempURL)
        return tempURL
    }

    private func dateString() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: Date())
    }

    private func generateCSV() -> String {
        var csv = "Name,Description,Frequency,Color,Created,Completions,Current Streak\n"

        for habit in habits {
            let name = habit.name.replacingOccurrences(of: ",", with: ";")
            let desc = (habit.habitDescription ?? "").replacingOccurrences(of: ",", with: ";")
            let freq = habit.frequency.displayName
            let color = habit.color
            let created = ISO8601DateFormatter().string(from: habit.createdDate)
            let completionCount = habit.safeCompletions.count
            let streak = habit.currentStreak()

            csv += "\(name),\(desc),\(freq),\(color),\(created),\(completionCount),\(streak)\n"
        }

        return csv
    }
}

// MARK: - Export Data Structures

struct ExportData: Codable {
    let exportDate: Date
    let habits: [HabitExport]
    let goals: [GoalExport]
    let completions: [CompletionExport]
}

struct HabitExport: Codable {
    let id: String
    let name: String
    let description: String?
    let color: String
    let emoji: String?
    let symbolName: String?
    let frequency: String
    let createdDate: Date
    let isActive: Bool

    init(from habit: Habit) {
        self.id = habit.id.uuidString
        self.name = habit.name
        self.description = habit.habitDescription
        self.color = habit.color
        self.emoji = habit.emoji
        self.symbolName = habit.symbolName
        self.frequency = habit.frequency.rawValue
        self.createdDate = habit.createdDate
        self.isActive = habit.isActive
    }
}

struct GoalExport: Codable {
    let id: String
    let name: String
    let description: String?
    let createdDate: Date

    init(from goal: Goal) {
        self.id = goal.id.uuidString
        self.name = goal.name
        self.description = goal.goalDescription
        self.createdDate = goal.createdDate
    }
}

struct CompletionExport: Codable {
    let id: String
    let habitId: String?
    let completionDate: Date
    let count: Int
    let actualDuration: TimeInterval?
    let notes: String?

    init(from completion: HabitCompletion) {
        self.id = completion.id.uuidString
        self.habitId = completion.habit?.id.uuidString
        self.completionDate = completion.completionDate
        self.count = completion.count
        self.actualDuration = completion.actualDuration
        self.notes = completion.notes
    }
}

// MARK: - Preview

#Preview {
    SettingsView()
        .modelContainer(.preview)
}
