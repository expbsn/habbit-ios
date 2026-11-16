//
//  ReceivedMessage.swift
//  Stick
//
//  Messages received from friends, stored locally.
//

import Foundation
import SwiftData

/// A motivational message received from a friend.
/// Stored locally and synced from CloudKit.
@Model
final class ReceivedMessage {
    /// CloudKit record ID for this message
    var cloudRecordID: String?

    /// CloudKit user ID of the sender
    var senderUserID: String = ""

    /// Sender's display name (cached for display)
    var senderDisplayName: String = ""

    /// Sender's avatar emoji (cached for display)
    var senderAvatarEmoji: String = "😊"

    /// The message template ID (MessageTemplate raw value, or "custom" for custom messages)
    var templateID: String = ""

    /// Custom message text (only set when templateID is "custom")
    var customMessageText: String?

    /// Date the message was sent
    var sentDate: Date = Date()

    /// Whether this message has been read
    var isRead: Bool = false

    /// Date the message was received locally
    var receivedDate: Date = Date()

    init(
        cloudRecordID: String? = nil,
        senderUserID: String,
        senderDisplayName: String,
        senderAvatarEmoji: String = "😊",
        templateID: String,
        customMessageText: String? = nil,
        sentDate: Date = Date()
    ) {
        self.cloudRecordID = cloudRecordID
        self.senderUserID = senderUserID
        self.senderDisplayName = senderDisplayName
        self.senderAvatarEmoji = senderAvatarEmoji
        self.templateID = templateID
        self.customMessageText = customMessageText
        self.sentDate = sentDate
        self.isRead = false
        self.receivedDate = Date()
    }

    /// Whether this is a custom message (not a template)
    var isCustomMessage: Bool {
        templateID == "custom"
    }

    /// The message template enum value
    var template: MessageTemplate? {
        MessageTemplate(rawValue: templateID)
    }

    /// Full display text (no emoji prefix)
    var displayText: String {
        if isCustomMessage, let text = customMessageText {
            return text
        }
        return template?.localizedMessage ?? templateID
    }

    /// Short preview for list display
    var previewText: String {
        if isCustomMessage, let text = customMessageText {
            return "\(senderDisplayName): \(text)"
        }
        return "\(senderDisplayName): \(template?.shortPreview ?? templateID)"
    }

    /// Formatted relative time (e.g., "2h ago")
    var relativeTime: String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: sentDate, relativeTo: Date())
    }

    /// Mark this message as read
    func markAsRead() {
        isRead = true
    }
}

// MARK: - Fetch Helpers

extension ReceivedMessage {
    /// Fetch all unread messages
    @MainActor
    static func unreadMessages(in context: ModelContext) -> [ReceivedMessage] {
        let descriptor = FetchDescriptor<ReceivedMessage>(
            predicate: #Predicate { !$0.isRead },
            sortBy: [SortDescriptor(\.sentDate, order: .reverse)]
        )

        do {
            return try context.fetch(descriptor)
        } catch {
            print("Error fetching unread messages: \(error)")
            return []
        }
    }

    /// Count of unread messages
    @MainActor
    static func unreadCount(in context: ModelContext) -> Int {
        unreadMessages(in: context).count
    }

    /// All messages sorted by date (most recent first)
    @MainActor
    static func allMessages(in context: ModelContext, limit: Int = 50) -> [ReceivedMessage] {
        var descriptor = FetchDescriptor<ReceivedMessage>(
            sortBy: [SortDescriptor(\.sentDate, order: .reverse)]
        )
        descriptor.fetchLimit = limit

        do {
            return try context.fetch(descriptor)
        } catch {
            print("Error fetching messages: \(error)")
            return []
        }
    }
}
