//
//  WeeklyWrap.swift
//  Stick
//
//  Weekly wrap model for storing Instagram-style weekly habit stats.
//

import Foundation
import SwiftData

@Model
final class WeeklyWrap {
    // MARK: - Properties

    var id: UUID = UUID()
    var weekStartDate: Date = Date()           // Monday of the week
    var weekEndDate: Date = Date()             // Sunday of the week
    var createdDate: Date = Date()
    var isDismissed: Bool = false
    var isViewed: Bool = false

    // MARK: - Aggregated Stats

    var totalCompletions: Int = 0
    var completionRate: Double = 0.0        // 0.0 - 1.0
    var perfectDays: Int = 0              // Days with 100% completion
    var bestStreak: Int = 0
    var totalMinutesTracked: Int = 0
    var mostConsistentHabitId: UUID?
    var mostConsistentHabitName: String?
    var improvementFromLastWeek: Double?  // e.g., 0.1 = 10% better

    // MARK: - Additional Stats

    var totalHabitsTracked: Int = 0
    var totalScheduledCompletions: Int = 0

    // MARK: - Highlight Day

    var highlightDayDate: Date?
    var highlightDayCompletions: Int?
    var highlightDayReason: String?  // e.g., "best_day", "exceeded_goal", "longest_session"

    // MARK: - Initialization

    init(
        weekStartDate: Date,
        weekEndDate: Date,
        totalCompletions: Int = 0,
        completionRate: Double = 0.0,
        perfectDays: Int = 0,
        bestStreak: Int = 0,
        totalMinutesTracked: Int = 0,
        mostConsistentHabitId: UUID? = nil,
        mostConsistentHabitName: String? = nil,
        improvementFromLastWeek: Double? = nil,
        totalHabitsTracked: Int = 0,
        totalScheduledCompletions: Int = 0,
        highlightDayDate: Date? = nil,
        highlightDayCompletions: Int? = nil,
        highlightDayReason: String? = nil
    ) {
        self.id = UUID()
        self.weekStartDate = weekStartDate
        self.weekEndDate = weekEndDate
        self.createdDate = Date()
        self.isDismissed = false
        self.isViewed = false
        self.totalCompletions = totalCompletions
        self.completionRate = completionRate
        self.perfectDays = perfectDays
        self.bestStreak = bestStreak
        self.totalMinutesTracked = totalMinutesTracked
        self.mostConsistentHabitId = mostConsistentHabitId
        self.mostConsistentHabitName = mostConsistentHabitName
        self.improvementFromLastWeek = improvementFromLastWeek
        self.totalHabitsTracked = totalHabitsTracked
        self.totalScheduledCompletions = totalScheduledCompletions
        self.highlightDayDate = highlightDayDate
        self.highlightDayCompletions = highlightDayCompletions
        self.highlightDayReason = highlightDayReason
    }

    // MARK: - Computed Properties

    /// Formatted date range string (e.g., "Feb 10-16")
    var dateRangeString: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM d"
        let start = formatter.string(from: weekStartDate)
        formatter.dateFormat = "d"
        let end = formatter.string(from: weekEndDate)
        return "\(start)-\(end)"
    }

    /// Formatted completion rate as percentage
    var completionRatePercent: Int {
        Int(completionRate * 100)
    }

    /// Formatted time tracked
    var formattedTimeTracked: String {
        let hours = totalMinutesTracked / 60
        let minutes = totalMinutesTracked % 60
        if hours > 0 {
            return minutes > 0 ? "\(hours)h \(minutes)m" : "\(hours)h"
        }
        return "\(minutes)m"
    }

    /// Summary message based on completion rate
    var summaryMessage: String {
        if completionRate >= 0.9 {
            return String(localized: "weekly_wrap_summary_great")
        } else if completionRate >= 0.7 {
            return String(localized: "weekly_wrap_summary_good")
        } else if completionRate >= 0.5 {
            return String(localized: "weekly_wrap_summary_keep_going")
        } else {
            return String(localized: "weekly_wrap_summary_new_week")
        }
    }

    /// Summary emoji based on completion rate
    var summaryEmoji: String {
        if completionRate >= 0.9 {
            return "🎉"
        } else if completionRate >= 0.7 {
            return "💪"
        } else if completionRate >= 0.5 {
            return "👍"
        } else {
            return "🌱"
        }
    }

    /// Formatted highlight day name (e.g., "Wednesday")
    var highlightDayName: String? {
        guard let date = highlightDayDate else { return nil }
        let formatter = DateFormatter()
        formatter.dateFormat = "EEEE"
        return formatter.string(from: date)
    }

    /// Whether there's a meaningful comparison to last week
    var hasComparison: Bool {
        improvementFromLastWeek != nil
    }

    /// Personal message based on improvement
    var comparisonMessage: String {
        guard let improvement = improvementFromLastWeek else {
            return String(localized: "weekly_wrap_first_week")
        }

        if improvement >= 0.2 {
            return String(localized: "weekly_wrap_huge_improvement")
        } else if improvement >= 0.1 {
            return String(localized: "weekly_wrap_solid_improvement")
        } else if improvement >= 0 {
            return String(localized: "weekly_wrap_steady_progress")
        } else if improvement >= -0.1 {
            return String(localized: "weekly_wrap_slight_dip")
        } else {
            return String(localized: "weekly_wrap_tough_week")
        }
    }
}
