//
//  EditProfileSheet.swift
//  Stick
//
//  Sheet for editing user profile from Friends tab or Settings.
//

import SwiftUI
import SwiftData

struct EditProfileSheet: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Query private var preferences: [UserPreferences]
    @Query private var cloudProfiles: [MyCloudProfile]

    @StateObject private var cloudKitService = CloudKitService.shared

    @State private var displayName = ""
    @State private var selectedEmoji = "😊"
    @State private var motivationalQuote = ""
    @State private var isSaving = false
    @State private var errorMessage: String?

    private var accentColor: Color {
        let colorValue = preferences.first?.appAccentColor ?? UserPreferences.adaptiveAccentColor
        if colorValue == UserPreferences.adaptiveAccentColor {
            return Color.primary
        }
        return Color(hex: colorValue)
    }

    private var currentProfile: MyCloudProfile? {
        cloudProfiles.first
    }

    private var isValid: Bool {
        !displayName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        NavigationStack {
            Form {
                // Preview Section
                Section {
                    HStack {
                        Spacer()
                        VStack(spacing: 8) {
                            Text(selectedEmoji)
                                .font(.system(size: 60))
                                .frame(width: 100, height: 100)
                                .background(accentColor.opacity(0.15))
                                .clipShape(Circle())

                            Text(displayName.isEmpty ? String(localized: "friends_your_name") : displayName)
                                .font(.title3.bold())
                                .foregroundStyle(displayName.isEmpty ? .secondary : .primary)

                            if let username = currentProfile?.username, !username.isEmpty {
                                Text("@\(username)")
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        Spacer()
                    }
                    .padding(.vertical, 16)
                    .listRowBackground(Color.clear)
                }

                // Name Section
                Section {
                    TextField(String(localized: "friends_display_name"), text: $displayName)
                        .textContentType(.name)
                        .autocorrectionDisabled()
                } header: {
                    Text(String(localized: "friends_name_header"))
                } footer: {
                    Text(String(localized: "friends_name_footer"))
                }

                // Avatar Section
                Section {
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 8), spacing: 12) {
                        ForEach(MyCloudProfile.avatarOptions, id: \.self) { emoji in
                            Button {
                                selectedEmoji = emoji
                            } label: {
                                Text(emoji)
                                    .font(.title2)
                                    .frame(width: 36, height: 36)
                                    .background(selectedEmoji == emoji ? accentColor.opacity(0.3) : Color.clear)
                                    .clipShape(RoundedRectangle(cornerRadius: 8))
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 8)
                                            .stroke(selectedEmoji == emoji ? accentColor : Color.clear, lineWidth: 2)
                                    )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.vertical, 8)
                } header: {
                    Text(String(localized: "friends_avatar_header"))
                }

                // Motivational Quote Section
                Section {
                    TextField(String(localized: "settings_motivation_placeholder"), text: $motivationalQuote, axis: .vertical)
                        .lineLimit(2...4)
                } header: {
                    Text(String(localized: "settings_motivation_quote"))
                } footer: {
                    Text(String(localized: "friends_quote_footer"))
                }

                // Error Message
                if let error = errorMessage {
                    Section {
                        Text(error)
                            .foregroundStyle(.red)
                            .font(.caption)
                    }
                }
            }
            .navigationTitle(String(localized: "settings_edit_profile"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(String(localized: "settings_cancel")) {
                        dismiss()
                    }
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button(String(localized: "settings_save")) {
                        Task {
                            await saveProfile()
                        }
                    }
                    .disabled(!isValid || isSaving)
                    .fontWeight(.semibold)
                }
            }
            .onAppear {
                loadProfile()
            }
            .interactiveDismissDisabled(isSaving)
        }
    }

    private func loadProfile() {
        if let profile = currentProfile {
            displayName = profile.displayName
            selectedEmoji = profile.avatarEmoji
            motivationalQuote = profile.motivationalQuote ?? ""
        } else if let userPrefs = preferences.first {
            // Fall back to UserPreferences if no cloud profile
            displayName = userPrefs.userName ?? ""
            motivationalQuote = userPrefs.motivationQuote ?? ""
        }
    }

    private func saveProfile() async {
        isSaving = true
        errorMessage = nil

        let trimmedName = displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedQuote = motivationalQuote.trimmingCharacters(in: .whitespacesAndNewlines)

        // Update cloud profile
        if let profile = currentProfile {
            profile.displayName = trimmedName
            profile.avatarEmoji = selectedEmoji
            profile.motivationalQuote = trimmedQuote.isEmpty ? nil : trimmedQuote
            profile.isSynced = false
        }

        // Sync to UserPreferences (keep Settings profile in sync)
        if let userPrefs = preferences.first {
            userPrefs.userName = trimmedName.isEmpty ? nil : trimmedName
            userPrefs.motivationQuote = trimmedQuote.isEmpty ? nil : trimmedQuote
        }

        do {
            try modelContext.save()

            // Sync to CloudKit if profile exists
            if let profile = currentProfile {
                try await cloudKitService.saveUserProfile(profile)
            }

            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }

        isSaving = false
    }
}

#Preview {
    EditProfileSheet()
        .modelContainer(.preview)
}
