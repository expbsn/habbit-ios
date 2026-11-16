//
//  WeeklyWrapService.swift
//  Stick
//
//  Service for generating and managing weekly wraps.
//

import Foundation
import SwiftData
import SwiftUI
import Combine

@MainActor
class WeeklyWrapService: ObservableObject {
    static let shared = WeeklyWrapService()

    @Published var pendingWrap: WeeklyWrap?

    private init() {}

    // MARK: - Public Methods

    /// Check if a new wrap should be generated (called on app active)
    func checkForNewWrap(context: ModelContext) {
        let calendar = Calendar.current

        // Only check on Monday or later in the week
        let today = Date()
        let weekday = calendar.component(.weekday, from: today)

        // Get the start of last week (Monday of previous week)
        guard let lastWeekStart = getLastWeekMonday(from: today) else { return }
        guard let lastWeekEnd = calendar.date(byAdding: .day, value: 6, to: lastWeekStart) else { return }

        // Check if a wrap already exists for last week
        let descriptor = FetchDescriptor<WeeklyWrap>(
            predicate: #Predicate { wrap in
                wrap.weekStartDate == lastWeekStart
            }
        )

        do {
            let existingWraps = try context.fetch(descriptor)

            if let existingWrap = existingWraps.first {
                // Wrap exists - check if it should be shown
                if !existingWrap.isDismissed && !existingWrap.isViewed {
                    pendingWrap = existingWrap
                } else {
                    pendingWrap = nil
                }
            } else {
                // No wrap exists - generate one if we're past the week end
                if today > lastWeekEnd {
                    generateWrap(for: lastWeekStart, endDate: lastWeekEnd, context: context)
                }
            }
        } catch {
            print("Failed to check for weekly wrap: \(error)")
        }
    }

    /// Create a test wrap for debugging
    private func createTestWrap(context: ModelContext) {
        let calendar = Calendar.current
        let today = Date()
        let lastMonday = calendar.date(byAdding: .day, value: -7, to: today)!
        let lastSunday = calendar.date(byAdding: .day, value: -1, to: today)!
        let wednesday = calendar.date(byAdding: .day, value: -5, to: today)!

        let wrap = WeeklyWrap(
            weekStartDate: lastMonday,
            weekEndDate: lastSunday,
            totalCompletions: 28,
            completionRate: 0.85,
            perfectDays: 4,
            bestStreak: 5,
            totalMinutesTracked: 225,
            mostConsistentHabitName: "Morning Run",
            improvementFromLastWeek: 0.12,
            totalHabitsTracked: 5,
            totalScheduledCompletions: 33,
            highlightDayDate: wednesday,
            highlightDayCompletions: 6,
            highlightDayReason: "perfect_day"
        )

        pendingWrap = wrap
    }

    /// Dismiss a wrap (hide the notification card)
    func dismissWrap(_ wrap: WeeklyWrap, context: ModelContext) {
        wrap.isDismissed = true
        pendingWrap = nil
        try? context.save()
    }

    /// Mark a wrap as viewed (after opening story)
    func markAsViewed(_ wrap: WeeklyWrap, context: ModelContext) {
        wrap.isViewed = true
        try? context.save()
    }

    // MARK: - Private Methods

    /// Get Monday of last week
    private func getLastWeekMonday(from date: Date) -> Date? {
        let calendar = Calendar.current

        // Get start of current week
        guard let currentWeekStart = calendar.date(from: calendar.dateComponents([.yearForWeekOfYear, .weekOfYear], from: date)) else {
            return nil
        }

        // Go back 7 days to get start of last week
        return calendar.date(byAdding: .day, value: -7, to: currentWeekStart)
    }

    /// Generate a wrap for a specific week
    private func generateWrap(for weekStart: Date, endDate weekEnd: Date, context: ModelContext) {
        // Fetch all active habits
        let habitDescriptor = FetchDescriptor<Habit>(
            predicate: #Predicate { $0.isActive }
        )

        do {
            let habits = try context.fetch(habitDescriptor)
            guard !habits.isEmpty else { return }

            // Don't generate wrap for first week - check if earliest habit was created before the week started
            let earliestHabitDate = habits.compactMap { $0.createdDate }.min() ?? Date()
            guard earliestHabitDate < weekStart else {
                // User's first habit was created during or after this week - skip wrap
                return
            }

            let calendar = Calendar.current
            var totalCompletions = 0
            var totalScheduled = 0
            var perfectDays = 0
            var totalMinutes = 0
            var habitCompletionCounts: [UUID: Int] = [:]
            var streakDays = 0
            var currentStreak = 0

            // Track highlight day (best performing day)
            var highlightDate: Date?
            var highlightCompletions = 0
            var highlightReason: String?
            var bestDayRate: Double = 0

            // Iterate through each day of the week
            var checkDate = weekStart
            while checkDate <= weekEnd {
                let scheduledHabits = ProgressTracker.scheduledHabits(from: habits, for: checkDate)
                let scheduledCount = scheduledHabits.count
                var completedCount = 0

                for habit in scheduledHabits {
                    if habit.isFullyCompleted(for: checkDate) {
                        completedCount += 1
                        habitCompletionCounts[habit.id, default: 0] += 1

                        // Add timer duration if applicable
                        if habit.isTimerBased, let duration = habit.duration {
                            totalMinutes += Int(duration / 60)
                        }
                    }
                }

                totalCompletions += completedCount
                totalScheduled += scheduledCount

                // Track best day (100% completion with most habits)
                let dayRate = scheduledCount > 0 ? Double(completedCount) / Double(scheduledCount) : 0
                if scheduledCount > 0 && dayRate == 1.0 && completedCount > highlightCompletions {
                    highlightDate = checkDate
                    highlightCompletions = completedCount
                    highlightReason = "perfect_day"
                    bestDayRate = dayRate
                } else if dayRate > bestDayRate && highlightDate == nil {
                    // If no perfect day yet, track best partial day
                    highlightDate = checkDate
                    highlightCompletions = completedCount
                    highlightReason = "best_day"
                    bestDayRate = dayRate
                }

                // Check for perfect day
                if scheduledCount > 0 && completedCount == scheduledCount {
                    perfectDays += 1
                    currentStreak += 1
                    streakDays = max(streakDays, currentStreak)
                } else if scheduledCount > 0 {
                    currentStreak = 0
                }

                guard let nextDay = calendar.date(byAdding: .day, value: 1, to: checkDate) else { break }
                checkDate = nextDay
            }

            // Find most consistent habit
            let mostConsistent = habitCompletionCounts.max { $0.value < $1.value }
            let mostConsistentHabit = habits.first { $0.id == mostConsistent?.key }

            // Calculate completion rate
            let completionRate = totalScheduled > 0 ? Double(totalCompletions) / Double(totalScheduled) : 0.0

            // Calculate improvement from last week
            let improvementFromLastWeek = calculateImprovement(currentRate: completionRate, weekStart: weekStart, context: context)

            // Create the wrap
            let wrap = WeeklyWrap(
                weekStartDate: weekStart,
                weekEndDate: weekEnd,
                totalCompletions: totalCompletions,
                completionRate: completionRate,
                perfectDays: perfectDays,
                bestStreak: streakDays,
                totalMinutesTracked: totalMinutes,
                mostConsistentHabitId: mostConsistentHabit?.id,
                mostConsistentHabitName: mostConsistentHabit?.name,
                improvementFromLastWeek: improvementFromLastWeek,
                totalHabitsTracked: habits.count,
                totalScheduledCompletions: totalScheduled,
                highlightDayDate: highlightDate,
                highlightDayCompletions: highlightCompletions,
                highlightDayReason: highlightReason
            )

            context.insert(wrap)
            try context.save()
            pendingWrap = wrap

        } catch {
            print("Failed to generate weekly wrap: \(error)")
        }
    }

    /// Calculate improvement from previous week
    private func calculateImprovement(currentRate: Double, weekStart: Date, context: ModelContext) -> Double? {
        let calendar = Calendar.current
        guard let previousWeekStart = calendar.date(byAdding: .day, value: -7, to: weekStart) else { return nil }

        let descriptor = FetchDescriptor<WeeklyWrap>(
            predicate: #Predicate { wrap in
                wrap.weekStartDate == previousWeekStart
            }
        )

        do {
            let previousWraps = try context.fetch(descriptor)
            if let previousWrap = previousWraps.first {
                return currentRate - previousWrap.completionRate
            }
        } catch {
            print("Failed to fetch previous wrap: \(error)")
        }

        return nil
    }

    /// Fetch all wraps for settings view
    func fetchAllWraps(context: ModelContext) -> [WeeklyWrap] {
        let descriptor = FetchDescriptor<WeeklyWrap>(
            sortBy: [SortDescriptor(\.weekStartDate, order: .reverse)]
        )

        do {
            return try context.fetch(descriptor)
        } catch {
            print("Failed to fetch wraps: \(error)")
            return []
        }
    }
}
