//
//  Habit.swift
//  Stick
//
//  Created by Kian Jain on 02.02.26.
//

import Foundation
import SwiftData

// MARK: - HealthKitDataType Enum

enum HealthKitDataType: String, Codable, CaseIterable {
    case steps = "steps"
    case calories = "calories"
    case distance = "distance"
    case workouts = "workouts"

    var displayName: String {
        switch self {
        case .steps:
            return "Steps"
        case .calories:
            return "Calories"
        case .distance:
            return "Distance"
        case .workouts:
            return "Workouts"
        }
    }

    var localizedName: String {
        switch self {
        case .steps:
            return String(localized: "healthkit_steps")
        case .calories:
            return String(localized: "healthkit_calories")
        case .distance:
            return String(localized: "healthkit_distance")
        case .workouts:
            return String(localized: "healthkit_workouts")
        }
    }

    var unit: String {
        switch self {
        case .steps:
            return "steps"
        case .calories:
            return "cal"
        case .distance:
            return "km"
        case .workouts:
            return "workouts"
        }
    }

    var systemImage: String {
        switch self {
        case .steps:
            return "figure.walk"
        case .calories:
            return "flame.fill"
        case .distance:
            return "figure.run"
        case .workouts:
            return "dumbbell.fill"
        }
    }
}

// MARK: - HealthKitDataType Target Helpers

extension HealthKitDataType {
    var defaultTarget: Double {
        switch self {
        case .steps: return 10000
        case .calories: return 500
        case .distance: return 5.0
        case .workouts: return 1
        }
    }

    var targetRange: ClosedRange<Double> {
        switch self {
        case .steps: return 1000...30000
        case .calories: return 100...2000
        case .distance: return 1.0...30.0
        case .workouts: return 1...5
        }
    }

    var targetStep: Double {
        switch self {
        case .steps: return 1000
        case .calories: return 50
        case .distance: return 0.5
        case .workouts: return 1
        }
    }

    var targetPresets: [Double] {
        switch self {
        case .steps: return [5000, 7500, 10000, 15000]
        case .calories: return [300, 500, 750, 1000]
        case .distance: return [3, 5, 8, 10]
        case .workouts: return [1, 2, 3]
        }
    }

    func formatTarget(_ value: Double) -> String {
        switch self {
        case .steps, .calories, .workouts: return String(Int(value))
        case .distance: return String(format: "%.1f", value)
        }
    }
}

// MARK: - HabitFrequency Enum

enum HabitFrequency: String, Codable, CaseIterable {
    case daily = "daily"
    case weekly = "weekly"
    case monthly = "monthly"
    case customInterval = "customInterval"

    var displayName: String {
        switch self {
        case .daily:
            return "Daily"
        case .weekly:
            return "Weekly"
        case .monthly:
            return "Monthly"
        case .customInterval:
            return "Custom Interval"
        }
    }

    var localizedName: String {
        switch self {
        case .daily:
            return String(localized: "frequency_daily")
        case .weekly:
            return String(localized: "frequency_weekly")
        case .monthly:
            return String(localized: "frequency_monthly")
        case .customInterval:
            return String(localized: "frequency_custom_interval")
        }
    }
}

// MARK: - Weekday Enum

/// Weekday values matching Apple's Calendar.component(.weekday) convention.
/// Use these instead of magic numbers for better readability.
enum Weekday: Int, CaseIterable, Identifiable {
    case sunday = 1
    case monday = 2
    case tuesday = 3
    case wednesday = 4
    case thursday = 5
    case friday = 6
    case saturday = 7

    var id: Int { rawValue }

    var shortName: String {
        switch self {
        case .sunday: return "Sun"
        case .monday: return "Mon"
        case .tuesday: return "Tue"
        case .wednesday: return "Wed"
        case .thursday: return "Thu"
        case .friday: return "Fri"
        case .saturday: return "Sat"
        }
    }

