//
//  SentMessage.swift
//  Stick
//
//  Messages sent to friends, stored locally for chat display.
//

import Foundation
import SwiftData

/// A message sent to a friend.
/// Stored locally to show in chat conversations.
@Model
final class SentMessage {
    /// CloudKit user ID of the recipient
    var recipientUserID: String = ""

    /// The message template ID (MessageTemplate raw value, or "custom" for custom messages)
    var templateID: String = ""

    /// Custom message text (only set when templateID is "custom")
    var customMessageText: String?

    /// Date the message was sent
    var sentDate: Date = Date()

    init(
        recipientUserID: String,
        templateID: String,
        customMessageText: String? = nil,
        sentDate: Date = Date()
    ) {
        self.recipientUserID = recipientUserID
        self.templateID = templateID
        self.customMessageText = customMessageText
        self.sentDate = sentDate
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

    /// Formatted relative time (e.g., "2h ago")
    var relativeTime: String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: sentDate, relativeTo: Date())
    }
}
