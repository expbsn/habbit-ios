//
//  TimerActivityManager.swift
//  Stick
//
//  Created by Kian Jain on 02.02.26.
//

import Foundation
import Combine

#if canImport(ActivityKit)
import ActivityKit

@MainActor
final class TimerActivityManager: ObservableObject {
    static let shared = TimerActivityManager()

    private var currentActivity: Activity<TimerActivityAttributes>?

    // MARK: - Active Timer State (persists when view is dismissed)

    /// The habit ID that has an active timer
    @Published private(set) var activeHabitId: UUID?

    /// Whether the timer is currently running (vs paused)
    @Published private(set) var isTimerRunning: Bool = false

    /// Remaining seconds when paused, or calculated from endTime when running
    private(set) var pausedRemainingSeconds: Int = 0

    /// Accumulated elapsed seconds (for calculating remaining time after resume)
    private(set) var accumulatedSeconds: Int = 0

    /// The timer start date (for calculating elapsed time)
    private(set) var timerStartDate: Date?

    /// Target duration for the active timer
    private(set) var targetDuration: TimeInterval = 0

    private init() {}

    func startActivity(
        habitId: UUID,
        habitName: String,
        habitColor: String,
        targetDuration: TimeInterval,
        remainingSeconds: Int,
        habitEmoji: String? = nil,
        habitSymbol: String? = nil
    ) async {
        // End any existing activity first
        await endActivity()

        // Store active timer state
        self.activeHabitId = habitId
        self.isTimerRunning = true
        self.targetDuration = targetDuration
        self.timerStartDate = Date()
        self.accumulatedSeconds = Int(targetDuration) - remainingSeconds
        self.pausedRemainingSeconds = remainingSeconds

        let endTime = Date().addingTimeInterval(TimeInterval(remainingSeconds))

        let authInfo = ActivityAuthorizationInfo()
        guard authInfo.areActivitiesEnabled else {
            print("Live Activities are NOT enabled")
            return
        }

        let attributes = TimerActivityAttributes(
            habitName: habitName,
            habitColor: habitColor,
            targetDuration: targetDuration,
            habitEmoji: habitEmoji,
            habitSymbol: habitSymbol
        )

        let initialState = TimerActivityAttributes.ContentState(
            endTime: endTime,
            isRunning: true,
            isPaused: false,
            isCompleted: false,
            pausedSecondsRemaining: nil
        )

        do {
            let activity = try Activity.request(
                attributes: attributes,
                content: .init(state: initialState, staleDate: endTime.addingTimeInterval(1)),
                pushType: nil
            )
            currentActivity = activity
            print("Started Live Activity: \(activity.id)")
        } catch {
            print("Failed to start Live Activity: \(error)")
        }
    }

    func updateActivity(remainingSeconds: Int, isRunning: Bool) async {
        // Update internal state
        self.isTimerRunning = isRunning
        self.pausedRemainingSeconds = remainingSeconds

        if isRunning {
            self.timerStartDate = Date()
            self.accumulatedSeconds = Int(targetDuration) - remainingSeconds
        } else {
            // Paused - save accumulated time
            if let startDate = timerStartDate {
                accumulatedSeconds += Int(Date().timeIntervalSince(startDate))
            }
            timerStartDate = nil
        }

        guard let activity = currentActivity else { return }

        let updatedState: TimerActivityAttributes.ContentState

        if isRunning {
            // Timer is running - calculate end time
            let endTime = Date().addingTimeInterval(TimeInterval(remainingSeconds))
            updatedState = TimerActivityAttributes.ContentState(
                endTime: endTime,
                isRunning: true,
                isPaused: false,
                isCompleted: false,
                pausedSecondsRemaining: nil
            )
        } else {
            // Timer is paused - store remaining seconds
            updatedState = TimerActivityAttributes.ContentState(
                endTime: Date(),
                isRunning: false,
                isPaused: true,
                isCompleted: false,
                pausedSecondsRemaining: remainingSeconds
            )
        }

        await activity.update(
            ActivityContent(state: updatedState, staleDate: nil)
        )
    }

    /// Mark the activity as completed (timer finished successfully)
    /// The Live Activity stays visible until the user opens the app
    func completeActivity() async {
        guard let activity = currentActivity else { return }

        let completedState = TimerActivityAttributes.ContentState(
            endTime: Date(),
            isRunning: false,
            isPaused: false,
            isCompleted: true,
            pausedSecondsRemaining: nil
        )

        // Update to completed state - don't dismiss automatically
        // The activity will be dismissed when the user opens the app
        await activity.update(
            ActivityContent(state: completedState, staleDate: nil)
        )

        // Clear internal timer state but keep currentActivity reference
        // so dismissCompletedActivities() can clean it up later
        activeHabitId = nil
        isTimerRunning = false
        pausedRemainingSeconds = 0
        accumulatedSeconds = 0
        timerStartDate = nil
        targetDuration = 0
    }

    func endActivity() async {
        if let activity = currentActivity {
            await activity.end(nil, dismissalPolicy: .immediate)
        }
        clearState()
    }

    /// Clear all timer state
    private func clearState() {
        currentActivity = nil
        activeHabitId = nil
        isTimerRunning = false
        pausedRemainingSeconds = 0
        accumulatedSeconds = 0
        timerStartDate = nil
        targetDuration = 0
    }

    /// Get current remaining seconds (calculates from running timer if active)
    func getCurrentRemainingSeconds() -> Int {
        if isTimerRunning, let startDate = timerStartDate {
            let elapsed = Int(Date().timeIntervalSince(startDate))
            let totalElapsed = accumulatedSeconds + elapsed
            return max(0, Int(targetDuration) - totalElapsed)
        }
        return pausedRemainingSeconds
    }

    /// Check if a specific habit has an active timer
    func hasActiveTimer(for habitId: UUID) -> Bool {
        activeHabitId == habitId
    }

    var hasActiveActivity: Bool {
        currentActivity != nil
    }

    /// Dismiss any completed Live Activities when app becomes active
    func dismissCompletedActivities() async {
        var hadCompletedActivities = false

        for activity in Activity<TimerActivityAttributes>.activities {
            let state = activity.content.state

            // Dismiss if explicitly completed OR if timer has expired
            let isExpired = state.isRunning && state.endTime <= Date()

            if state.isCompleted || isExpired {
                await activity.end(nil, dismissalPolicy: .immediate)
                hadCompletedActivities = true
            }
        }

        // Clear currentActivity reference if we dismissed it
        if hadCompletedActivities {
            clearState()
        }
    }
}

#else

import Combine

@MainActor
final class TimerActivityManager: ObservableObject {
    static let shared = TimerActivityManager()

    @Published private(set) var activeHabitId: UUID?
    @Published private(set) var isTimerRunning: Bool = false
    private(set) var pausedRemainingSeconds: Int = 0
    private(set) var accumulatedSeconds: Int = 0
    private(set) var timerStartDate: Date?
    private(set) var targetDuration: TimeInterval = 0

    private init() {}

    func startActivity(
        habitId: UUID,
        habitName: String,
        habitColor: String,
        targetDuration: TimeInterval,
        remainingSeconds: Int,
        habitEmoji: String? = nil,
        habitSymbol: String? = nil
    ) async {}

    func updateActivity(remainingSeconds: Int, isRunning: Bool) async {}
    func completeActivity() async {}
    func endActivity() async {}
    func getCurrentRemainingSeconds() -> Int { 0 }
    func hasActiveTimer(for habitId: UUID) -> Bool { false }
    var hasActiveActivity: Bool { false }
    func dismissCompletedActivities() async {}
}

#endif