    var fullName: String {
        switch self {
        case .sunday: return "Sunday"
        case .monday: return "Monday"
        case .tuesday: return "Tuesday"
        case .wednesday: return "Wednesday"
        case .thursday: return "Thursday"
        case .friday: return "Friday"
        case .saturday: return "Saturday"
        }
    }

    /// Returns weekdays ordered starting from Monday (common preference)
    static var weekdaysFromMonday: [Weekday] {
        [.monday, .tuesday, .wednesday, .thursday, .friday, .saturday, .sunday]
    }
}

// MARK: - Habit Model

@Model
final class Habit {
    // MARK: - Basic Info

    var id: UUID = UUID()
    var name: String = ""
    var habitDescription: String?
    var color: String = "#007AFF" // Hex color (e.g., "#FF5733")
    var symbolName: String? // SF Symbol name
    var emoji: String? // Alternative to symbol
    var createdDate: Date = Date()
    var isActive: Bool = true
    var sortOrder: Int = 0

    // MARK: - Scheduling

    /// Frequency type for this habit
    var frequencyRawValue: String = "daily"

    /// Days of the week for specificDays frequency.
    /// Uses Apple's Calendar weekday convention: 1 = Sunday, 2 = Monday, ..., 7 = Saturday.
    /// This matches Calendar.component(.weekday, from:) for consistency.
    /// Stored as comma-separated string for SwiftData compatibility.
    var scheduledDaysData: String?

    /// Times of day for reminders, stored as seconds from midnight.
    /// When accessed via `scheduledTimes`, returns Date objects where only the time
    /// component (hour, minute, second) is meaningful - the date portion should be ignored.
    /// Stored as comma-separated string for SwiftData compatibility.
    var scheduledTimesData: String?

    /// Interval in days for everyXDays frequency (e.g., 2 = every 2 days)
    var customInterval: Int?

    /// Target duration in seconds for timer-based habits (nil = quick complete)
    var duration: TimeInterval?

    /// Target count for partial completion habits (e.g., 8 glasses of water)
    /// If nil, habit is binary (done/not done)
    var targetCount: Int?

    /// Number of times to complete per week for flexible weekly habits (1-7)
    /// If nil and frequency is weekly, uses scheduledDays for specific day tracking
    var weeklyRepetitions: Int?

    /// Number of times to complete per month for monthly habits (1-31)
    var monthlyRepetitions: Int?

    // MARK: - Notifications

    var notificationsEnabled: Bool = true
    var reminderMessage: String?

    // MARK: - HealthKit Integration

    /// The HealthKit data type linked to this habit (e.g., "steps", "calories")
    var healthKitType: String?

    /// Whether to auto-complete the habit based on HealthKit data
    var healthKitAutoComplete: Bool = false

    // MARK: - Relationships

    @Relationship(inverse: \Goal.habits)
    var goal: Goal?

    @Relationship(deleteRule: .cascade, inverse: \HabitCompletion.habit)
    var completions: [HabitCompletion]?

    /// Safe accessor for completions that returns empty array if nil
    var safeCompletions: [HabitCompletion] {
        get { completions ?? [] }
        set { completions = newValue }
    }

    // MARK: - Computed Properties

    var frequency: HabitFrequency {
        get { HabitFrequency(rawValue: frequencyRawValue) ?? .daily }
        set { frequencyRawValue = newValue.rawValue }
    }

    /// Weekday indices when habit is scheduled.
    /// Uses Apple's Calendar weekday convention: 1 = Sunday, 2 = Monday, ..., 7 = Saturday.
    /// Example: [2, 4, 6] = Monday, Wednesday, Friday
    var scheduledDays: [Int] {
        get {
            guard let data = scheduledDaysData, !data.isEmpty else { return [] }
            return data.split(separator: ",").compactMap { Int($0) }
        }
        set {
            scheduledDaysData = newValue.map { String($0) }.joined(separator: ",")
        }
    }

