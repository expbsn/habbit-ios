//
//  SharedChallengesSection.swift
//  Stick
//
//  Section displaying shared challenges in FriendsView.
//

import SwiftUI
import SwiftData

struct SharedChallengesSection: View {
    @Environment(\.modelContext) private var modelContext
    @Query private var allChallenges: [SharedChallenge]
    @StateObject private var cloudKitService = CloudKitService.shared
    @StateObject private var challengeSyncService = ChallengeSyncService.shared

    let accentColor: Color
    @Binding var showingCreateChallenge: Bool
    @Binding var selectedChallenge: SharedChallenge?

    private var currentUserID: String {
        cloudKitService.currentUserID ?? ""
    }

    /// Active challenges (status == active)
    private var activeChallenges: [SharedChallenge] {
        let active = allChallenges.filter { $0.statusRaw == "active" }
        return active
    }

    /// Pending challenges where current user is the invited participant
    private var pendingChallenges: [SharedChallenge] {
        let pending = allChallenges.filter {
            $0.statusRaw == "pending" && $0.participantUserID == currentUserID
        }
        return pending
    }

    /// Pending challenges created by current user (waiting for friend to accept)
    private var sentChallenges: [SharedChallenge] {
        let sent = allChallenges.filter {
            $0.statusRaw == "pending" && $0.creatorUserID == currentUserID
        }
        return sent
    }

    var body: some View {
        Section {
            if activeChallenges.isEmpty && pendingChallenges.isEmpty && sentChallenges.isEmpty {
                emptyStateView
            } else {
                // Received pending challenges (invites) first
                ForEach(pendingChallenges) { challenge in
                    PendingChallengeRowView(
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

                // Sent challenges (waiting for friend to accept)
                ForEach(sentChallenges) { challenge in
                    SentChallengeRowView(
                        challenge: challenge,
                        currentUserID: currentUserID
                    )
                }

                // Active challenges
                ForEach(activeChallenges) { challenge in
                    ChallengeRowView(
                        challenge: challenge,
                        currentUserID: currentUserID,
                        accentColor: accentColor
                    )
                    .contentShape(Rectangle())
                    .onTapGesture {
                        selectedChallenge = challenge
                    }
                }
            }
        } header: {
            HStack {
                Text(String(localized: "challenges_title"))
                Spacer()
                Button {
                    showingCreateChallenge = true
                } label: {
                    Image(systemName: "plus")
                        .font(.caption)
                }
            }
        }
        .onAppear {
            Task {
                await challengeSyncService.syncChallenges(context: modelContext)
            }
        }
    }

    private var emptyStateView: some View {
        VStack(spacing: 8) {
            Image(systemName: "trophy")
                .font(.title)
                .foregroundStyle(.secondary)

            Text(String(localized: "challenges_empty_title"))
                .font(.subheadline.weight(.medium))

            Text(String(localized: "challenges_empty_description"))
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            Button {
                showingCreateChallenge = true
            } label: {
                Text(String(localized: "challenges_start_one"))
                    .font(.caption.weight(.semibold))
            }
            .buttonStyle(.borderless)
            .padding(.top, 4)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 16)
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

#Preview {
    List {
        SharedChallengesSection(
            accentColor: .blue,
            showingCreateChallenge: .constant(false),
            selectedChallenge: .constant(nil)
        )
    }
    .modelContainer(.preview)
}
