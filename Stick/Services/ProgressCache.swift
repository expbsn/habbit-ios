//
//  ProgressCache.swift
//  Stick
//
//  Caches daily progress calculations for calendar display.
//  Populated on app launch and updated when completions change.
//

import Foundation
import SwiftData

@Observable
final class ProgressCache {
    static let shared = ProgressCache()

    /// Cached progress values: date (start of day) -> progress (0.0-1.0)
    private(set) var cache: [Date: Double] = [:]

    /// Whether the cache has been populated
    private(set) var isLoaded = false

    private init() {}

    /// Populate cache with progress for the last 12 months
    @MainActor
    func populate(habits: [Habit], skippedDates: Set<Date>) {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())

        // Calculate for last 365 days
        cache.removeAll()

        for dayOffset in 0..<365 {
            guard let date = calendar.date(byAdding: .day, value: -dayOffset, to: today) else { continue }
            let dayStart = calendar.startOfDay(for: date)

            if skippedDates.contains(dayStart) {
                cache[dayStart] = 0.0
            } else {
                let progress = ProgressTracker.progress(for: date, habits: habits)
                cache[dayStart] = progress
            }
        }

        isLoaded = true
    }

    /// Get cached progress for a date, or calculate if not cached
    func progress(for date: Date, habits: [Habit], skippedDates: Set<Date>) -> Double {
        let dayStart = Calendar.current.startOfDay(for: date)

        // Return cached value if available
        if let cached = cache[dayStart] {
            return cached
        }

        // Calculate and cache if not found
        if skippedDates.contains(dayStart) {
            cache[dayStart] = 0.0
            return 0.0
        }

        let progress = ProgressTracker.progress(for: date, habits: habits)
        cache[dayStart] = progress
        return progress
    }

    /// Invalidate cache (call when habits or completions change)
    func invalidate() {
        cache.removeAll()
        isLoaded = false
    }

    /// Update cache for a specific date (call after completion changes)
    func updateDate(_ date: Date, habits: [Habit], skippedDates: Set<Date>) {
        let dayStart = Calendar.current.startOfDay(for: date)

        if skippedDates.contains(dayStart) {
            cache[dayStart] = 0.0
        } else {
            cache[dayStart] = ProgressTracker.progress(for: date, habits: habits)
        }
    }
}