    /// Times of day for reminders.
    /// Returns Date objects where only the time component (hour, minute, second) is meaningful.
    /// The date portion is always "today" and should be ignored when comparing or displaying.
    var scheduledTimes: [Date] {
        get {
            guard let data = scheduledTimesData, !data.isEmpty else { return [] }
            return data.split(separator: ",").compactMap { interval in
                guard let timeInterval = TimeInterval(interval) else { return nil }
                return Calendar.current.startOfDay(for: Date()).addingTimeInterval(timeInterval)
            }
        }
        set {
            let calendar = Calendar.current
            scheduledTimesData = newValue.map { date in
                let startOfDay = calendar.startOfDay(for: date)
                return String(date.timeIntervalSince(startOfDay))
            }.joined(separator: ",")
        }
    }

    /// Whether this habit uses a timer for completion
    var isTimerBased: Bool {
        duration != nil && duration! > 0
    }

    /// Display icon - prefers emoji over SF Symbol
    var displayIcon: String {
        if let emoji = emoji, !emoji.isEmpty {
            return emoji
        }
        return symbolName ?? "checkmark.circle"
    }

    /// Whether this habit has a target count (partial completion)
    var hasTargetCount: Bool {
        targetCount != nil && targetCount! > 1
    }

    /// Whether weekly habit uses flexible repetitions (vs specific days)
    var isFlexibleWeekly: Bool {
        frequency == .weekly && weeklyRepetitions != nil
    }

    /// Whether weekly habit uses specific days
    var usesSpecificDays: Bool {
        frequency == .weekly && !scheduledDays.isEmpty && weeklyRepetitions == nil
    }

    /// Whether this habit is linked to HealthKit
    var isHealthKitLinked: Bool {
        healthKitType != nil && !healthKitType!.isEmpty
    }

    /// Get the HealthKit data type enum value
    var healthKitDataType: HealthKitDataType? {
        get {
            guard let type = healthKitType else { return nil }
            return HealthKitDataType(rawValue: type)
        }
        set {
            healthKitType = newValue?.rawValue
        }
    }

    /// Get current count for a specific date (sum of all completion counts)
    func currentCount(for date: Date) -> Int {
        completions(for: date).reduce(0) { $0 + $1.count }
    }

    /// Count fully completed days in current week
    /// For count-based habits (including HealthKit), only counts days where target was reached
    func completionsThisWeek() -> Int {
        let calendar = Calendar.current
        guard let weekStart = calendar.date(from: calendar.dateComponents([.yearForWeekOfYear, .weekOfYear], from: Date())) else {
            return 0
        }

        // For count-based habits, count days where target was reached
        if hasTargetCount {
            var count = 0
            var checkDate = weekStart
            while checkDate <= Date() {
                if isFullyCompleted(for: checkDate) {
                    count += 1
                }
                guard let nextDay = calendar.date(byAdding: .day, value: 1, to: checkDate) else { break }
                checkDate = nextDay
            }
            return count
        }

        // For binary habits, count raw completion records
        return safeCompletions.filter { $0.completionDate >= weekStart }.count
    }

    /// Count fully completed days in current month
    /// For count-based habits (including HealthKit), only counts days where target was reached
    func completionsThisMonth() -> Int {
        let calendar = Calendar.current
        let currentMonth = calendar.component(.month, from: Date())
        let currentYear = calendar.component(.year, from: Date())

        // For count-based habits, count days where target was reached
        if hasTargetCount {
            var count = 0
            guard let monthStart = calendar.date(from: calendar.dateComponents([.year, .month], from: Date())) else {
                return 0
            }
            var checkDate = monthStart
            while checkDate <= Date() {
                if isFullyCompleted(for: checkDate) {
                    count += 1
                }
                guard let nextDay = calendar.date(byAdding: .day, value: 1, to: checkDate) else { break }
                checkDate = nextDay
            }
            return count
        }

        // For binary habits, count raw completion records
        return safeCompletions.filter { completion in
            let month = calendar.component(.month, from: completion.completionDate)
            let year = calendar.component(.year, from: completion.completionDate)
            return month == currentMonth && year == currentYear
        }.count
    }

