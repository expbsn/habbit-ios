//
//  AddFriendSheet.swift
//  Stick
//
//  Sheet for adding friends via username search or share link.
//

import SwiftUI
import SwiftData

struct AddFriendSheet: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Query private var preferences: [UserPreferences]
    @Query private var existingFriends: [FriendProfile]

    @StateObject private var cloudKitService = CloudKitService.shared

    @State private var searchText = ""
    @State private var searchResults: [(userID: String, username: String, displayName: String, avatarEmoji: String)] = []
    @State private var isSearching = false
    @State private var searchError: String?
    @State private var sentRequests: Set<String> = []

    @State private var showingShareSheet = false
    @State private var shareURL: URL?
    @State private var copied = false

    private var accentColor: Color {
        let colorValue = preferences.first?.appAccentColor ?? UserPreferences.adaptiveAccentColor
        if colorValue == UserPreferences.adaptiveAccentColor {
            return Color.primary
        }
        return Color(hex: colorValue)
    }

    /// IDs of users we're already connected with
    private var existingFriendIDs: Set<String> {
        Set(existingFriends.map { $0.cloudUserID })
    }

    var body: some View {
        NavigationStack {
            List {
                // Search Section
                Section {
                    HStack {
                        Image(systemName: "magnifyingglass")
                            .foregroundStyle(.secondary)
                        TextField(String(localized: "friends_search_placeholder"), text: $searchText)
                            .textContentType(.name)
                            .autocorrectionDisabled()
                            .onSubmit {
                                Task { await performSearch() }
                            }
                        if isSearching {
                            ProgressView()
                        } else if !searchText.isEmpty {
                            Button {
                                searchText = ""
                                searchResults = []
                            } label: {
                                Image(systemName: "xmark.circle.fill")
                                    .foregroundStyle(.secondary)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                } header: {
                    Text(String(localized: "friends_search_header"))
                } footer: {
                    Text(String(localized: "friends_search_footer"))
                }

                // Search Results
                if !searchResults.isEmpty {
                    Section {
                        ForEach(searchResults, id: \.userID) { result in
                            HStack(spacing: 12) {
                                Text(result.avatarEmoji)
                                    .font(.title2)
                                    .frame(width: 44, height: 44)
                                    .background(accentColor.opacity(0.15))
                                    .clipShape(Circle())

                                VStack(alignment: .leading, spacing: 2) {
                                    Text(result.displayName)
                                        .fontWeight(.medium)
                                    Text("@\(result.username)")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }

                                Spacer()

                                if existingFriendIDs.contains(result.userID) {
                                    Text(String(localized: "friends_already_added"))
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                } else if sentRequests.contains(result.userID) {
                                    Image(systemName: "checkmark.circle.fill")
                                        .foregroundStyle(.green)
                                } else {
                                    Button {
                                        Task { await sendRequest(to: result) }
                                    } label: {
                                        Image(systemName: "person.badge.plus")
                                            .font(.title3)
                                            .foregroundStyle(accentColor)
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                            .padding(.vertical, 4)
                        }
                    } header: {
                        Text(String(localized: "friends_search_results"))
                    }
                } else if !searchText.isEmpty && !isSearching {
                    Section {
                        HStack {
                            Spacer()
                            VStack(spacing: 8) {
                                Image(systemName: "person.slash")
                                    .font(.title)
                                    .foregroundStyle(.secondary)
                                Text(String(localized: "friends_no_results"))
                                    .foregroundStyle(.secondary)
                            }
                            .padding(.vertical, 20)
                            Spacer()
                        }
                    }
                }

                // Error
                if let error = searchError {
                    Section {
                        Text(error)
                            .foregroundStyle(.red)
                            .font(.caption)
                    }
                }

                // Share Link Section
                Section {
                    Button {
                        shareInviteLink()
                    } label: {
                        HStack {
                            Image(systemName: "square.and.arrow.up")
                            Text(String(localized: "friends_share_link"))
                            Spacer()
                            Image(systemName: "chevron.right")
                                .foregroundStyle(.secondary)
                        }
                    }

                    Button {
                        copyInviteLink()
                    } label: {
                        HStack {
                            Image(systemName: copied ? "checkmark" : "doc.on.doc")
                            Text(copied ? String(localized: "friends_link_copied") : String(localized: "friends_copy_link"))
                            Spacer()
                        }
                    }
                    .foregroundStyle(copied ? .green : accentColor)
                } header: {
                    Text(String(localized: "friends_or_share_link"))
                } footer: {
                    Text(String(localized: "friends_invite_info"))
                }
            }
            .navigationTitle(String(localized: "friends_add_friend"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(String(localized: "timer_done")) {
                        dismiss()
                    }
                }
            }
            .sheet(isPresented: $showingShareSheet) {
                if let url = shareURL {
                    ShareSheet(items: [url])
                }
            }
            .onChange(of: searchText) { _, newValue in
                // Auto-search after typing stops
                let trimmed = newValue.trimmingCharacters(in: .whitespacesAndNewlines)
                if trimmed.count >= 2 {
                    Task {
                        try? await Task.sleep(nanoseconds: 500_000_000) // 0.5s debounce
                        if searchText == newValue { // Only search if text hasn't changed
                            await performSearch()
                        }
                    }
                } else {
                    searchResults = []
                }
            }
        }
    }

    private func performSearch() async {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard query.count >= 2 else {
            searchResults = []
            return
        }

        isSearching = true
        searchError = nil

        do {
            searchResults = try await cloudKitService.searchUsers(query: query)
        } catch {
            searchError = error.localizedDescription
            searchResults = []
        }

        isSearching = false
    }

    private func sendRequest(to user: (userID: String, username: String, displayName: String, avatarEmoji: String)) async {
        do {
            // Pass the profile data we already have from search results
            try await FriendSyncService.shared.sendFriendRequest(
                toUserID: user.userID,
                displayName: user.displayName,
                avatarEmoji: user.avatarEmoji,
                context: modelContext
            )
            sentRequests.insert(user.userID)
        } catch {
            searchError = error.localizedDescription
        }
    }

    private func shareInviteLink() {
        if let url = cloudKitService.generateInviteLink() {
            shareURL = url
            showingShareSheet = true
        }
    }

    private func copyInviteLink() {
        if let url = cloudKitService.generateInviteLink() {
            UIPasteboard.general.url = url
            withAnimation {
                copied = true
            }

            // Reset after 2 seconds
            DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                withAnimation {
                    copied = false
                }
            }
        }
    }
}

// MARK: - Share Sheet

struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}

#Preview {
    AddFriendSheet()
        .modelContainer(.preview)
}
