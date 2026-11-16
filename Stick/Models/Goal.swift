//
//  Goal.swift
//  Stick
//
//  Created by Kian Jain on 02.02.26.
//

import Foundation
import SwiftData

@Model
final class Goal {
    // MARK: - Properties

    var id: UUID = UUID()
    var name: String = ""
    var goalDescription: String?
    var createdDate: Date = Date()

    // MARK: - Relationships

    @Relationship(deleteRule: .nullify)
    var habits: [Habit]?

    /// Safe accessor for habits that returns empty array if nil
    var safeHabits: [Habit] {
        get { habits ?? [] }
        set { habits = newValue }
    }

    // MARK: - Computed Properties

    /// Number of active habits in this goal
    var activeHabitCount: Int {
        safeHabits.filter { $0.isActive }.count
    }

    /// Calculate overall progress for today (0.0 - 1.0)
    func todayProgress() -> Double {
        let today = Date()
        let scheduledHabits = safeHabits.filter { $0.isActive && $0.isScheduled(for: today) }

        guard !scheduledHabits.isEmpty else { return 1.0 }

        let completedCount = scheduledHabits.filter { $0.isFullyCompleted(for: today) }.count
        return Double(completedCount) / Double(scheduledHabits.count)
    }

    /// Calculate progress for a specific date range
    func progress(from startDate: Date, to endDate: Date) -> Double {
        let calendar = Calendar.current
        var totalScheduled = 0
        var totalCompleted = 0

        var currentDate = startDate
        while currentDate <= endDate {
            for habit in safeHabits where habit.isActive && habit.isScheduled(for: currentDate) {
                totalScheduled += 1
                if habit.isFullyCompleted(for: currentDate) {
                    totalCompleted += 1
                }
            }

            guard let nextDate = calendar.date(byAdding: .day, value: 1, to: currentDate) else {
                break
            }
            currentDate = nextDate
        }

        guard totalScheduled > 0 else { return 1.0 }
        return Double(totalCompleted) / Double(totalScheduled)
    }

    // MARK: - Initialization

    init(name: String, description: String? = nil) {
        self.id = UUID()
        self.name = name
        self.goalDescription = description
        self.createdDate = Date()
        self.habits = []
    }
}
