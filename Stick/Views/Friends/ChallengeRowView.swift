//
//  ChallengeRowView.swift
//  Stick
//
//  Row component for displaying a challenge in the list.
//

import SwiftUI

struct ChallengeRowView: View {
    let challenge: SharedChallenge
    let currentUserID: String
    let accentColor: Color

    var body: some View {
        HStack(spacing: 12) {
            // Emoji icon
            Text(challenge.habitEmoji)
                .font(.title2)
                .frame(width: 44, height: 44)
                .background(Color(hex: challenge.habitColor).opacity(0.2))
                .clipShape(RoundedRectangle(cornerRadius: 12))

            VStack(alignment: .leading, spacing: 4) {
                // Challenge name
                Text(challenge.habitName)
                    .font(.body.weight(.medium))

                // Subtitle with friend name and progress
                HStack(spacing: 4) {
                    Text(String(localized: "challenges_with"))
                    Text(challenge.friendDisplayName(for: currentUserID))
                        .foregroundStyle(.secondary)

                    if challenge.isActive {
                        Text("•")
                            .foregroundStyle(.secondary)
                        Text(challenge.progressDisplay)
                            .foregroundStyle(.secondary)
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)

                // Progress indicators
                if challenge.isActive {
                    if challenge.isCollaborative {
                        // Collaborative: show combined progress
                        HStack(spacing: 4) {
                            Image(systemName: "person.2.fill")
                                .font(.caption2)
                            Text("\(challenge.combinedCompletedDays)/\(challenge.targetDays)")
                                .fontWeight(.semibold)
                            Image(systemName: "checkmark")
                                .font(.caption2)
                        }
                        .font(.caption2)
                        .foregroundStyle(.primary)
                    } else {
                        // Competitive: show individual progress
                        HStack(spacing: 16) {
                            progressBadge(
                                label: String(localized: "friends_you"),
                                count: challenge.myCompletedDays(for: currentUserID),
                                isMe: true
                            )

                            progressBadge(
                                label: challenge.friendDisplayName(for: currentUserID),
                                count: challenge.friendCompletedDays(for: currentUserID),
                                isMe: false
                            )
                        }
                        .font(.caption2)
                    }
                }
            }

            Spacer()

            // Status indicator or chevron
            if challenge.isPending {
                Text(String(localized: "challenges_pending"))
                    .font(.caption)
                    .foregroundStyle(.orange)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.orange.opacity(0.15))
                    .clipShape(Capsule())
            } else {
                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
    }

    @ViewBuilder
    private func progressBadge(label: String, count: Int, isMe: Bool) -> some View {
        HStack(spacing: 4) {
            Text(label)
                .foregroundStyle(isMe ? .primary : .secondary)
            Text("\(count)")
                .fontWeight(.semibold)
            Image(systemName: "checkmark")
                .font(.caption2)
        }
        .foregroundStyle(isMe ? .primary : .secondary)
    }
}

// MARK: - Pending Challenge Row

struct PendingChallengeRowView: View {
    let challenge: SharedChallenge
    let currentUserID: String
    let accentColor: Color
    let onAccept: () -> Void
    let onDecline: () -> Void

    @Environment(\.colorScheme) private var colorScheme

    // Adaptive-safe tint: avoids white button in dark mode when accent is Color.primary
    private var buttonTint: Color {
        if accentColor == Color.primary {
            return colorScheme == .dark ? Color(.systemGray2) : Color(.label)
        }
        return accentColor
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                // Emoji icon
                Text(challenge.habitEmoji)
                    .font(.title2)
                    .frame(width: 44, height: 44)
                    .background(Color(hex: challenge.habitColor).opacity(0.2))
                    .clipShape(RoundedRectangle(cornerRadius: 12))

                VStack(alignment: .leading, spacing: 2) {
                    Text(challenge.habitName)
                        .font(.body.weight(.medium))

                    HStack(spacing: 4) {
                        Text(String(localized: "challenges_from"))
                        Text(challenge.friendDisplayName(for: currentUserID))
                        Text("·")
                        Text(String(format: String(localized: "challenges_days_format"), challenge.targetDays))
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }

                Spacer()
            }

            // Action buttons
            HStack(spacing: 12) {
                Button {
                    onDecline()
                } label: {
                    Text(String(localized: "challenges_decline"))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                }
                .buttonStyle(.bordered)

                Button {
                    onAccept()
                } label: {
                    Text(String(localized: "challenges_accept"))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                }
                .buttonStyle(.borderedProminent)
                .tint(buttonTint)
            }
        }
        .padding(.vertical, 4)
    }
}

// MARK: - Sent Challenge Row (waiting for friend to accept)

struct SentChallengeRowView: View {
    let challenge: SharedChallenge
    let currentUserID: String

    var body: some View {
        HStack(spacing: 12) {
            // Emoji icon
            Text(challenge.habitEmoji)
                .font(.title2)
                .frame(width: 44, height: 44)
                .background(Color(hex: challenge.habitColor).opacity(0.2))
                .clipShape(RoundedRectangle(cornerRadius: 12))

            VStack(alignment: .leading, spacing: 4) {
                // Challenge name
                Text(challenge.habitName)
                    .font(.body.weight(.medium))

                // Subtitle
                HStack(spacing: 4) {
                    Text(String(localized: "challenges_sent_to"))
                    Text(challenge.friendDisplayName(for: currentUserID))
                        .foregroundStyle(.secondary)
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }

            Spacer()

            // Waiting badge
            Text(String(localized: "challenges_waiting"))
                .font(.caption)
                .foregroundStyle(.blue)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Color.blue.opacity(0.15))
                .clipShape(Capsule())
        }
        .padding(.vertical, 4)
    }
}

#Preview {
    List {
        ChallengeRowView(
            challenge: {
                let c = SharedChallenge(
                    creatorUserID: "user1",
                    participantUserID: "user2",
                    habitName: "Morning Meditation",
                    habitEmoji: "🧘",
                    habitColor: "#5856D6",
                    targetDays: 30
                )
                c.statusRaw = "active"
                c.startDate = Date()
                c.myCompletedDays = 10
                c.friendCompletedDays = 12
                c.participantDisplayName = "Sarah"
                return c
            }(),
            currentUserID: "user1",
            accentColor: .blue
        )
    }
}
