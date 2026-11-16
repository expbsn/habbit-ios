//
//  UserPreferences.swift
//  Stick
//
//  Created by Kian Jain on 02.02.26.
//

import Foundation
import SwiftData

/// User preferences and settings for the app.
/// This model is designed as a singleton - there should only ever be one instance.
/// Use `UserPreferences.shared(in:)` to fetch or create the single instance.
@Model
final class UserPreferences {
    // MARK: - Onboarding

    var hasCompletedOnboarding: Bool = false

    /// Onboarding answers stored as JSON data
    /// Keys: question identifiers, Values: user answers
    var onboardingAnswersData: Data?

    // MARK: - App Appearance

    /// Global app accent color (hex string, e.g., "#007AFF")
    var appAccentColor: String = "adaptive"

    /// App theme preference: "system", "light", or "dark"
    var themePreference: String = "system"

    /// First day of week: 1 = Sunday, 2 = Monday (matches Calendar.Weekday)
    var firstDayOfWeek: Int = 1

    // MARK: - Notifications

    var notificationsEnabled: Bool = true

    /// Whether smart motivational reminders are enabled
    var smartRemindersEnabled: Bool = false

    /// How many smart reminders to send per day: 1, 2, or 3
    var smartRemindersFrequency: Int = 2

    /// Default notification time stored as seconds from midnight
    var defaultNotificationTime: TimeInterval?

    // MARK: - Friend Notifications

    /// Notify when a friend sends you a message
    var friendMessageNotificationsEnabled: Bool = true

    /// Notify when a friend reaches 100% daily completion
    var friendCompletionNotificationsEnabled: Bool = true

    /// Notify when someone sends you a friend request
    var friendRequestNotificationsEnabled: Bool = true

    // MARK: - User Experience

    var hapticsEnabled: Bool = true

    // MARK: - Streak Settings

    /// Minimum completion percentage required for a day to count toward streak (0.0 - 1.0)
    /// Default is 1.0 (100%)
    var streakThreshold: Double = 1.0

    // MARK: - User Profile (Optional)

    var userName: String?
    var motivationQuote: String?

    // MARK: - Computed Properties

    /// Access onboarding answers as a dictionary
    var onboardingAnswers: [String: String] {
        get {
            guard let data = onboardingAnswersData else { return [:] }
            return (try? JSONDecoder().decode([String: String].self, from: data)) ?? [:]
        }
        set {
            onboardingAnswersData = try? JSONEncoder().encode(newValue)
        }
    }

    /// Theme as enum for easier use
    var theme: AppTheme {
        get { AppTheme(rawValue: themePreference) ?? .system }
        set { themePreference = newValue.rawValue }
    }

    /// Default notification time as Date (time component only)
    var defaultNotificationDate: Date? {
        get {
            guard let interval = defaultNotificationTime else { return nil }
            return Calendar.current.startOfDay(for: Date()).addingTimeInterval(interval)
        }
        set {
            guard let date = newValue else {
                defaultNotificationTime = nil
                return
            }
            let startOfDay = Calendar.current.startOfDay(for: date)
            defaultNotificationTime = date.timeIntervalSince(startOfDay)
        }
    }

    // MARK: - Initialization

    /// Special value for adaptive accent color (black in light mode, white in dark mode)
    static let adaptiveAccentColor = "adaptive"

    init(
        hasCompletedOnboarding: Bool = false,
        appAccentColor: String = UserPreferences.adaptiveAccentColor,
        themePreference: String = "system",
        firstDayOfWeek: Int = 1,
        notificationsEnabled: Bool = true,
        hapticsEnabled: Bool = true
    ) {
        self.hasCompletedOnboarding = hasCompletedOnboarding
        self.appAccentColor = appAccentColor
        self.themePreference = themePreference
        self.firstDayOfWeek = firstDayOfWeek
        self.notificationsEnabled = notificationsEnabled
        self.hapticsEnabled = hapticsEnabled
    }

    // MARK: - Singleton Access

    /// Fetches the existing UserPreferences instance or creates one if none exists.
    /// This ensures there's always exactly one UserPreferences object in the database.
    ///
    /// Usage:
    /// ```swift
    /// let preferences = UserPreferences.shared(in: modelContext)
    /// ```
    @MainActor
    static func shared(in context: ModelContext) -> UserPreferences {
        let descriptor = FetchDescriptor<UserPreferences>()

        do {
            let existing = try context.fetch(descriptor)
            if let first = existing.first {
                // Clean up duplicates if any exist (shouldn't happen, but be safe)
                if existing.count > 1 {
                    for duplicate in existing.dropFirst() {
                        context.delete(duplicate)
                    }
                }
                return first
            }
        } catch {
            print("Error fetching UserPreferences: \(error)")
        }

        // No existing preferences found, create default
        let preferences = UserPreferences.createDefault()
        context.insert(preferences)
        return preferences
    }

    // MARK: - Default Instance

    /// Creates a default UserPreferences instance with standard settings.
    /// Prefer using `shared(in:)` to ensure singleton behavior.
    static func createDefault() -> UserPreferences {
        let preferences = UserPreferences()

        // Set default notification time to 9:00 AM
        var components = DateComponents()
        components.hour = 9
        components.minute = 0
        if let date = Calendar.current.date(from: components) {
            preferences.defaultNotificationDate = date
        }

        return preferences
    }
}

// MARK: - Onboarding Question Keys

extension UserPreferences {
    /// Standard onboarding question identifiers
    enum OnboardingQuestion: String {
        case statement = "statement"           // "To which statement can you relate the most?"
        case procrastination = "procrastination" // "Does procrastination bother you?"
        case goalMeaning = "goalMeaning"       // "What does setting a goal mean for you?"
        case holdingBack = "holdingBack"       // "What is holding you back from completing your goals?"
        case whyHabits = "whyHabits"           // "Why do you want to build habits?"

        // Legacy keys (kept for backwards compatibility)
        case motivation = "motivation"
        case challenge = "challenge"
    }

    /// Get answer for a specific onboarding question
    func answer(for question: OnboardingQuestion) -> String? {
        onboardingAnswers[question.rawValue]
    }

    /// Set answer for a specific onboarding question
    func setAnswer(_ answer: String, for question: OnboardingQuestion) {
        var answers = onboardingAnswers
        answers[question.rawValue] = answer
        onboardingAnswers = answers
    }
}

// MARK: - App Theme

enum AppTheme: String, CaseIterable {
    case system = "system"
    case light = "light"
    case dark = "dark"
    case dim = "dim"

    var displayName: String {
        switch self {
        case .system: return "System"
        case .light: return "Light"
        case .dark: return "Dark"
        case .dim: return "Dim"
        }
    }

    var localizedName: String {
        switch self {
        case .system: return String(localized: "settings_theme_system")
        case .light: return String(localized: "settings_theme_light")
        case .dark: return String(localized: "settings_theme_dark")
        case .dim: return String(localized: "settings_theme_dim")
        }
    }

    var icon: String {
        switch self {
        case .system: return "circle.lefthalf.filled"
        case .light: return "sun.max.fill"
        case .dark: return "moon.fill"
        case .dim: return "moon.haze.fill"
        }
    }
}
