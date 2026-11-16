//
//  ContentView.swift
//  Stick
//
//  Created by Kian Jain on 02.02.26.
//

import SwiftUI
import SwiftData

struct ContentView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.colorScheme) private var systemColorScheme
    @Query private var preferences: [UserPreferences]
    @Query private var habits: [Habit]

    /// State for CloudKit sync check
    @State private var isCheckingCloudSync = true
    /// Once decided, this locks in whether to show onboarding (prevents mid-session switches)
    @State private var shouldShowOnboarding: Bool? = nil

    /// Set to true to skip onboarding during development
    #if DEBUG
    private let skipOnboarding = false
    private let forceShowOnboarding = false
    #else
    private let skipOnboarding = false
    private let forceShowOnboarding = false
    #endif

    /// Check current data to determine if user has completed onboarding
    private var hasCompletedOnboardingFromData: Bool {
        if forceShowOnboarding { return false }
        if skipOnboarding { return true }
        // Primary check: user explicitly completed onboarding
        if preferences.first?.hasCompletedOnboarding == true { return true }
        // Fallback for iCloud restore: if habits exist, user has used the app before
        if !habits.isEmpty { return true }
        return false
    }

    /// Current accent color from preferences
    private var accentColor: Color {
        let colorValue = preferences.first?.appAccentColor ?? UserPreferences.adaptiveAccentColor
        if colorValue == UserPreferences.adaptiveAccentColor {
            return Color.primary
        }
        return Color(hex: colorValue)
    }

    /// Current theme preference
    private var colorScheme: ColorScheme? {
        guard let theme = preferences.first?.theme else { return nil }
        switch theme {
        case .system: return nil
        case .light: return .light
        case .dark, .dim: return .dark
        }
    }

    /// Whether user has completed onboarding (locked in after sync check)
    private var hasCompletedOnboarding: Bool {
        // Once decided, use the locked-in value
        if let decided = shouldShowOnboarding {
            return !decided
        }
        // During sync check, use current data
        return hasCompletedOnboardingFromData
    }

    var body: some View {
        Group {
            if isCheckingCloudSync {
                // Loading screen while waiting for CloudKit sync
                launchScreen
            } else if hasCompletedOnboarding {
                MainTabView()
                    .preferredColorScheme(colorScheme)
            } else {
                OnboardingView()
                // Onboarding follows system appearance
            }
        }
        .tint(accentColor)
        .id("\(preferences.first?.appAccentColor ?? "default")-\(preferences.first?.themePreference ?? "system")") // Force re-render when accent or theme changes
        .onAppear {
            startCloudSyncCheck()
        }
        .onChange(of: preferences.first?.hasCompletedOnboarding) { _, newValue in
            // Update onboarding state when user completes onboarding or CloudKit syncs
            if newValue == true {
                shouldShowOnboarding = false
                isCheckingCloudSync = false
            }
        }
        .onChange(of: habits.count) { _, newCount in
            // If habits sync from CloudKit, stop waiting and lock in decision
            if newCount > 0 && isCheckingCloudSync {
                shouldShowOnboarding = false // Lock in: don't show onboarding
                isCheckingCloudSync = false
            }
        }
        .onOpenURL { url in
            handleDeepLink(url)
        }
    }

    /// Launch screen shown while waiting for CloudKit sync
    private var launchScreen: some View {
        ZStack {
            Color(.systemBackground)
                .ignoresSafeArea()

            VStack(spacing: 6) {
                Image("loading")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 80, height: 80)

                Text("Habbit")
                    .font(.system(size: 22, weight: .medium, design: .rounded))
                    .tracking(-1.2)
                    .foregroundStyle(.primary)
            }
        }
    }

    /// Start checking for CloudKit sync with timeout
    private func startCloudSyncCheck() {
        Task {
            // Wait up to 6 seconds for CloudKit data to sync
            // If data arrives earlier (via onChange), we'll stop waiting immediately
            try? await Task.sleep(nanoseconds: 6_000_000_000) // 6 seconds max

            await MainActor.run {
                if isCheckingCloudSync {
                    // Lock in the onboarding decision based on current data
                    // This prevents late-arriving CloudKit data from switching views mid-session
                    shouldShowOnboarding = !hasCompletedOnboardingFromData
                    isCheckingCloudSync = false
                    ensureUserPreferencesExist()
                }
            }
        }
    }

    /// Handle deep links from Live Activity and friend invites
    private func handleDeepLink(_ url: URL) {
        guard url.scheme == "stick" else { return }

        let pathComponent = url.lastPathComponent
        print("Deep link received: \(url), action: \(pathComponent)")

        Task { @MainActor in
            switch url.host {
            case "timer":
                await handleTimerAction(pathComponent)
            case "friend":
                await handleFriendInvite(url)
            default:
                break
            }
        }
    }

    /// Handle friend invite deep links
    @MainActor
    private func handleFriendInvite(_ url: URL) async {
        // Parse the user ID from the URL: stick://friend/invite?id=USER_ID
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let userID = components.queryItems?.first(where: { $0.name == "id" })?.value else {
            print("Invalid friend invite URL: \(url)")
            return
        }

        print("📨 Friend invite received from user: \(userID)")

        // Wait for CloudKit to be ready (up to 5 seconds)
        let cloudKit = CloudKitService.shared
        print("📨 Waiting for CloudKit... isAuthenticated: \(cloudKit.isAuthenticated), currentUserID: \(cloudKit.currentUserID ?? "nil")")

        var attempts = 0
        while cloudKit.currentUserID == nil && attempts < 50 {
            try? await Task.sleep(nanoseconds: 100_000_000) // 0.1 seconds
            attempts += 1
        }

        print("📨 CloudKit ready after \(attempts) attempts. currentUserID: \(cloudKit.currentUserID ?? "nil")")

        // Check if CloudKit is ready
        guard let currentUserID = cloudKit.currentUserID else {
            print("❌ CloudKit not authenticated after 5s, cannot process friend invite")
            return
        }

        // Don't send request to yourself
        guard userID != currentUserID else {
            print("❌ Cannot send friend request to yourself (your ID: \(currentUserID))")
            return
        }

        print("📨 Sending friend request from \(currentUserID) to \(userID)...")

        // Send friend request to the inviter (also creates local FriendProfile)
        do {
            try await FriendSyncService.shared.sendFriendRequest(toUserID: userID, context: modelContext)
            print("✅ Friend request sent successfully to: \(userID)")
        } catch {
            print("❌ Failed to send friend request: \(error)")
        }
    }

    /// Handle timer actions from Live Activity buttons
    @MainActor
    private func handleTimerAction(_ action: String) async {
        let manager = TimerActivityManager.shared

        print("Timer action: \(action), hasActiveHabit: \(manager.activeHabitId != nil), isRunning: \(manager.isTimerRunning)")

        switch action {
        case "toggle":
            // Toggle pause/resume
            if manager.activeHabitId != nil {
                let remaining = manager.getCurrentRemainingSeconds()
                if manager.isTimerRunning {
                    // Pause the timer
                    print("Pausing timer, remaining: \(remaining)")
                    await manager.updateActivity(remainingSeconds: remaining, isRunning: false)
                } else {
                    // Resume the timer
                    print("Resuming timer, remaining: \(remaining)")
                    await manager.updateActivity(remainingSeconds: remaining, isRunning: true)
                }
            } else {
                print("No active timer to toggle")
            }
        case "cancel":
            // Cancel/end the timer
            print("Canceling timer")
            await manager.endActivity()
        default:
            break
        }
    }

    /// Ensure UserPreferences singleton exists
    private func ensureUserPreferencesExist() {
        if preferences.isEmpty {
            let defaultPreferences = UserPreferences.createDefault()
            modelContext.insert(defaultPreferences)
        }
    }
}

#Preview("App") {
    ContentView()
        .modelContainer(.preview)
}

#Preview("Main Tab (Skip Onboarding)") {
    MainTabView()
        .modelContainer(.preview)
}
