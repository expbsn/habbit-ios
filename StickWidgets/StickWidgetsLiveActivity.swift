//
//  StickWidgetsLiveActivity.swift
//  StickWidgets
//
//  Created by Kian Jain on 04.02.26.
//

import ActivityKit
import WidgetKit
import SwiftUI

struct StickWidgetsLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: TimerActivityAttributes.self) { context in
            // Lock screen view
            LockScreenLiveActivityView(context: context)
        } dynamicIsland: { context in
            DynamicIsland {
                // Put all content in bottom region for proper alignment below the notch
                DynamicIslandExpandedRegion(.leading) {
                    EmptyView()
                }

                DynamicIslandExpandedRegion(.trailing) {
                    EmptyView()
                }

                DynamicIslandExpandedRegion(.bottom) {
                    ExpandedContentView(context: context)
                }
            } compactLeading: {
                CompactLeadingView(context: context)
            } compactTrailing: {
                CompactTrailingView(context: context)
            } minimal: {
                MinimalView(context: context)
            }
        }
    }
}

// MARK: - Helper to determine timer state

private func timerState(_ context: ActivityViewContext<TimerActivityAttributes>) -> TimerDisplayState {
    if context.state.isCompleted {
        return .completed
    } else if context.state.isPaused {
        return .paused(remaining: context.state.pausedSecondsRemaining ?? 0)
    } else if context.state.isRunning {
        if context.state.endTime <= Date() {
            return .completed
        }
        return .running(endTime: context.state.endTime)
    }
    return .completed
}

private enum TimerDisplayState {
    case running(endTime: Date)
    case paused(remaining: Int)
    case completed

    var isCompleted: Bool {
        if case .completed = self { return true }
        return false
    }

    var isPaused: Bool {
        if case .paused = self { return true }
        return false
    }

    var isRunning: Bool {
        if case .running = self { return true }
        return false
    }
}

private func habitColor(_ context: ActivityViewContext<TimerActivityAttributes>) -> Color {
    Color(hex: context.attributes.habitColor)
}

private func formatGoalDuration(_ duration: TimeInterval) -> String {
    let totalMinutes = Int(duration) / 60
    if totalMinutes >= 60 {
        let hours = totalMinutes / 60
        let mins = totalMinutes % 60
        return mins > 0 ? "\(hours)h \(mins)m" : "\(hours)h"
    }
    return "\(totalMinutes) min"
}

// MARK: - Expanded Dynamic Island View (all content in one HStack for alignment)

private struct ExpandedContentView: View {
    let context: ActivityViewContext<TimerActivityAttributes>

