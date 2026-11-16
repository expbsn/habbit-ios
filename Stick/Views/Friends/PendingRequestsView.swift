//
//  PendingRequestsView.swift
//  Stick
//
//  View for managing pending friend requests.
//

import SwiftUI
import SwiftData

struct PendingRequestsView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Query private var preferences: [UserPreferences]
    @Query(filter: #Predicate<FriendProfile> { $0.connectionStatus == "pending" }) private var pendingFriends: [FriendProfile]

    @StateObject private var friendSyncService = FriendSyncService.shared

    @State private var processingIDs: Set<String> = []

    private var accentColor: Color {
        let colorValue = preferences.first?.appAccentColor ?? UserPreferences.adaptiveAccentColor
        if colorValue == UserPreferences.adaptiveAccentColor {
            return Color.primary
        }
        return Color(hex: colorValue)
    }

    private var incomingRequests: [FriendProfile] {
        pendingFriends.filter { $0.isPendingIncoming }
    }

    private var outgoingRequests: [FriendProfile] {
        pendingFriends.filter { $0.isPendingOutgoing }
    }

    var body: some View {
        NavigationStack {
            List {
                // Incoming Requests
                if !incomingRequests.isEmpty {
                    Section {
                        ForEach(incomingRequests) { friend in
                            incomingRequestRow(friend)
                        }
                    } header: {
                        Text(String(localized: "friends_incoming_requests"))
                    }
                }

                // Outgoing Requests
                if !outgoingRequests.isEmpty {
                    Section {
                        ForEach(outgoingRequests) { friend in
                            outgoingRequestRow(friend)
                        }
                    } header: {
                        Text(String(localized: "friends_outgoing_requests"))
                    } footer: {
                        Text(String(localized: "friends_outgoing_footer"))
                    }
                }

                // Empty State
                if pendingFriends.isEmpty {
                    Section {
                        ContentUnavailableView {
                            Label(String(localized: "friends_no_pending"), systemImage: "person.2")
                        } description: {
                            Text(String(localized: "friends_no_pending_description"))
                        }
                        .listRowBackground(Color.clear)
                    }
                }
            }
            .listStyle(.insetGrouped)
            .navigationTitle(String(localized: "friends_pending_title"))
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

    // MARK: - Incoming Request Row

    private func incomingRequestRow(_ friend: FriendProfile) -> some View {
        HStack(spacing: 12) {
            Text(friend.avatarEmoji)
                .font(.title2)
                .frame(width: 44, height: 44)
                .background(Color(.systemGray5))
                .clipShape(Circle())

            VStack(alignment: .leading, spacing: 2) {
                Text(friend.displayName)
                    .font(.body.weight(.medium))

                Text(String(localized: "friends_wants_to_connect"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            if processingIDs.contains(friend.cloudUserID) {
                ProgressView()
                    .scaleEffect(0.8)
            } else {
                HStack(spacing: 8) {
                    Button {
                        Task {
                            await declineRequest(friend)
                        }
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.title2)
                            .foregroundStyle(.red)
                    }
                    .buttonStyle(.plain)

                    Button {
                        Task {
                            await acceptRequest(friend)
                        }
                    } label: {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.title2)
                            .foregroundStyle(.green)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(.vertical, 4)
    }

    // MARK: - Outgoing Request Row

    private func outgoingRequestRow(_ friend: FriendProfile) -> some View {
        HStack(spacing: 12) {
            Text(friend.avatarEmoji)
                .font(.title2)
                .frame(width: 44, height: 44)
                .background(Color(.systemGray5))
                .clipShape(Circle())

            VStack(alignment: .leading, spacing: 2) {
                Text(friend.displayName)
                    .font(.body.weight(.medium))

                Text(String(localized: "friends_request_pending"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Image(systemName: "clock")
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 4)
    }

    // MARK: - Actions

    private func acceptRequest(_ friend: FriendProfile) async {
        processingIDs.insert(friend.cloudUserID)

        do {
            try await friendSyncService.acceptFriendRequest(friend, context: modelContext)
        } catch {
            print("Failed to accept request: \(error)")
        }

        processingIDs.remove(friend.cloudUserID)
    }

    private func declineRequest(_ friend: FriendProfile) async {
        processingIDs.insert(friend.cloudUserID)

        do {
            try await friendSyncService.declineFriendRequest(friend, context: modelContext)
        } catch {
            print("Failed to decline request: \(error)")
        }

        processingIDs.remove(friend.cloudUserID)
    }
}

#Preview {
    PendingRequestsView()
        .modelContainer(.preview)
}
