//
//  NotificationManager.swift
//  Stick
//
//  Created by Kian Jain on 02.02.26.
//

import Foundation
import UserNotifications
import SwiftData
import Combine

/// Manages local notifications for habit reminders
@MainActor
final class NotificationManager: ObservableObject {
    static let shared = NotificationManager()

    @Published var isAuthorized = false
    @Published var authorizationStatus: UNAuthorizationStatus = .notDetermined

    private let notificationCenter = UNUserNotificationCenter.current()

    private init() {
        Task {
            await checkAuthorizationStatus()
        }
    }

    // MARK: - Authorization

    /// Check current authorization status
    func checkAuthorizationStatus() async {
        let settings = await notificationCenter.notificationSettings()
        authorizationStatus = settings.authorizationStatus
        isAuthorized = settings.authorizationStatus == .authorized
    }

    /// Request notification permissions
    func requestAuthorization() async -> Bool {
        do {
            let granted = try await notificationCenter.requestAuthorization(options: [.alert, .badge, .sound])
            await checkAuthorizationStatus()
            return granted
        } catch {
            print("Notification authorization error: \(error)")
            return false
        }
    }

    // MARK: - Scheduling

    /// Schedule notifications for a habit based on its settings
    func scheduleNotifications(for habit: Habit) async {
        guard habit.notificationsEnabled else {
            await cancelNotifications(for: habit)
            return
        }

        guard isAuthorized else {
            print("Notifications not authorized")
            return
        }

        // Cancel existing notifications for this habit first
        await cancelNotifications(for: habit)

        // Get scheduled times or use default
        let times = habit.scheduledTimes.isEmpty ? [defaultReminderTime()] : habit.scheduledTimes

        for (index, time) in times.enumerated() {
            await scheduleNotification(
                for: habit,
                at: time,
                identifier: "\(habit.id.uuidString)-\(index)"
            )
        }
    }

    /// Schedule a single notification
    private func scheduleNotification(for habit: Habit, at time: Date, identifier: String) async {
        let content = UNMutableNotificationContent()
        content.title = "Time for \(habit.name)"
        content.body = habit.reminderMessage ?? "Don't forget to complete your habit!"
        content.sound = .default
        content.badge = 1

        // Add habit ID for handling tap
        content.userInfo = ["habitId": habit.id.uuidString]

        // Create trigger based on frequency
        let trigger = createTrigger(for: habit, at: time)

        let request = UNNotificationRequest(
            identifier: identifier,
            content: content,
            trigger: trigger
        )

        do {
            try await notificationCenter.add(request)
        } catch {
            print("Failed to schedule notification: \(error)")
        }
    }

    /// Create appropriate trigger based on habit frequency
    private func createTrigger(for habit: Habit, at time: Date) -> UNNotificationTrigger {
        let calendar = Calendar.current
        let timeComponents = calendar.dateComponents([.hour, .minute], from: time)

        switch habit.frequency {
        case .daily:
            // Daily at specified time
            var components = DateComponents()
            components.hour = timeComponents.hour
            components.minute = timeComponents.minute
            return UNCalendarNotificationTrigger(dateMatching: components, repeats: true)

        case .weekly:
            if habit.scheduledDays.isEmpty {
                // Flexible weekly - notify daily
                var components = DateComponents()
                components.hour = timeComponents.hour
                components.minute = timeComponents.minute
                return UNCalendarNotificationTrigger(dateMatching: components, repeats: true)
            } else {
                // Specific days - use first scheduled day
                // Note: For multiple days, we'd need multiple notifications
                let weekday = habit.scheduledDays.first ?? 2
                var components = DateComponents()
                components.weekday = weekday
                components.hour = timeComponents.hour
                components.minute = timeComponents.minute
                return UNCalendarNotificationTrigger(dateMatching: components, repeats: true)
            }

        case .monthly:
            // Monthly on day 1 (could be customized)
            var components = DateComponents()
            components.day = 1
            components.hour = timeComponents.hour
            components.minute = timeComponents.minute
            return UNCalendarNotificationTrigger(dateMatching: components, repeats: true)

        case .customInterval:
            // Custom interval in days
            let interval = TimeInterval((habit.customInterval ?? 1) * 24 * 60 * 60)
            return UNTimeIntervalNotificationTrigger(timeInterval: interval, repeats: true)
        }
    }

