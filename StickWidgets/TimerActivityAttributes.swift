//
//  TimerActivityAttributes.swift
//  StickWidgets
//
//  Shared Activity Attributes for Timer Live Activity
//

import Foundation
import ActivityKit

struct TimerActivityAttributes: ActivityAttributes {
    public struct ContentState: Codable, Hashable {
        /// The time when the timer will end (used for countdown)
        var endTime: Date
        /// Whether the timer is actively running
        var isRunning: Bool
        /// Whether the timer is paused (not running but not finished)
        var isPaused: Bool
        /// Whether the timer has completed successfully
        var isCompleted: Bool
        /// Seconds remaining when paused (nil when running or completed)
        var pausedSecondsRemaining: Int?
    }

    var habitName: String
    var habitColor: String
    var targetDuration: TimeInterval
    var habitEmoji: String?
    var habitSymbol: String?
}
