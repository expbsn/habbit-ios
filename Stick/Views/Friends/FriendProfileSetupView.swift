//
//  FriendProfileSetupView.swift
//  Stick
//
//  Initial profile setup view for the friends feature.
//

import SwiftUI
import SwiftData

struct FriendProfileSetupView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Query private var preferences: [UserPreferences]
    @Query private var existingProfiles: [MyCloudProfile]

    @StateObject private var cloudKitService = CloudKitService.shared

    @State private var username = ""
    @State private var displayName = ""
    @State private var selectedEmoji = "😊"
    @State private var motivationalQuote = ""
    @State private var isDiscoverable = true
    @State private var isSaving = false
    @State private var isCheckingUsername = false
    @State private var usernameAvailable: Bool?
    @State private var errorMessage: String?

    private var accentColor: Color {
        let colorValue = preferences.first?.appAccentColor ?? UserPreferences.adaptiveAccentColor
        if colorValue == UserPreferences.adaptiveAccentColor {
            return Color.primary
        }
        return Color(hex: colorValue)
    }

    /// Toggle tint that falls back to green when adaptive mode is on
    private var toggleTint: Color {
        let colorValue = preferences.first?.appAccentColor ?? UserPreferences.adaptiveAccentColor
        if colorValue == UserPreferences.adaptiveAccentColor {
            return Color.green
        }
        return Color(hex: colorValue)
    }

    private var existingProfile: MyCloudProfile? {
        existingProfiles.first
    }

    /// Sanitized username (lowercase, no spaces, alphanumeric + underscore only)
    private var sanitizedUsername: String {
        username
            .lowercased()
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .filter { $0.isLetter || $0.isNumber || $0 == "_" }
    }

    private var isUsernameValid: Bool {
        let clean = sanitizedUsername
        return clean.count >= 3 && clean.count <= 20
    }

    private var isValid: Bool {
        isUsernameValid &&
        !displayName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        usernameAvailable == true
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

                            if !sanitizedUsername.isEmpty {
                                Text("@\(sanitizedUsername)")
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        Spacer()
                    }
                    .padding(.vertical, 16)
                    .listRowBackground(Color.clear)
                }

                // Username Section
                Section {
                    HStack {
                        Text("@")
                            .foregroundStyle(.secondary)
                        TextField(String(localized: "friends_username_placeholder"), text: $username)
                            .textContentType(.username)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .onChange(of: username) { _, newValue in
                                // Reset availability when typing
                                usernameAvailable = nil
                                // Debounce check
                                let sanitized = sanitizedUsername
                                if sanitized.count >= 3 {
                                    Task {
                                        try? await Task.sleep(nanoseconds: 500_000_000)
                                        if sanitizedUsername == sanitized {
                                            await checkUsernameAvailability()
                                        }
                                    }
                                }
                            }

                        if isCheckingUsername {
                            ProgressView()
                                .scaleEffect(0.8)
                        } else if let available = usernameAvailable {
                            Image(systemName: available ? "checkmark.circle.fill" : "xmark.circle.fill")
                                .foregroundStyle(available ? .green : .red)
                        }
                    }
                } header: {
                    Text(String(localized: "friends_username_header"))
                } footer: {
                    if !isUsernameValid && !username.isEmpty {
                        Text(String(localized: "friends_username_requirements"))
                            .foregroundStyle(.red)
                    } else if usernameAvailable == false {
                        Text(String(localized: "friends_username_taken"))
                            .foregroundStyle(.red)
                    } else {
                        Text(String(localized: "friends_username_footer"))
                    }
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

                // Privacy Section
                Section {
                    Toggle(String(localized: "friends_discoverable"), isOn: $isDiscoverable)
                        .tint(toggleTint)
                } header: {
                    Text(String(localized: "friends_privacy_header"))
                } footer: {
                    Text(String(localized: "friends_discoverable_footer"))
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
            .navigationTitle(String(localized: "friends_setup_profile"))
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
                if let profile = existingProfile {
                    // Load from existing cloud profile
                    username = profile.username
                    displayName = profile.displayName
                    selectedEmoji = profile.avatarEmoji
                    motivationalQuote = profile.motivationalQuote ?? ""
                    isDiscoverable = profile.isDiscoverable
                    // Mark as available since it's their own username
                    if !profile.username.isEmpty {
                        usernameAvailable = true
                    }
                } else if let userPrefs = preferences.first {
                    // Pre-fill from Settings profile if no cloud profile exists
                    displayName = userPrefs.userName ?? ""
                    motivationalQuote = userPrefs.motivationQuote ?? ""
                }
            }
            .interactiveDismissDisabled(isSaving)
        }
    }

    private func checkUsernameAvailability() async {
        let clean = sanitizedUsername
        guard clean.count >= 3 else {
            usernameAvailable = nil
            return
        }

        isCheckingUsername = true

        do {
            let taken = try await cloudKitService.isUsernameTaken(clean)
            usernameAvailable = !taken
        } catch {
            usernameAvailable = nil
        }

        isCheckingUsername = false
    }

    private func saveProfile() async {
        isSaving = true
        errorMessage = nil

        let profile = existingProfile ?? MyCloudProfile()
        let trimmedUsername = sanitizedUsername
        let trimmedName = displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedQuote = motivationalQuote.trimmingCharacters(in: .whitespacesAndNewlines)

        profile.username = trimmedUsername
        profile.displayName = trimmedName
        profile.avatarEmoji = selectedEmoji
        profile.motivationalQuote = trimmedQuote.isEmpty ? nil : trimmedQuote
        profile.isDiscoverable = isDiscoverable

        if existingProfile == nil {
            modelContext.insert(profile)
        }

        // Sync to UserPreferences (keep Settings profile in sync)
        if let userPrefs = preferences.first {
            userPrefs.userName = trimmedName.isEmpty ? nil : trimmedName
            userPrefs.motivationQuote = trimmedQuote.isEmpty ? nil : trimmedQuote
        }

        do {
            try modelContext.save()

            // Sync to CloudKit
            try await cloudKitService.saveUserProfile(profile)

            dismiss()
        } catch let error as CloudKitError {
            if case .usernameTaken = error {
                usernameAvailable = false
                errorMessage = String(localized: "friends_username_taken")
            } else {
                errorMessage = error.localizedDescription
            }
        } catch {
            errorMessage = error.localizedDescription
        }

        isSaving = false
    }
}

#Preview {
    FriendProfileSetupView()
        .modelContainer(.preview)
}
