//
//  ProgressTracker.swift
//  Stick
//
//  Universal progress tracking for the entire app.
//  This ensures consistency across main progress ring, calendar, analytics, and streaks.
//

import Foundation

/// Universal progress tracker that provides consistent progress calculations across the app.
///
/// Rules:
/// - Only "daily-type" habits count toward progress: daily, specific-day weekly, custom interval
/// - Flexible weekly (X times per week) and monthly habits do NOT count toward progress
/// - Progress is calculated as: completed daily-type habits / scheduled daily-type habits
/// - Streak is simply: consecutive days with 100% progress
struct ProgressTracker {

    /// Filters habits to only those that count toward daily progress.
    /// These are habits with fixed schedules: daily, specific-day weekly, custom interval.
    /// Excludes flexible weekly and monthly habits.
    static func dailyTypeHabits(from habits: [Habit]) -> [Habit] {
        habits.filter { habit in
            switch habit.frequency {
            case .daily:
                return true
            case .weekly:
                // Only specific-day weekly counts, NOT flexible (X times per week)
                return habit.usesSpecificDays
            case .monthly:
                // Monthly never counts toward daily progress
                return false
            case .customInterval:
                return true
            }
        }
    }

    /// Habits scheduled for a specific date (only daily-type habits).
    /// These are the habits that should be completed on this specific day.
    static func scheduledHabits(from habits: [Habit], for date: Date) -> [Habit] {
        let calendar = Calendar.current
        let dateStart = calendar.startOfDay(for: date)

        return dailyTypeHabits(from: habits).filter { habit in
            let createdStart = calendar.startOfDay(for: habit.createdDate)
            return habit.isScheduled(for: date) && createdStart <= dateStart
        }
    }

    /// Calculate progress for a specific date.
    /// Returns: average of all habit progress values (0.0 to 1.0, capped)
    /// Returns -1 if no habits are scheduled (indicates "no data" for that day)
    /// Uses partial completion: count-based habits contribute their partial progress (e.g., 3/5 = 0.6)
    /// Progress is capped at 1.0 - over-completion doesn't exceed 100%
    static func progress(for date: Date, habits: [Habit]) -> Double {
        let scheduled = scheduledHabits(from: habits, for: date)
        guard !scheduled.isEmpty else { return -1 }

        let totalProgress = scheduled.reduce(0.0) { sum, habit in
            sum + habitProgress(habit, for: date)
        }
        return min(1.0, totalProgress / Double(scheduled.count))
    }

    /// Get progress for a single habit (0.0 to 1.0, capped).
    /// For count-based habits: returns partial progress (e.g., 3/5 = 0.6), capped at 1.0
    /// For binary habits: returns 1.0 if completed, 0.0 otherwise
    static func habitProgress(_ habit: Habit, for date: Date) -> Double {
        if habit.hasTargetCount {
            return min(1.0, habit.progress(for: date))
        } else {
            return habit.isCompleted(for: date) ? 1.0 : 0.0
        }
    }

    /// Check if a habit is fully complete for a date.
    /// For habits with targetCount, checks if target is reached.
    /// For binary habits, checks if any completion exists.
    private static func isHabitComplete(_ habit: Habit, for date: Date) -> Bool {
        if habit.hasTargetCount {
            return habit.isTargetReached(for: date)
        } else {
            return habit.isCompleted(for: date)
        }
    }

    /// Check if a day meets the completion threshold for streak counting.
    /// Returns true if no habits are scheduled (empty day doesn't break streak).
    /// - Parameter threshold: Minimum completion percentage (0.0-1.0), default 1.0 (100%)
    static func isDayComplete(for date: Date, habits: [Habit], threshold: Double = 1.0) -> Bool {
        let scheduled = scheduledHabits(from: habits, for: date)
        guard !scheduled.isEmpty else { return true } // No habits scheduled = complete

        let dayProgress = progress(for: date, habits: habits)
        return dayProgress >= threshold
    }

