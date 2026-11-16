//
//  MessageTemplate.swift
//  Stick
//
//  Predefined motivational messages for friends.
//

import Foundation

/// Predefined motivational message templates that friends can send to each other.
/// Messages are simple and encouraging without being intrusive.
enum MessageTemplate: String, CaseIterable, Identifiable, Codable {
    case keepGoing = "keep_going"
    case youGotThis = "you_got_this"
    case amazingProgress = "amazing_progress"
    case proudOfYou = "proud_of_you"
    case dontGiveUp = "dont_give_up"
    case crushing = "crushing"
    case inspiringMe = "inspiring_me"
    case letsMeetGoal = "lets_meet_goal"

    var id: String { rawValue }

    /// The emoji associated with this message template
    var emoji: String {
        switch self {
        case .keepGoing: return "💪"
        case .youGotThis: return "🙌"
        case .amazingProgress: return "🚀"
        case .proudOfYou: return "🌟"
        case .dontGiveUp: return "🔥"
        case .crushing: return "⚡️"
        case .inspiringMe: return "✨"
        case .letsMeetGoal: return "🎯"
        }
    }

    /// Short label for compact template grid display
    var shortLabel: String {
        switch self {
        case .keepGoing:
            return String(localized: "message_short_keep_going")
        case .youGotThis:
            return String(localized: "message_short_you_got_this")
        case .amazingProgress:
            return String(localized: "message_short_amazing")
        case .proudOfYou:
            return String(localized: "message_short_proud")
        case .dontGiveUp:
            return String(localized: "message_short_dont_give_up")
        case .crushing:
            return String(localized: "message_short_crushing")
        case .inspiringMe:
            return String(localized: "message_short_inspiring")
        case .letsMeetGoal:
            return String(localized: "message_short_goals")
        }
    }

    /// The localized message text
    var localizedMessage: String {
        switch self {
        case .keepGoing:
            return String(localized: "message_keep_going")
        case .youGotThis:
            return String(localized: "message_you_got_this")
        case .amazingProgress:
            return String(localized: "message_amazing_progress")
        case .proudOfYou:
            return String(localized: "message_proud_of_you")
        case .dontGiveUp:
            return String(localized: "message_dont_give_up")
        case .crushing:
            return String(localized: "message_crushing")
        case .inspiringMe:
            return String(localized: "message_inspiring_me")
        case .letsMeetGoal:
            return String(localized: "message_lets_meet_goal")
        }
    }

    /// Full display string with emoji
    var displayText: String {
        "\(emoji) \(localizedMessage)"
    }

    /// Short preview for notifications
    var shortPreview: String {
        "\(emoji) \(localizedMessage)"
    }
}
