//
//  SharedChallengeHabitRow.swift
//  Stick
//
//  Row displaying a shared challenge in the habit list — identical layout to HabitRowView.
//

import SwiftUI

struct SharedChallengeHabitRow: View {
    let challenge: SharedChallenge
    let currentUserID: String
    let isCompleted: Bool
    let accentColor: Color
    let onMarkComplete: () -> Void

    private var partnerEmoji: String {
        challenge.friendAvatarEmoji(for: currentUserID)
    }

    private var progressFraction: Double {
        guard challenge.targetDays > 0 else { return 0 }
        return Double(challenge.myCompletedDays) / Double(challenge.targetDays)
    }

    var body: some View {
        HStack(spacing: 12) {
            // Completion circle — matches simpleCompletionButton in HabitRowView
            completionButton

            // Habit icon with partner emoji on bottom-right
            challengeIcon

            // Name + metadata
            VStack(alignment: .leading, spacing: 4) {
                Text(challenge.habitName)
                    .font(.body.weight(.medium))
                    .strikethrough(isCompleted, color: .secondary)
                    .foregroundStyle(isCompleted ? .secondary : .primary)

                challengeMetadata
            }

            Spacer()
        }
        .contentShape(Rectangle())
    }

    // MARK: - Subviews

    private var completionButton: some View {
        ZStack {
            Circle()
                .stroke(Color(hex: challenge.habitColor), lineWidth: 2)
                .frame(width: 28, height: 28)

            if isCompleted {
                Circle()
                    .fill(Color(hex: challenge.habitColor))
                    .frame(width: 28, height: 28)

                Image(systemName: "checkmark")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(.white)
            }
        }
        .contentShape(Circle())
        .highPriorityGesture(
            TapGesture().onEnded {
                if !isCompleted { onMarkComplete() }
            }
        )
    }

    private var challengeIcon: some View {
        ZStack(alignment: .bottomTrailing) {
            Text(challenge.habitEmoji)
                .font(.title2)
                .frame(width: 40, height: 40)
                .background(Color(hex: challenge.habitColor).opacity(0.15))
                .clipShape(RoundedRectangle(cornerRadius: 10))

            // Partner emoji badge — mirrors HealthKit badge positioning
            if !partnerEmoji.isEmpty {
                Text(partnerEmoji)
                    .font(.system(size: 11))
                    .offset(x: 4, y: 4)
            }
        }
    }

    @ViewBuilder
    private var challengeMetadata: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
                Text(challenge.friendDisplayName(for: currentUserID))
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)

                Text("\(challenge.myCompletedDays)/\(challenge.targetDays)")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                if challenge.healthKitType != nil {
                    Image(systemName: "heart.fill")
                        .font(.caption2)
                        .foregroundStyle(.red)
                }
            }

        }
    }
}
