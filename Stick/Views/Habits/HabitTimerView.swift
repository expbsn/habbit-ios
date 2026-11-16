//
//  HabitTimerView.swift
//  Stick
//
//  Created by Kian Jain on 02.02.26.
//

import SwiftUI
import SwiftData
#if canImport(UIKit)
import UIKit
#endif

struct HabitTimerView: View {
    let habit: Habit
    let onComplete: () -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @StateObject private var activityManager = TimerActivityManager.shared

    // Timer state - simple integer seconds
    @State private var remainingSeconds: Int = 0
    @State private var isRunning: Bool = false
    @State private var timer: Timer?

    // Background timer support
    @State private var timerStartDate: Date? = nil
    @State private var accumulatedSeconds: Int = 0

    // Track if we restored from an existing timer
    @State private var restoredFromExisting: Bool = false
    // Track if habit was auto-completed to prevent double-completion
    @State private var hasAutoCompleted: Bool = false

    private var targetSeconds: Int {
        Int(habit.duration ?? 0)
    }

    /// Check if there's an existing active timer for this habit
    private var hasExistingTimer: Bool {
        activityManager.hasActiveTimer(for: habit.id)
    }

    private var elapsedSeconds: Int {
        targetSeconds - remainingSeconds
    }

    private var progress: Double {
        guard targetSeconds > 0 else { return 0 }
        return Double(elapsedSeconds) / Double(targetSeconds)
    }