    /// Progress towards target for a specific date (0.0 - 1.0)
    func progress(for date: Date) -> Double {
        guard let target = targetCount, target > 0 else {
            return isCompleted(for: date) ? 1.0 : 0.0
        }
        return min(1.0, Double(currentCount(for: date)) / Double(target))
    }

    /// Whether target count is reached for a specific date
    func isTargetReached(for date: Date) -> Bool {
        guard let target = targetCount else {
            return isCompleted(for: date)
        }
        return currentCount(for: date) >= target
    }

    // MARK: - Initialization

    init(
        name: String,
        description: String? = nil,
        color: String = "#007AFF",
        symbolName: String? = nil,
        emoji: String? = nil,
        frequency: HabitFrequency = .daily,
        scheduledDays: [Int] = [],
        scheduledTimes: [Date] = [],
        customInterval: Int? = nil,
        duration: TimeInterval? = nil,
        targetCount: Int? = nil,
        weeklyRepetitions: Int? = nil,
        monthlyRepetitions: Int? = nil,
        notificationsEnabled: Bool = true,
        reminderMessage: String? = nil,
        goal: Goal? = nil,
        healthKitType: String? = nil,
        healthKitAutoComplete: Bool = false
    ) {
        self.id = UUID()
        self.name = name
        self.habitDescription = description
        self.color = color
        self.symbolName = symbolName
        self.emoji = emoji
        self.createdDate = Date()
        self.isActive = true
        self.sortOrder = Int(Date().timeIntervalSince1970)
        self.frequencyRawValue = frequency.rawValue
        self.customInterval = customInterval
        self.duration = duration
        self.targetCount = targetCount
        self.weeklyRepetitions = weeklyRepetitions
        self.monthlyRepetitions = monthlyRepetitions
        self.notificationsEnabled = notificationsEnabled
        self.reminderMessage = reminderMessage
        self.goal = goal
        self.completions = []
        self.healthKitType = healthKitType
        self.healthKitAutoComplete = healthKitAutoComplete

        // Set computed properties via their setters
        self.scheduledDays = scheduledDays
        self.scheduledTimes = scheduledTimes
    }
}

// MARK: - Habit Scheduling Helpers

extension Habit {
    /// Check if the habit is scheduled for a given date.
    /// For weekly/monthly without specific days, this returns true (flexible scheduling).
    func isScheduled(for date: Date) -> Bool {
        let calendar = Calendar.current

        switch frequency {
        case .daily:
            return true

        case .weekly:
            // If specific days are set, only scheduled on those days
            // Otherwise, flexible weekly - scheduled every day (complete anytime)
            if !scheduledDays.isEmpty {
                let weekday = calendar.component(.weekday, from: date)
                return scheduledDays.contains(weekday)
            }
            return true // Flexible weekly

        case .monthly:
            // Monthly is always "scheduled" - can complete any day
            return true

        case .customInterval:
            guard let interval = customInterval, interval > 0 else { return true }
            let daysSinceCreation = calendar.dateComponents([.day], from: createdDate, to: date).day ?? 0
            return daysSinceCreation >= 0 && daysSinceCreation % interval == 0
        }
    }

    /// Check if weekly habit met its goal this week
    func isWeeklyGoalMet() -> Bool {
        guard frequency == .weekly else { return false }

        if let reps = weeklyRepetitions {
            // Flexible weekly: check if completed enough times
            return completionsThisWeek() >= reps
        } else if usesSpecificDays {
            // Specific days: all scheduled days this week must be completed
            // For simplicity, just check today if it's a scheduled day
            return isCompleted(for: Date())
        } else {
            // Default: at least one completion this week
            return completionsThisWeek() > 0
        }
    }

    /// Check if monthly habit met its goal this month
    func isMonthlyGoalMet() -> Bool {
        guard frequency == .monthly else { return false }

        if let reps = monthlyRepetitions {
            return completionsThisMonth() >= reps
        } else {
            // Default: at least one completion this month
            return completionsThisMonth() > 0
        }
    }

