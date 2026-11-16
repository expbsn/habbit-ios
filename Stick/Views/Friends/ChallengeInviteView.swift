//
//  ChallengeInviteView.swift
//  Stick
//
//  View for displaying and managing pending challenge invites.
//

import SwiftUI
import SwiftData

struct ChallengeInviteView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Query private var preferences: [UserPreferences]

    @StateObject private var cloudKitService = CloudKitService.shared
    @StateObject private var challengeSyncService = ChallengeSyncService.shared

    private var accentColor: Color {
        let colorValue = preferences.first?.appAccentColor ?? UserPreferences.adaptiveAccentColor
        if colorValue == UserPreferences.adaptiveAccentColor {
            return Color.primary
        }
        return Color(hex: colorValue)
    }

    private var currentUserID: String {
        cloudKitService.currentUserID ?? ""
    }

    @Query private var allChallenges: [SharedChallenge]

    private var pendingInvites: [SharedChallenge] {
        allChallenges.filter { $0.isPending && $0.participantUserID == currentUserID }
    }

    var body: some View {
        NavigationStack {
            Group {
                if pendingInvites.isEmpty {
                    emptyStateView
                } else {
                    List {
                        ForEach(pendingInvites) { challenge in
                            InviteCard(
                                challenge: challenge,
                                currentUserID: currentUserID,
                                accentColor: accentColor,
                                onAccept: {
                                    acceptChallenge(challenge)
                                },
                                onDecline: {
                                    declineChallenge(challenge)
                                }
                            )
                        }
                    }
                    .listStyle(.insetGrouped)
                }
            }
            .dimThemeBackground()
            .navigationTitle(String(localized: "challenges_invites_title"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(String(localized: "timer_done")) {
                        dismiss()
                    }
                }
            }
        }
    }

    private var emptyStateView: some View {
        ContentUnavailableView {
            Label(String(localized: "challenges_no_invites"), systemImage: "trophy")
        } description: {
            Text(String(localized: "challenges_no_invites_description"))
        }
    }

    private func acceptChallenge(_ challenge: SharedChallenge) {
        Task {
            do {
                try await challengeSyncService.acceptChallenge(challenge, context: modelContext)
            } catch {
                print("Failed to accept challenge: \(error)")
            }
        }
    }

    private func declineChallenge(_ challenge: SharedChallenge) {
        Task {
            do {
                try await challengeSyncService.declineChallenge(challenge, context: modelContext)
            } catch {
                print("Failed to decline challenge: \(error)")
            }
        }
    }
}

// MARK: - Invite Card

private struct InviteCard: View {
    let challenge: SharedChallenge
    let currentUserID: String
    let accentColor: Color
    let onAccept: () -> Void
    let onDecline: () -> Void

    @State private var isAccepting = false
    @State private var isDeclining = false
    @Environment(\.colorScheme) private var colorScheme

    private var buttonTint: Color {
        if accentColor == Color.primary {
            return colorScheme == .dark ? Color(.systemGray2) : Color(.label)
        }
        return accentColor
    }

    var body: some View {
        VStack(spacing: 16) {
            // Header
            HStack(spacing: 12) {
                Text(challenge.habitEmoji)
                    .font(.system(size: 44))
                    .frame(width: 60, height: 60)
                    .background(Color(hex: challenge.habitColor).opacity(0.2))
                    .clipShape(RoundedRectangle(cornerRadius: 16))

                VStack(alignment: .leading, spacing: 4) {
                    Text(challenge.habitName)
                        .font(.headline)

                    HStack(spacing: 4) {
                        Text(String(localized: "challenges_from"))
                        Text(challenge.friendDisplayName(for: currentUserID))
                    }
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                }

                Spacer()
            }

            // Details
            HStack(spacing: 24) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(String(localized: "challenges_duration"))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(String(format: String(localized: "challenges_days_format"), challenge.targetDays))
                        .font(.subheadline.weight(.medium))
                }

                Spacer()
            }

            // Action buttons
            HStack(spacing: 12) {
                Button {
                    isDeclining = true
                    onDecline()
                } label: {
                    if isDeclining {
                        ProgressView()
                            .frame(maxWidth: .infinity)
                    } else {
                        Text(String(localized: "challenges_decline"))
                            .frame(maxWidth: .infinity)
                    }
                }
                .buttonStyle(.bordered)
                .disabled(isAccepting || isDeclining)

                Button {
                    isAccepting = true
                    onAccept()
                } label: {
                    if isAccepting {
                        ProgressView()
                            .frame(maxWidth: .infinity)
                    } else {
                        Text(String(localized: "challenges_accept"))
                            .frame(maxWidth: .infinity)
                    }
                }
                .buttonStyle(.borderedProminent)
                .tint(buttonTint)
                .disabled(isAccepting || isDeclining)
            }
        }
        .padding()
    }
}

#Preview {
    ChallengeInviteView()
        .modelContainer(.preview)
}
