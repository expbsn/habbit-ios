//
//  HabitCompletion.swift
//  Stick
//
//  Created by Kian Jain on 02.02.26.
//

import Foundation
import SwiftData

@Model
final class HabitCompletion {
    // MARK: - Properties

    var id: UUID = UUID()

    /// The date and time when the habit was completed
    var completionDate: Date = Date()

    /// Count for partial completion habits (e.g., 1 glass of water)
    /// Default is 1 for binary habits or single completions
    var count: Int = 1

    /// Actual duration in seconds if timer was used (nil for quick complete)
    var actualDuration: TimeInterval?

    /// Optional notes about this completion
    var notes: String?

    /// Source of this completion: "manual", "healthkit", or "timer"
    var source: String?

    // MARK: - Relationships

    var habit: Habit?

    // MARK: - Computed Properties

    /// Formatted duration string (e.g., "5m 30s")
    var formattedDuration: String? {
        guard let duration = actualDuration else { return nil }

        let minutes = Int(duration) / 60
        let seconds = Int(duration) % 60

        if minutes > 0 {
            return "\(minutes)m \(seconds)s"
        } else {
            return "\(seconds)s"
        }
    }

    /// Whether this completion used the timer feature
    var usedTimer: Bool {
        actualDuration != nil
    }

    /// Date component only (start of day)
    var completionDay: Date {
        Calendar.current.startOfDay(for: completionDate)
    }

    // MARK: - Initialization

    init(
        habit: Habit,
        completionDate: Date = Date(),
        count: Int = 1,
        actualDuration: TimeInterval? = nil,
        notes: String? = nil,
        source: String? = "manual"
    ) {
        self.id = UUID()
        self.habit = habit
        self.completionDate = completionDate
        self.count = count
        self.actualDuration = actualDuration
        self.notes = notes
        self.source = source
    }
}
