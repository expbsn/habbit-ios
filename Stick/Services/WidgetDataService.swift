//
//  WidgetDataService.swift
//  Stick
//
//  Service to sync habit data with home screen widgets
//

import Foundation
import WidgetKit
import SwiftData

// MARK: - Widget Habit Model (must match widget's model)

struct WidgetHabitData: Codable {
    let id: String
    let name: String
    let color: String
    let emoji: String?
    let symbolName: String?
    let currentCount: Int
    let targetCount: Int
    let isCompleted: Bool
    let frequency: String
    let streakCount: Int
}

/// Todo item shape written to the app group for the widget.
struct WidgetTodoData: Codable {
    let title: String
    let isDone: Bool
}

// MARK: - Widget Data Service

@MainActor
final class WidgetDataService {
    static let shared = WidgetDataService()

    private let appGroupID = "group.com.kianjain.Stick"
    private let habitsKey = "widgetHabits"
    private let progressKey = "widgetProgress"
    let stepsCountKey = "widgetStepsCount"
    let stepsGoalKey = "widgetStepsGoal"
    // Daily note keys (mirror WidgetDailyNote in the widget target)
    private let noteModeKey = "widgetDailyNoteMode"      // "text" | "todo" | "" (none)
    private let noteTextKey = "widgetDailyNoteText"
    private let noteTodosKey = "widgetDailyNoteTodos"    // JSON [WidgetTodoData]
    private let noteDateKey = "widgetDailyNoteDate"      // start-of-day timestamp

    private var sharedDefaults: UserDefaults? {
        UserDefaults(suiteName: appGroupID)
    }

    private init() {}

    /// Sync all habits to the widget, optionally refreshing today's note too.
    func syncHabits(_ habits: [Habit], todayNote: DailyNote? = nil) {
        writeDailyNote(todayNote)
        syncHabitsData(habits)
    }

    /// Push today's daily note to the widget and trigger a reload.
    func syncDailyNote(_ note: DailyNote?) {
        writeDailyNote(note)
        reloadWidgets()
    }

    /// Write the daily-note payload to shared UserDefaults (no reload).
    private func writeDailyNote(_ note: DailyNote?) {
        guard let defaults = sharedDefaults else { return }

        // Only today's note is relevant to the widget.
        let isTodayNote = note.map { Calendar.current.isDateInToday($0.date) } ?? false

        guard let note, isTodayNote, note.hasContent else {
            defaults.set("", forKey: noteModeKey)
            defaults.removeObject(forKey: noteTextKey)
            defaults.removeObject(forKey: noteTodosKey)
            defaults.set(Calendar.current.startOfDay(for: Date()).timeIntervalSince1970, forKey: noteDateKey)
            return
        }

        defaults.set(note.mode.rawValue, forKey: noteModeKey)
        defaults.set(Calendar.current.startOfDay(for: note.date).timeIntervalSince1970, forKey: noteDateKey)

        switch note.mode {
        case .text:
            defaults.set(note.content, forKey: noteTextKey)
            defaults.removeObject(forKey: noteTodosKey)
        case .todo:
            let todos = note.todos.map { WidgetTodoData(title: $0.title, isDone: $0.isDone) }
            if let data = try? JSONEncoder().encode(todos) {
                defaults.set(data, forKey: noteTodosKey)
            }
            defaults.removeObject(forKey: noteTextKey)
        }
    }

    /// Sync all habits to the widget
    private func syncHabitsData(_ habits: [Habit]) {
        let today = Date()
        let activeHabits = habits.filter { $0.isActive }

        // Calculate overall progress using ProgressTracker logic
        let todayProgress = ProgressTracker.progress(for: today, habits: activeHabits)

        // Only sync daily-type habits that are scheduled for today
        let scheduledHabits = ProgressTracker.scheduledHabits(from: activeHabits, for: today)
        let widgetHabits = scheduledHabits.map { habit -> WidgetHabitData in
            let currentCount = habit.currentCount(for: today)
            let targetCount = habit.targetCount ?? 1
            let isCompleted = habit.isFullyCompleted(for: today)
            let streakCount = habit.currentStreak()

            return WidgetHabitData(
                id: habit.id.uuidString,
                name: habit.name,
                color: habit.color,
                emoji: habit.emoji,
                symbolName: habit.symbolName,
                currentCount: currentCount,
                targetCount: targetCount,
                isCompleted: isCompleted,
                frequency: habit.frequency.displayName,
                streakCount: streakCount
            )
        }

        // Persist steps goal from any steps-linked habit
        if let stepsHabit = activeHabits.first(where: { $0.healthKitType == "steps" }),
           let target = stepsHabit.targetCount, target > 0 {
            sharedDefaults?.set(target, forKey: stepsGoalKey)
        } else {
            // Default 10 000 steps goal if no habit is configured
            if sharedDefaults?.object(forKey: stepsGoalKey) == nil {
                sharedDefaults?.set(10_000, forKey: stepsGoalKey)
            }
        }

        saveHabits(widgetHabits)
        saveProgress(todayProgress)
        reloadWidgets()
    }

    /// Write the latest step count from HealthKit to shared UserDefaults
    func syncSteps(count: Int) {
        sharedDefaults?.set(count, forKey: stepsCountKey)
    }

    /// Save habits to shared UserDefaults
    private func saveHabits(_ habits: [WidgetHabitData]) {
        guard let defaults = sharedDefaults,
              let data = try? JSONEncoder().encode(habits) else {
            return
        }
        defaults.set(data, forKey: habitsKey)
    }

    /// Save progress to shared UserDefaults
    private func saveProgress(_ progress: Double) {
        guard let defaults = sharedDefaults else { return }
        // Store -1 as 0 for display (no habits scheduled = show 0%)
        defaults.set(max(0, progress), forKey: progressKey)
    }

    /// Reload all widgets
    func reloadWidgets() {
        WidgetCenter.shared.reloadAllTimelines()
    }
}
