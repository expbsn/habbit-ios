//
//  WeeklyWrapNotificationCard.swift
//  Stick
//
//  Notification card displayed when a weekly wrap is ready.
//

import SwiftUI

struct WeeklyWrapNotificationCard: View {
    let wrap: WeeklyWrap
    let onTap: () -> Void
    let onDismiss: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            // Grey circle with emoji
            ZStack {
                Circle()
                    .fill(Color.gray.opacity(0.2))
                    .frame(width: 44, height: 44)

                Text("👀")
                    .font(.title2)
            }

            // Text content
            VStack(alignment: .leading, spacing: 2) {
                Text(String(localized: "weekly_wrap_notification_title"))
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)

                Text(String(localized: "weekly_wrap_notification_subtitle"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()
        }
        .padding(16)
        #if canImport(UIKit)
        .background(Color(uiColor: .secondarySystemGroupedBackground))
        #else
        .background(Color(nsColor: .controlBackgroundColor))
        #endif
        .clipShape(RoundedRectangle(cornerRadius: 24))
        .contentShape(RoundedRectangle(cornerRadius: 24))
        .onTapGesture {
            onTap()
        }
        .overlay(alignment: .topTrailing) {
            // Dismiss button
            Button(action: onDismiss) {
                Image(systemName: "xmark")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
                    .frame(width: 24, height: 24)
                    .background(Color.gray.opacity(0.2))
                    .clipShape(Circle())
            }
            .buttonStyle(.plain)
            .offset(x: -8, y: 8)
        }
    }
}

#Preview {
    WeeklyWrapNotificationCard(
        wrap: {
            let calendar = Calendar.current
            let today = Date()
            let lastMonday = calendar.date(byAdding: .day, value: -7, to: today)!
            let lastSunday = calendar.date(byAdding: .day, value: -1, to: today)!

            return WeeklyWrap(
                weekStartDate: lastMonday,
                weekEndDate: lastSunday,
                totalCompletions: 28,
                completionRate: 0.85,
                perfectDays: 4,
                bestStreak: 5,
                totalMinutesTracked: 225,
                mostConsistentHabitName: "Morning Run",
                totalHabitsTracked: 5,
                totalScheduledCompletions: 33
            )
        }(),
        onTap: {},
        onDismiss: {}
    )
    .padding()
}
