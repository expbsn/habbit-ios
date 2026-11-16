//
//  ChallengeStatus.swift
//  Stick
//
//  Status states for shared challenges.
//

import Foundation

/// Status of a shared challenge between friends
enum ChallengeStatus: String, Codable, CaseIterable {
    /// Challenge has been created but not yet accepted by participant
    case pending = "pending"

    /// Challenge has been accepted and is actively being tracked
    case active = "active"

    /// Challenge duration has ended (reached target days)
    case completed = "completed"

    /// Challenge was cancelled by creator or declined by participant
    case cancelled = "cancelled"

    /// Localized display name for the status
    var displayName: String {
        switch self {
        case .pending:
            return String(localized: "challenges_status_pending")
        case .active:
            return String(localized: "challenges_status_active")
        case .completed:
            return String(localized: "challenges_status_completed")
        case .cancelled:
            return String(localized: "challenges_status_cancelled")
        }
    }

    /// Whether the challenge is currently trackable
    var isTrackable: Bool {
        self == .active
    }

    /// Whether the challenge has ended (completed or cancelled)
    var hasEnded: Bool {
        self == .completed || self == .cancelled
    }
}