    /// Calculate overall streak (consecutive days meeting completion threshold).
    /// Skipped dates don't break the streak.
    /// - Parameter skippedDates: Set of dates that were skipped and don't break the streak
    /// - Parameter threshold: Minimum completion percentage required (0.0-1.0), default 1.0 (100%)
    static func calculateStreak(habits: [Habit], skippedDates: Set<Date> = [], threshold: Double = 1.0) -> Int {
        guard !habits.isEmpty else { return 0 }

        let dailyHabits = dailyTypeHabits(from: habits)
        guard !dailyHabits.isEmpty else { return 0 }

        let calendar = Calendar.current
        var streak = 0
        var checkDate = Date()
        let maxDaysToCheck = 365
        let today = calendar.startOfDay(for: Date())

        // Get earliest habit creation date
        let earliestCreation = habits.compactMap { $0.createdDate }.min() ?? Date()

        // Check if today is skipped
        if skippedDates.contains(today) {
            guard let yesterday = calendar.date(byAdding: .day, value: -1, to: checkDate) else {
                return 0
            }
            checkDate = yesterday
        } else {
            // Check if today meets the threshold
            let todayComplete = isDayComplete(for: checkDate, habits: habits, threshold: threshold)

            if !todayComplete {
                // Today isn't complete, start checking from yesterday
                guard let yesterday = calendar.date(byAdding: .day, value: -1, to: checkDate) else {
                    return 0
                }
                checkDate = yesterday
            }
        }

        // Count consecutive complete days
        for _ in 0..<maxDaysToCheck {
            // Stop if we've gone before any habit was created
            if checkDate < earliestCreation { break }

            let checkDayStart = calendar.startOfDay(for: checkDate)

            // If this day is skipped, skip over it without breaking streak
            if skippedDates.contains(checkDayStart) {
                guard let previousDay = calendar.date(byAdding: .day, value: -1, to: checkDate) else { break }
                checkDate = previousDay
                continue
            }

            let scheduled = scheduledHabits(from: habits, for: checkDate)

            if scheduled.isEmpty {
                // No habits scheduled this day - doesn't break streak, just skip
                guard let previousDay = calendar.date(byAdding: .day, value: -1, to: checkDate) else { break }
                checkDate = previousDay
                continue
            }

            if isDayComplete(for: checkDate, habits: habits, threshold: threshold) {
                streak += 1
            } else {
                break // Day below threshold breaks the streak
            }

            guard let previousDay = calendar.date(byAdding: .day, value: -1, to: checkDate) else { break }
            checkDate = previousDay
        }

        return streak
    }

    /// Check if a specific date has been skipped
    static func isDateSkipped(_ date: Date, skippedDates: Set<Date>) -> Bool {
        let calendar = Calendar.current
        let dayStart = calendar.startOfDay(for: date)
        return skippedDates.contains(dayStart)
    }

    /// Get flexible/timeframe habits (weekly flexible + monthly) - shown in separate section
    static func timeframeHabits(from habits: [Habit]) -> [Habit] {
        habits.filter { habit in
            (habit.frequency == .weekly && habit.isFlexibleWeekly) || habit.frequency == .monthly
        }
    }

    // MARK: - Weekly Time Spent

    /// Total time spent on habits this week (in seconds).
    /// Only counts completed timer habits at their full target duration.
    static func weeklyTimeSpent(habits: [Habit]) -> TimeInterval {
        let calendar = Calendar.current
        guard let weekInterval = calendar.dateInterval(of: .weekOfYear, for: Date()) else { return 0 }
        let weekStart = weekInterval.start

        return habits.reduce(0) { total, habit in
            guard habit.isTimerBased, let duration = habit.duration else { return total }
            let weekCompletions = habit.safeCompletions.filter { $0.completionDate >= weekStart }
            return total + (TimeInterval(weekCompletions.count) * duration)
        }
    }

    /// Weekly time spent formatted as readable string (e.g., "2h", "45m").
    static func formattedWeeklyTime(habits: [Habit]) -> String {
        let totalMinutes = Int(weeklyTimeSpent(habits: habits)) / 60
        if totalMinutes >= 60 {
            let hours = (totalMinutes + 30) / 60 // Round to nearest hour
            return "\(hours)h"
        } else if totalMinutes > 0 {
            return "\(totalMinutes)m"
        } else {
            return "0m"
        }
    }

    /// Weekly time spent in hours (as Double for display).
    static func weeklyHoursSpent(habits: [Habit]) -> Double {
        weeklyTimeSpent(habits: habits) / 3600.0
    }
}
