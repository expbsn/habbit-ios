//
//  SkippedDay.swift
//  Stick
//
//  Model for tracking skipped days that don't break streaks.
//

import Foundation
import SwiftData

@Model
final class SkippedDay {
    var id: UUID = UUID()
    var date: Date = Date()          // Start of day
    var createdDate: Date = Date()
    var reason: String?     // Optional: "sick", "vacation", etc.

    init(date: Date, reason: String? = nil) {
        self.id = UUID()
        self.date = Calendar.current.startOfDay(for: date)
        self.createdDate = Date()
        self.reason = reason
    }
}