    /// Progress towards weekly goal (0.0 - 1.0)
    func weeklyProgress() -> Double {
        guard frequency == .weekly, let reps = weeklyRepetitions, reps > 0 else {
            return isWeeklyGoalMet() ? 1.0 : 0.0
        }
        return min(1.0, Double(completionsThisWeek()) / Double(reps))
    }

    /// Progress towards monthly goal (0.0 - 1.0)
    func monthlyProgress() -> Double {
        guard frequency == .monthly, let reps = monthlyRepetitions, reps > 0 else {
            return isMonthlyGoalMet() ? 1.0 : 0.0
        }
        return min(1.0, Double(completionsThisMonth()) / Double(reps))
    }

    /// Smart completion check based on frequency
    func isEffectivelyCompleted(for date: Date = Date()) -> Bool {
        switch frequency {
        case .daily, .customInterval:
            return isCompleted(for: date)
        case .weekly:
            if usesSpecificDays {
                return isCompleted(for: date)
            }
            return isWeeklyGoalMet()
        case .monthly:
            return isMonthlyGoalMet()
        }
    }

    /// Get display text for repetition progress (e.g., "2/3 this week")
    func repetitionProgressText() -> String? {
        switch frequency {
        case .weekly:
            if let reps = weeklyRepetitions {
                return "\(completionsThisWeek())/\(reps) this week"
            }
        case .monthly:
            if let reps = monthlyRepetitions {
                return "\(completionsThisMonth())/\(reps) this month"
            }
        default:
            break
        }
        return nil
    }

    /// Get completions for a specific date
    func completions(for date: Date) -> [HabitCompletion] {
        let calendar = Calendar.current
        return safeCompletions.filter { calendar.isDate($0.completionDate, inSameDayAs: date) }
    }

    /// Check if habit is completed for a specific date
    func isCompleted(for date: Date) -> Bool {
        !completions(for: date).isEmpty
    }

    /// Calculate current streak (consecutive days completed)
    /// - Parameter skippedDates: Set of dates that were skipped and don't break the streak
    func currentStreak(skippedDates: Set<Date> = []) -> Int {
        let calendar = Calendar.current
        var streak = 0
        var checkDate = Date()
        let today = calendar.startOfDay(for: Date())

        // Check if today is skipped - if so, start from yesterday
        if skippedDates.contains(today) {
            guard let yesterday = calendar.date(byAdding: .day, value: -1, to: checkDate) else {
                return 0
            }
            checkDate = yesterday
        } else if !isFullyCompleted(for: checkDate) {
            // If not completed today, start checking from yesterday
            guard let yesterday = calendar.date(byAdding: .day, value: -1, to: checkDate) else {
                return 0
            }
            checkDate = yesterday
        }

        while true {
            let checkDayStart = calendar.startOfDay(for: checkDate)

            // If this day is skipped, skip over it without breaking streak
            if skippedDates.contains(checkDayStart) {
                guard let previousDay = calendar.date(byAdding: .day, value: -1, to: checkDate) else {
                    break
                }
                if previousDay < createdDate {
                    break
                }
                checkDate = previousDay
                continue
            }

            // Only count if habit was scheduled for this day
            if isScheduled(for: checkDate) {
                if isFullyCompleted(for: checkDate) {
                    streak += 1
                } else {
                    break
                }
            }

            guard let previousDay = calendar.date(byAdding: .day, value: -1, to: checkDate) else {
                break
            }

            // Don't count before habit was created
            if previousDay < createdDate {
                break
            }

            checkDate = previousDay
        }

        return streak
    }

    /// Check if habit is fully completed for a date.
    /// For count-based habits (including HealthKit), checks if target is reached.
    /// For binary habits, checks if any completion exists.
    func isFullyCompleted(for date: Date) -> Bool {
        if hasTargetCount {
            return isTargetReached(for: date)
        } else {
            return isCompleted(for: date)
        }
    }
}
