//
//  MyCloudProfile.swift
//  Stick
//
//  User's own CloudKit profile settings stored locally.
//

import Foundation
import SwiftData

/// The user's CloudKit profile configuration, stored locally.
/// This is synced to CloudKit's public database for discoverability.
@Model
final class MyCloudProfile {
    /// Unique CloudKit record ID for this user
    var cloudRecordID: String?

    /// Unique username for finding this user (e.g., "johnsmith")
    var username: String = ""

    /// Display name shown to friends
    var displayName: String = ""

    /// Avatar emoji (single emoji character)
    var avatarEmoji: String = "😊"

    /// Whether this user can be discovered by others
    var isDiscoverable: Bool = true

    /// User's motivational quote
    var motivationalQuote: String?

    /// Whether the profile has been synced to CloudKit
    var isSynced: Bool = false

    /// Last time this profile was synced to CloudKit
    var lastSyncedDate: Date?

    /// Date this profile was created
    var createdDate: Date = Date()

    init(
        username: String = "",
        displayName: String = "",
        avatarEmoji: String = "😊",
        isDiscoverable: Bool = true
    ) {
        self.username = username
        self.displayName = displayName
        self.avatarEmoji = avatarEmoji
        self.isDiscoverable = isDiscoverable
        self.isSynced = false
        self.createdDate = Date()
    }

    /// Check if the profile is complete and ready to be used
    var isComplete: Bool {
        !username.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        !displayName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        !avatarEmoji.isEmpty
    }

    /// Formatted username with @ prefix
    var formattedUsername: String {
        username.isEmpty ? "" : "@\(username)"
    }

    // MARK: - Singleton Access

    /// Fetches the existing profile or creates one if none exists.
    @MainActor
    static func shared(in context: ModelContext) -> MyCloudProfile {
        let descriptor = FetchDescriptor<MyCloudProfile>()

        do {
            let existing = try context.fetch(descriptor)
            if let first = existing.first {
                // Clean up duplicates if any exist
                if existing.count > 1 {
                    for duplicate in existing.dropFirst() {
                        context.delete(duplicate)
                    }
                }
                return first
            }
        } catch {
            print("Error fetching MyCloudProfile: \(error)")
        }

        // No existing profile found, create default
        let profile = MyCloudProfile()
        context.insert(profile)
        return profile
    }
}

// MARK: - Avatar Emoji Options

extension MyCloudProfile {
    /// Available avatar emoji options for users to choose from
    static let avatarOptions: [String] = [
        // Faces
        "😊", "😎", "🤓", "😇", "🥳", "😄", "🤩", "😌",
        "🥰", "😍", "🤗", "🤔", "😏", "😴", "🥱", "😜",
        // People & Activities
        "🧑‍💻", "🧘", "🏃", "🚴", "🏋️", "🤸", "🧗", "🏄",
        "🎨", "🎵", "📚", "🎮", "🧑‍🍳", "🧑‍🎓", "🧑‍🚀", "🦸",
        // Animals
        "🦁", "🐯", "🐻", "🐼", "🦊", "🐰", "🐸", "🦋",
        "🐶", "🐱", "🐨", "🐵", "🦄", "🐢", "🦉", "🐙",
        // Nature & Objects
        "🌸", "🌺", "🌻", "🌈", "☀️", "🌙", "⭐️", "✨",
        "🔥", "💪", "🎯", "🏆", "💎", "🚀", "🎸", "🎭"
    ]
}