    private var isComplete: Bool {
        remainingSeconds <= 0
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                // Timer display
                Text(formatTime(remainingSeconds))
                    .font(.system(size: 64, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(hasAutoCompleted ? .green : Color(hex: habit.color))

                // Progress ring with tappable checkmark
                ZStack {
                    Circle()
                        .stroke(Color(hex: habit.color).opacity(0.2), lineWidth: 8)

                    Circle()
                        .trim(from: 0, to: progress)
                        .stroke(
                            hasAutoCompleted ? Color.green : Color(hex: habit.color),
                            style: StrokeStyle(lineWidth: 8, lineCap: .round)
                        )
                        .rotationEffect(.degrees(-90))

                    // Tappable checkmark to toggle completion
                    Button {
                        toggleCompletion()
                    } label: {
                        ZStack {
                            Circle()
                                .fill(hasAutoCompleted ? Color.green : Color(hex: habit.color).opacity(0.15))
                                .frame(width: 70, height: 70)

                            Image(systemName: "checkmark")
                                .font(.system(size: 28, weight: .bold))
                                .foregroundStyle(hasAutoCompleted ? .white : Color(hex: habit.color))
                        }
                    }
                }
                .frame(width: 120, height: 120)

                // Controls (hidden when completed)
                if !hasAutoCompleted {
                    HStack(spacing: 32) {
                        // Reset button
                        Button {
                            resetTimer()
                        } label: {
                            Image(systemName: "arrow.counterclockwise")
                                .font(.title2)
                                .frame(width: 50, height: 50)
                                .background(Color.gray.opacity(0.2))
                                .clipShape(Circle())
                        }
                        .disabled(remainingSeconds == targetSeconds)
                        .opacity(remainingSeconds == targetSeconds ? 0.5 : 1)

                        // Play/Pause button
                        Button {
                            if isRunning {
                                pauseTimer()
                            } else {
                                startTimer()
                            }
                        } label: {
                            Image(systemName: isRunning ? "pause.fill" : "play.fill")
                                .font(.title)
                                .frame(width: 64, height: 64)
                                .background(Color(hex: habit.color))
                                .foregroundStyle(.white)
                                .clipShape(Circle())
                        }

                        // Skip +30s button
                        Button {
                            skipForward()
                        } label: {
                            Image(systemName: "goforward.30")
                                .font(.title2)
                                .frame(width: 50, height: 50)
                                .background(Color.gray.opacity(0.2))
                                .clipShape(Circle())
                        }
                        .disabled(isComplete)
                        .opacity(isComplete ? 0.5 : 1)
                    }
                } else {
                    // Show completion message when done
                    Text(String(localized: "timer_completed"))
                        .font(.headline)
                        .foregroundStyle(.green)
                }
            }
            .padding()
            .navigationTitle(habit.name)
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(String(localized: "settings_cancel")) {
                        stopTimer()
                        Task { await TimerActivityManager.shared.endActivity() }
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(String(localized: "timer_done")) {
                        closeTimer()
                    }
                    .fontWeight(.semibold)
                }
            }
            .onAppear {
                restoreOrInitializeTimer()
            }
            .onDisappear {
                // Only stop the local timer, don't end the activity
                // This allows the Live Activity to continue running
                stopTimer()
            }
            #if canImport(UIKit)
            .onReceive(NotificationCenter.default.publisher(for: UIApplication.willEnterForegroundNotification)) { _ in
                if isRunning {
                    updateRemainingTime()
                }
            }
            #endif
        }
    }

    // MARK: - Timer Functions

    private func restoreOrInitializeTimer() {
        // First check if habit is already completed for today
        if habit.isEffectivelyCompleted(for: Date()) {
            hasAutoCompleted = true
            remainingSeconds = 0
            accumulatedSeconds = targetSeconds
            isRunning = false
            restoredFromExisting = false
            return
        }

        if activityManager.hasActiveTimer(for: habit.id) {
            // Restore state from the activity manager
            restoredFromExisting = true
            remainingSeconds = activityManager.getCurrentRemainingSeconds()
            accumulatedSeconds = activityManager.accumulatedSeconds
            isRunning = activityManager.isTimerRunning

            if isRunning {
                // Resume the local timer for UI updates
                timerStartDate = activityManager.timerStartDate
                timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { _ in
                    updateRemainingTime()
                }
            }
        } else {
            // Initialize fresh timer
            remainingSeconds = targetSeconds
            accumulatedSeconds = 0
            isRunning = false
            restoredFromExisting = false
        }
    }

    private func startTimer() {
        isRunning = true
        timerStartDate = Date()

        // Start or update live activity
        Task {
            if restoredFromExisting {
                // Just update the existing activity
                await TimerActivityManager.shared.updateActivity(
                    remainingSeconds: remainingSeconds,
                    isRunning: true
                )
            } else {
                // Start new activity
                await TimerActivityManager.shared.startActivity(
                    habitId: habit.id,
                    habitName: habit.name,
                    habitColor: habit.color,
                    targetDuration: Double(targetSeconds),
                    remainingSeconds: remainingSeconds,
                    habitEmoji: habit.emoji,
                    habitSymbol: habit.symbolName
                )
                restoredFromExisting = true // Now we have an existing activity
            }
        }

        // Simple 1-second timer for UI updates
        timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { _ in
            updateRemainingTime()
        }
    }

    private func updateRemainingTime() {
        guard let startDate = timerStartDate else { return }
        let elapsedSinceStart = Int(Date().timeIntervalSince(startDate))
        let totalElapsed = accumulatedSeconds + elapsedSinceStart
        remainingSeconds = max(0, targetSeconds - totalElapsed)

        if remainingSeconds <= 0 {
            stopTimer()
            triggerCompletionFeedback()
            // Auto-complete the habit and show completion in Live Activity
            autoCompleteHabit()
            Task { await TimerActivityManager.shared.completeActivity() }
        }
    }

    private func pauseTimer() {
        isRunning = false
        timer?.invalidate()
        timer = nil

        // Save accumulated time
        if let startDate = timerStartDate {
            accumulatedSeconds += Int(Date().timeIntervalSince(startDate))
        }
        timerStartDate = nil

        Task {
            await TimerActivityManager.shared.updateActivity(
                remainingSeconds: remainingSeconds,
                isRunning: false
            )
        }
    }

    private func stopTimer() {
        isRunning = false
        timer?.invalidate()
        timer = nil
        timerStartDate = nil
    }

    private func resetTimer() {
        stopTimer()
        remainingSeconds = targetSeconds
        accumulatedSeconds = 0

        Task {
            await TimerActivityManager.shared.updateActivity(
                remainingSeconds: remainingSeconds,
                isRunning: false
            )
        }
    }

    private func skipForward() {
        // When skipping, add 30 seconds to accumulated time
        accumulatedSeconds += 30
        remainingSeconds = max(0, remainingSeconds - 30)

        if remainingSeconds <= 0 {
            stopTimer()
            triggerCompletionFeedback()
            autoCompleteHabit()
            Task { await TimerActivityManager.shared.completeActivity() }
        } else {
            Task {
                await TimerActivityManager.shared.updateActivity(
                    remainingSeconds: remainingSeconds,
                    isRunning: isRunning
                )
            }
        }
    }

    /// Auto-complete when timer naturally reaches zero
    private func autoCompleteHabit() {
        guard !hasAutoCompleted else { return }
        hasAutoCompleted = true

        // Create completion record
        let completion = HabitCompletion(
            habit: habit,
            count: 1,
            actualDuration: TimeInterval(targetSeconds), // Full duration completed
            source: "timer"
        )
        modelContext.insert(completion)
        habit.safeCompletions.append(completion)

        do {
            try modelContext.save()
            onComplete() // Notify parent to refresh
        } catch {
            print("Failed to save auto-completion: \(error)")
        }
    }

    /// Toggle completion via checkmark button inside progress ring
    private func toggleCompletion() {
        if hasAutoCompleted {
            // Uncomplete the habit
            uncompleteHabit()
        } else {
            // Complete the habit
            completeHabit()
        }
    }

    /// Mark habit as complete
    private func completeHabit() {
        hasAutoCompleted = true

        stopTimer()

        Task {
            await TimerActivityManager.shared.completeActivity()
        }

        // Create completion record with elapsed time
        let completion = HabitCompletion(
            habit: habit,
            count: 1,
            actualDuration: TimeInterval(elapsedSeconds),
            source: "timer"
        )
        modelContext.insert(completion)
        habit.safeCompletions.append(completion)

        do {
            try modelContext.save()
            triggerCompletionFeedback()
            onComplete()
        } catch {
            print("Failed to save: \(error)")
        }
    }

    /// Remove completion and reset timer
    private func uncompleteHabit() {
        // Delete today's completions
        let todayCompletions = habit.completions(for: Date())
        for completion in todayCompletions {
            modelContext.delete(completion)
        }

        do {
            try modelContext.save()
            onComplete()
        } catch {
            print("Failed to delete completion: \(error)")
        }

        // Reset timer state
        hasAutoCompleted = false
        remainingSeconds = targetSeconds
        accumulatedSeconds = 0
        isRunning = false
        restoredFromExisting = false

        Task {
            await TimerActivityManager.shared.endActivity()
        }
    }

    /// Close timer view without marking as complete (Done button)
    private func closeTimer() {
        stopTimer()

        // If already completed, just dismiss
        // If not completed, keep Live Activity running in background
        if hasAutoCompleted {
            Task {
                await TimerActivityManager.shared.endActivity()
            }
        }
        // If timer is still running/paused and not completed,
        // the Live Activity continues in the background

        dismiss()
    }

    private func triggerCompletionFeedback() {
        #if os(iOS)
        let generator = UINotificationFeedbackGenerator()
        generator.notificationOccurred(.success)
        #endif
    }

    private func formatTime(_ seconds: Int) -> String {
        let mins = seconds / 60
        let secs = seconds % 60
        return String(format: "%d:%02d", mins, secs)
    }
}

// MARK: - Preview

#Preview {
    let habit = Habit(
        name: "Meditation",
        color: "#5856D6",
        emoji: "🧘",
        frequency: .daily,
        duration: 600
    )

    return HabitTimerView(habit: habit) {
        print("Completed!")
    }
}