    /// Schedule notifications for specific weekdays
    func scheduleWeekdayNotifications(for habit: Habit, times: [Date]) async {
        guard habit.notificationsEnabled, isAuthorized else { return }
        guard !habit.scheduledDays.isEmpty else { return }

        await cancelNotifications(for: habit)

        let calendar = Calendar.current

        for (dayIndex, weekday) in habit.scheduledDays.enumerated() {
            for (timeIndex, time) in times.enumerated() {
                let timeComponents = calendar.dateComponents([.hour, .minute], from: time)

                var components = DateComponents()
                components.weekday = weekday
                components.hour = timeComponents.hour
                components.minute = timeComponents.minute

                let content = UNMutableNotificationContent()
                content.title = "Time for \(habit.name)"
                content.body = habit.reminderMessage ?? "Don't forget to complete your habit!"
                content.sound = .default
                content.userInfo = ["habitId": habit.id.uuidString]

                let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: true)
                let identifier = "\(habit.id.uuidString)-\(dayIndex)-\(timeIndex)"

                let request = UNNotificationRequest(
                    identifier: identifier,
                    content: content,
                    trigger: trigger
                )

                do {
                    try await notificationCenter.add(request)
                } catch {
                    print("Failed to schedule weekday notification: \(error)")
                }
            }
        }
    }

    // MARK: - Cancellation

    /// Cancel all notifications for a specific habit
    func cancelNotifications(for habit: Habit) async {
        let pendingRequests = await notificationCenter.pendingNotificationRequests()
        let identifiersToRemove = pendingRequests
            .filter { $0.identifier.hasPrefix(habit.id.uuidString) }
            .map { $0.identifier }

        notificationCenter.removePendingNotificationRequests(withIdentifiers: identifiersToRemove)
    }

    /// Cancel all habit notifications
    func cancelAllNotifications() {
        notificationCenter.removeAllPendingNotificationRequests()
    }

    // MARK: - Badge Management

    /// Clear the app badge
    func clearBadge() async {
        #if os(iOS)
        await MainActor.run {
            UNUserNotificationCenter.current().setBadgeCount(0)
        }
        #endif
    }

    // MARK: - Helpers

    private func defaultReminderTime() -> Date {
        var components = DateComponents()
        components.hour = 9
        components.minute = 0
        return Calendar.current.date(from: components) ?? Date()
    }

    /// Get all pending notifications (for debugging)
    func getPendingNotifications() async -> [UNNotificationRequest] {
        await notificationCenter.pendingNotificationRequests()
    }

    /// Reschedule all notifications for all habits
    func rescheduleAllNotifications(habits: [Habit]) async {
        cancelAllNotifications()

        for habit in habits where habit.isActive && habit.notificationsEnabled {
            await scheduleNotifications(for: habit)
        }
    }

    // MARK: - Smart Reminders

    /// All pending smart-reminder notification identifiers use this prefix so they can be bulk-cancelled.
    private static let smartReminderPrefix = "smart_reminder_"

    /// Playful habit-name templates loaded from localizable strings.
    /// {name} and {emoji} are substituted at schedule time.
    private static var messageTemplates: [(title: String, body: String)] {
        (0..<12).map { i in
            (NSLocalizedString("smart_habit_\(i)_title", comment: ""),
             NSLocalizedString("smart_habit_\(i)_body", comment: ""))
        }
    }

    /// Goal-motivated templates loaded from localizable strings.
    /// {name}, {emoji}, and {goal} are substituted at schedule time.
    private static var goalTemplates: [(title: String, body: String)] {
        (0..<10).map { i in
            (NSLocalizedString("smart_goal_\(i)_title", comment: ""),
             NSLocalizedString("smart_goal_\(i)_body", comment: ""))
        }
    }

    /// Schedule (or reschedule) smart reminders based on the given habit list and frequency.
    /// Cancels any previously scheduled smart reminders first.
    /// For 4× and 5× frequencies, the extra slots (index ≥ 3) use goal-motivated messaging.
    func scheduleSmartReminders(habits: [Habit], frequency: Int) async {
        // Cancel existing smart reminders
        await cancelSmartReminders()

        guard isAuthorized, !habits.isEmpty else { return }

        let activeHabits = habits.filter { $0.isActive }
        guard !activeHabits.isEmpty else { return }

        // Determine trigger hours based on frequency.
        // For 4× and 5×, the first 3 hours mirror the 3× schedule; extra hours get goal nudges.
        let hours: [Int]
        switch frequency {
        case 1:  hours = [19]                       // 7 pm
        case 3:  hours = [9, 14, 19]               // 9 am, 2 pm, 7 pm
        case 4:  hours = [9, 14, 19, 20]           // base 3× + goal nudge at 8 pm
        case 5:  hours = [9, 14, 19, 17, 20]       // base 3× + goal nudges at 5 pm & 8 pm
        default: hours = [9, 19]                   // 9 am, 7 pm (frequency == 2)
        }

        // Slots at index ≥ 3 use goal-motivated templates (for 4× and 5×)
        let goalSlotStart = 3

        // Random starting offset so templates rotate differently on each reschedule
        let msgOffset = Int.random(in: 0..<Self.messageTemplates.count)
        let goalOffset = Int.random(in: 0..<Self.goalTemplates.count)

        for (slotIndex, hour) in hours.enumerated() {
            // Pick a habit for this slot, rotating through active habits
            let habit = activeHabits[slotIndex % activeHabits.count]
            let emoji = habit.emoji ?? "✨"
            let name = habit.name

            let title: String
            let body: String

            if frequency >= 4, slotIndex >= goalSlotStart {
                // Goal-motivated slot: use the habit's goal name if available
                let goalName = habit.goal?.name ?? name
                let idx = (goalOffset + (slotIndex - goalSlotStart)) % Self.goalTemplates.count
                let tmpl = Self.goalTemplates[idx]
                title = tmpl.title
                    .replacingOccurrences(of: "{emoji}", with: emoji)
                    .replacingOccurrences(of: "{name}", with: name)
                    .replacingOccurrences(of: "{goal}", with: goalName)
                body = tmpl.body
                    .replacingOccurrences(of: "{emoji}", with: emoji)
                    .replacingOccurrences(of: "{name}", with: name)
                    .replacingOccurrences(of: "{goal}", with: goalName)
            } else {
                // Regular habit-name slot
                let idx = (msgOffset + slotIndex) % Self.messageTemplates.count
                let tmpl = Self.messageTemplates[idx]
                title = tmpl.title
                    .replacingOccurrences(of: "{emoji}", with: emoji)
                    .replacingOccurrences(of: "{name}", with: name)
                body = tmpl.body
                    .replacingOccurrences(of: "{emoji}", with: emoji)
                    .replacingOccurrences(of: "{name}", with: name)
            }

            let content = UNMutableNotificationContent()
            content.title = title
            content.body = body
            content.sound = .default

            var components = DateComponents()
            components.hour = hour
            components.minute = 0
            let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: true)

            let identifier = "\(Self.smartReminderPrefix)\(hour)"
            let request = UNNotificationRequest(identifier: identifier, content: content, trigger: trigger)

            do {
                try await notificationCenter.add(request)
            } catch {
                print("Smart reminder scheduling error: \(error)")
            }
        }
    }

    /// Cancel all currently scheduled smart reminders.
    func cancelSmartReminders() async {
        let pending = await notificationCenter.pendingNotificationRequests()
        let smartIDs = pending
            .map { $0.identifier }
            .filter { $0.hasPrefix(Self.smartReminderPrefix) }
        notificationCenter.removePendingNotificationRequests(withIdentifiers: smartIDs)
    }

    // MARK: - Template Helpers (used by debug menu)

    static func randomHabitTemplate(name: String, emoji: String) -> (String, String) {
        let tmpl = messageTemplates.randomElement()!
        return (
            tmpl.title.replacingOccurrences(of: "{emoji}", with: emoji).replacingOccurrences(of: "{name}", with: name),
            tmpl.body.replacingOccurrences(of: "{emoji}", with: emoji).replacingOccurrences(of: "{name}", with: name)
        )
    }

    static func randomGoalTemplate(name: String, emoji: String, goal: String) -> (String, String) {
        let tmpl = goalTemplates.randomElement()!
        return (
            tmpl.title.replacingOccurrences(of: "{emoji}", with: emoji).replacingOccurrences(of: "{name}", with: name).replacingOccurrences(of: "{goal}", with: goal),
            tmpl.body.replacingOccurrences(of: "{emoji}", with: emoji).replacingOccurrences(of: "{name}", with: name).replacingOccurrences(of: "{goal}", with: goal)
        )
    }

    // MARK: - Re-engagement Notifications

    private static let reEngagementIdentifier = "re-engagement-inactivity"
    static let reEngagementDays: TimeInterval = 3 * 24 * 3600  // 3 days

    /// Schedule a re-engagement notification to fire `reEngagementDays` from now.
    /// Cancels any previously scheduled one first so there is always at most one pending.
    static func scheduleReEngagementNotification(habitNames: [String], goalNames: [String]) {
        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: [reEngagementIdentifier])

        let content = UNMutableNotificationContent()

        let allNames = (habitNames + goalNames).prefix(2)
        let (title, body) = reEngagementTemplate(habits: habitNames, goals: goalNames)
        content.title = title
        content.body = body
        _ = allNames  // used indirectly via template
        content.sound = .default

        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: reEngagementDays, repeats: false)
        let request = UNNotificationRequest(identifier: reEngagementIdentifier, content: content, trigger: trigger)
        center.add(request)
    }

    /// Cancel any pending re-engagement notification (call when app becomes active).
    static func cancelReEngagementNotification() {
        UNUserNotificationCenter.current()
            .removePendingNotificationRequests(withIdentifiers: [reEngagementIdentifier])
    }

    private static func reEngagementTemplate(habits: [String], goals: [String]) -> (title: String, body: String) {
        let templates: [(title: String, body: String)] = [
            (NSLocalizedString("reengagement_0_title", comment: ""),
             NSLocalizedString("reengagement_0_body", comment: "")),
            (NSLocalizedString("reengagement_1_title", comment: ""),
             NSLocalizedString("reengagement_1_body", comment: "")),
            (NSLocalizedString("reengagement_2_title", comment: ""),
             NSLocalizedString("reengagement_2_body", comment: "")),
            (NSLocalizedString("reengagement_3_title", comment: ""),
             NSLocalizedString("reengagement_3_body", comment: "")),
            (NSLocalizedString("reengagement_4_title", comment: ""),
             NSLocalizedString("reengagement_4_body", comment: "")),
            (NSLocalizedString("reengagement_5_title", comment: ""),
             NSLocalizedString("reengagement_5_body", comment: "")),
            (NSLocalizedString("reengagement_6_title", comment: ""),
             NSLocalizedString("reengagement_6_body", comment: "")),
        ]
        let tmpl = templates.randomElement()!
        let habitLine = habits.prefix(2).joined(separator: " & ")
        let goalLine = goals.first ?? habitLine
        let name = goalLine.isEmpty ? "your habits" : goalLine
        let title = tmpl.title.replacingOccurrences(of: "{habit}", with: name)
        let body = tmpl.body.replacingOccurrences(of: "{habit}", with: name)
        return (title, body)
    }

    private static var challengeDoneTemplates: [(title: String, body: String)] {
        (0..<7).map { i in
            (NSLocalizedString("challenge_done_\(i)_title", comment: ""),
             NSLocalizedString("challenge_done_\(i)_body", comment: ""))
        }
    }

    /// Schedule a local notification for when a challenge partner completes their daily task.
    static func scheduleChallengeDoneNotification(partnerName: String) {
        let tmpl = challengeDoneTemplates.randomElement()!
        let title = tmpl.title.replacingOccurrences(of: "{partner}", with: partnerName)
        let body = tmpl.body.replacingOccurrences(of: "{partner}", with: partnerName)

        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        content.badge = 1

        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 1, repeats: false)
        let id = "challenge-done-\(partnerName)-\(Date().timeIntervalSince1970)"
        let request = UNNotificationRequest(identifier: id, content: content, trigger: trigger)

        UNUserNotificationCenter.current().add(request)
    }
}

// MARK: - Habit Extension for Notifications

extension Habit {
    /// Schedule notifications for this habit
    @MainActor
    func scheduleNotifications() async {
        await NotificationManager.shared.scheduleNotifications(for: self)
    }

    /// Cancel notifications for this habit
    @MainActor
    func cancelNotifications() async {
        await NotificationManager.shared.cancelNotifications(for: self)
    }
}