    var body: some View {
        let color = habitColor(context)
        let state = timerState(context)

        HStack(spacing: 14) {
            // Icon in circle - always show habit icon, even when completed
            ZStack {
                Circle()
                    .fill(state.isCompleted ? Color.green.opacity(0.25) : color.opacity(0.25))
                    .frame(width: 52, height: 52)

                if let emoji = context.attributes.habitEmoji, !emoji.isEmpty {
                    Text(emoji)
                        .font(.system(size: 32))
                } else if let symbol = context.attributes.habitSymbol, !symbol.isEmpty {
                    Image(systemName: symbol)
                        .font(.system(size: 32, weight: .medium))
                        .foregroundStyle(state.isCompleted ? .green : color)
                } else {
                    Image(systemName: "timer")
                        .font(.system(size: 22, weight: .medium))
                        .foregroundStyle(state.isCompleted ? .green : color)
                }
            }

            // Timer and goal
            VStack(alignment: .leading, spacing: 0) {
                switch state {
                case .completed:
                    Text("Done!")
                        .font(.system(size: 28, weight: .semibold, design: .rounded))
                        .foregroundStyle(.green)
                case .paused(let remaining):
                    Text(formatTime(remaining))
                        .font(.system(size: 28, weight: .semibold, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(.white)
                case .running(let endTime):
                    Text(timerInterval: Date()...endTime, countsDown: true)
                        .font(.system(size: 28, weight: .semibold, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(.white)
                }

                if !state.isCompleted {
                    Text("Goal: \(formatGoalDuration(context.attributes.targetDuration))")
                        .font(.system(size: 12))
                        .foregroundStyle(color.opacity(0.8))
                }
            }

            Spacer()

            // Action buttons
            if state.isCompleted {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 46))
                    .foregroundStyle(.green)
            } else {
                HStack(spacing: 12) {
                    // Pause/Play button
                    Link(destination: URL(string: "stick://timer/toggle")!) {
                        ZStack {
                            Circle()
                                .fill(color.opacity(0.25))
                                .frame(width: 46, height: 46)

                            Image(systemName: state.isPaused ? "play.fill" : "pause.fill")
                                .font(.system(size: 18, weight: .semibold))
                                .foregroundStyle(color)
                        }
                    }

                    // Cancel button
                    Link(destination: URL(string: "stick://timer/cancel")!) {
                        ZStack {
                            Circle()
                                .fill(color.opacity(0.25))
                                .frame(width: 46, height: 52)

                            Image(systemName: "xmark")
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundStyle(color)
                        }
                    }
                }
            }
        }
        .padding(.horizontal, 4)
        .padding(.bottom, 12)
    }
}

// MARK: - Compact Dynamic Island Views

private struct CompactLeadingView: View {
    let context: ActivityViewContext<TimerActivityAttributes>

    var body: some View {
        let color = habitColor(context)
        let state = timerState(context)

        // Always show habit icon, use green tint when completed
        if let emoji = context.attributes.habitEmoji, !emoji.isEmpty {
            Text(emoji)
        } else if let symbol = context.attributes.habitSymbol, !symbol.isEmpty {
            Image(systemName: symbol)
                .foregroundStyle(state.isCompleted ? .green : color)
        } else {
            Image(systemName: "timer")
                .foregroundStyle(state.isCompleted ? .green : color)
        }
    }
}

private struct CompactTrailingView: View {
    let context: ActivityViewContext<TimerActivityAttributes>

    var body: some View {
        let color = habitColor(context)
        let state = timerState(context)
        let targetDuration = context.attributes.targetDuration

        switch state {
        case .completed:
            Image(systemName: "checkmark")
                .fontWeight(.semibold)
                .foregroundStyle(.green)
        case .paused(let remaining):
            // Show progress ring for paused state
            CompactProgressRing(
                progress: 1.0 - (Double(remaining) / targetDuration),
                color: color
            )
        case .running(let endTime):
            // Show progress ring that updates with timer
            ProgressRingWithTimer(
                endTime: endTime,
                targetDuration: targetDuration,
                color: color
            )
        }
    }
}

private struct CompactProgressRing: View {
    let progress: Double
    let color: Color

    var body: some View {
        ZStack {
            Circle()
                .stroke(color.opacity(0.3), lineWidth: 3)
            Circle()
                .trim(from: 0, to: min(1.0, max(0, progress)))
                .stroke(color, style: StrokeStyle(lineWidth: 3, lineCap: .round))
                .rotationEffect(.degrees(-90))
        }
        .frame(width: 20, height: 20)
        .padding(.leading, 2)
    }
}

private struct ProgressRingWithTimer: View {
    let endTime: Date
    let targetDuration: TimeInterval
    let color: Color

    var body: some View {
        TimelineView(.animation(minimumInterval: 1)) { timeline in
            let remaining = max(0, endTime.timeIntervalSince(timeline.date))
            let progress = 1.0 - (remaining / targetDuration)

            CompactProgressRing(progress: progress, color: color)
        }
    }
}

// MARK: - Minimal Dynamic Island View

private struct MinimalView: View {
    let context: ActivityViewContext<TimerActivityAttributes>

    var body: some View {
        let color = habitColor(context)
        let state = timerState(context)

        // Always show habit icon, use green tint when completed
        if let emoji = context.attributes.habitEmoji, !emoji.isEmpty {
            Text(emoji)
                .font(.caption)
        } else if let symbol = context.attributes.habitSymbol, !symbol.isEmpty {
            Image(systemName: symbol)
                .font(.caption2)
                .foregroundStyle(state.isCompleted ? .green : color)
        } else {
            Image(systemName: "timer")
                .font(.caption2)
                .foregroundStyle(state.isCompleted ? .green : color)
        }
    }
}

// MARK: - Lock Screen View

private struct LockScreenLiveActivityView: View {
    let context: ActivityViewContext<TimerActivityAttributes>

    var body: some View {
        let color = habitColor(context)
        let state = timerState(context)

        HStack(spacing: 16) {
            // Icon in circle - always show habit icon, even when completed
            ZStack {
                Circle()
                    .fill(state.isCompleted ? Color.green.opacity(0.2) : color.opacity(0.2))
                    .frame(width: 52, height: 52)

                if let emoji = context.attributes.habitEmoji, !emoji.isEmpty {
                    Text(emoji)
                        .font(.system(size: 24))
                } else if let symbol = context.attributes.habitSymbol, !symbol.isEmpty {
                    Image(systemName: symbol)
                        .font(.system(size: 22, weight: .medium))
                        .foregroundStyle(state.isCompleted ? .green : color)
                } else {
                    Image(systemName: "timer")
                        .font(.system(size: 22, weight: .medium))
                        .foregroundStyle(state.isCompleted ? .green : color)
                }
            }

            // Timer and goal
            VStack(alignment: .leading, spacing: 2) {
                switch state {
                case .completed:
                    Text("Done!")
                        .font(.system(size: 28, weight: .semibold, design: .rounded))
                        .foregroundStyle(.green)
                case .paused(let remaining):
                    Text(formatTime(remaining))
                        .font(.system(size: 28, weight: .semibold, design: .rounded))
                        .monospacedDigit()
                case .running(let endTime):
                    Text(timerInterval: Date()...endTime, countsDown: true)
                        .font(.system(size: 28, weight: .semibold, design: .rounded))
                        .monospacedDigit()
                }

                if !state.isCompleted {
                    Text("Goal: \(formatGoalDuration(context.attributes.targetDuration))")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()

            // Action buttons
            if !state.isCompleted {
                HStack(spacing: 12) {
                    Link(destination: URL(string: "stick://timer/toggle")!) {
                        ZStack {
                            Circle()
                                .fill(color.opacity(0.2))
                                .frame(width: 44, height: 44)

                            Image(systemName: state.isPaused ? "play.fill" : "pause.fill")
                                .font(.system(size: 18, weight: .semibold))
                                .foregroundStyle(color)
                        }
                    }

                    Link(destination: URL(string: "stick://timer/cancel")!) {
                        ZStack {
                            Circle()
                                .fill(color.opacity(0.2))
                                .frame(width: 44, height: 44)

                            Image(systemName: "xmark")
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundStyle(color)
                        }
                    }
                }
            } else {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 44))
                    .foregroundStyle(.green)
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 16)
        .activityBackgroundTint(Color("ActivityBackground").opacity(0.75))
    }
}

// MARK: - Helper Functions

private func formatTime(_ seconds: Int) -> String {
    let mins = seconds / 60
    let secs = seconds % 60
    return String(format: "%d:%02d", mins, secs)
}

private func formatTimeCompact(_ seconds: Int) -> String {
    let mins = seconds / 60
    let secs = seconds % 60
    return String(format: "%d:%02d", mins, secs)
}

private func formatMinutesOnly(_ seconds: Int) -> String {
    // Show seconds only when below 1 minute
    if seconds < 60 {
        return "\(seconds)s"
    }

    let totalMinutes = seconds / 60  // Don't round up - show actual minutes
    if totalMinutes >= 60 {
        let hours = totalMinutes / 60
        let mins = totalMinutes % 60
        return mins > 0 ? "\(hours)h\(mins)m" : "\(hours)h"
    }
    return "\(totalMinutes)m"
}

// MARK: - Color Extension

extension Color {
    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let a, r, g, b: UInt64
        switch hex.count {
        case 3:
            (a, r, g, b) = (255, (int >> 8) * 17, (int >> 4 & 0xF) * 17, (int & 0xF) * 17)
        case 6:
            (a, r, g, b) = (255, int >> 16, int >> 8 & 0xFF, int & 0xFF)
        case 8:
            (a, r, g, b) = (int >> 24, int >> 16 & 0xFF, int >> 8 & 0xFF, int & 0xFF)
        default:
            (a, r, g, b) = (255, 0, 122, 255)
        }
        self.init(
            .sRGB,
            red: Double(r) / 255,
            green: Double(g) / 255,
            blue: Double(b) / 255,
            opacity: Double(a) / 255
        )
    }
}

// MARK: - Previews

#Preview("Expanded - Running", as: .dynamicIsland(.expanded), using: TimerActivityAttributes(
    habitName: "Morning Exercise",
    habitColor: "#5E5CE6",
    targetDuration: 600,
    habitEmoji: nil,
    habitSymbol: "figure.walk"
)) {
    StickWidgetsLiveActivity()
} contentStates: {
    TimerActivityAttributes.ContentState(
        endTime: Date().addingTimeInterval(13),
        isRunning: true,
        isPaused: false,
        isCompleted: false,
        pausedSecondsRemaining: nil
    )
}

#Preview("Expanded - Paused", as: .dynamicIsland(.expanded), using: TimerActivityAttributes(
    habitName: "Meditation",
    habitColor: "#5E5CE6",
    targetDuration: 600,
    habitEmoji: "🧘",
    habitSymbol: nil
)) {
    StickWidgetsLiveActivity()
} contentStates: {
    TimerActivityAttributes.ContentState(
        endTime: Date(),
        isRunning: false,
        isPaused: true,
        isCompleted: false,
        pausedSecondsRemaining: 245
    )
}

#Preview("Compact - Running", as: .dynamicIsland(.compact), using: TimerActivityAttributes(
    habitName: "Exercise",
    habitColor: "#FF9500",
    targetDuration: 1800,
    habitEmoji: "🏋️",
    habitSymbol: nil
)) {
    StickWidgetsLiveActivity()
} contentStates: {
    TimerActivityAttributes.ContentState(
        endTime: Date().addingTimeInterval(1500),
        isRunning: true,
        isPaused: false,
        isCompleted: false,
        pausedSecondsRemaining: nil
    )
}

#Preview("Minimal", as: .dynamicIsland(.minimal), using: TimerActivityAttributes(
    habitName: "Exercise",
    habitColor: "#FF9500",
    targetDuration: 1800,
    habitEmoji: "🏋️",
    habitSymbol: nil
)) {
    StickWidgetsLiveActivity()
} contentStates: {
    TimerActivityAttributes.ContentState(
        endTime: Date().addingTimeInterval(1500),
        isRunning: true,
        isPaused: false,
        isCompleted: false,
        pausedSecondsRemaining: nil
    )
}

#Preview("Lock Screen - Running", as: .content, using: TimerActivityAttributes(
    habitName: "Morning Exercise",
    habitColor: "#5E5CE6",
    targetDuration: 600,
    habitEmoji: nil,
    habitSymbol: "figure.walk"
)) {
    StickWidgetsLiveActivity()
} contentStates: {
    TimerActivityAttributes.ContentState(
        endTime: Date().addingTimeInterval(13),
        isRunning: true,
        isPaused: false,
        isCompleted: false,
        pausedSecondsRemaining: nil
    )
}

#Preview("Lock Screen - Completed", as: .content, using: TimerActivityAttributes(
    habitName: "Morning Exercise",
    habitColor: "#FF9500",
    targetDuration: 1800,
    habitEmoji: "🏋️",
    habitSymbol: nil
)) {
    StickWidgetsLiveActivity()
} contentStates: {
    TimerActivityAttributes.ContentState(
        endTime: Date(),
        isRunning: false,
        isPaused: false,
        isCompleted: true,
        pausedSecondsRemaining: nil
    )
}
