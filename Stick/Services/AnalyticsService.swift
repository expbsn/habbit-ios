//
//  AnalyticsService.swift
//  Stick
//
//  Centralized analytics tracking via PostHog
//

import Foundation
import PostHog

final class AnalyticsService {
    static let shared = AnalyticsService()

    private init() {}

    // MARK: - Onboarding Events

    func trackOnboardingStarted() {
        PostHogSDK.shared.capture("onboarding_started")
        PostHogSDK.shared.flush()
    }

    func trackOnboardingStepCompleted(step: Int, stepName: String) {
        PostHogSDK.shared.capture("onboarding_step_completed", properties: [
            "step_number": step,
            "step_name": stepName
        ])
        PostHogSDK.shared.flush()
    }

    func trackOnboardingCompleted() {
        PostHogSDK.shared.capture("onboarding_completed")
        PostHogSDK.shared.flush()
    }

    func trackOnboardingAbandoned(atStep: Int) {
        PostHogSDK.shared.capture("onboarding_abandoned", properties: [
            "abandoned_at_step": atStep
        ])
    }

    // MARK: - Paywall Events

    func trackPaywallViewed(source: String = "onboarding") {
        PostHogSDK.shared.capture("paywall_viewed", properties: [
            "source": source
        ])
        PostHogSDK.shared.flush()
    }

    func trackPaywallDismissed(source: String = "onboarding") {
        PostHogSDK.shared.capture("paywall_dismissed", properties: [
            "source": source
        ])
        PostHogSDK.shared.flush()
    }

    func trackPlanSelected(plan: String) {
        PostHogSDK.shared.capture("plan_selected", properties: [
            "plan": plan
        ])
        PostHogSDK.shared.flush()
    }

    // MARK: - Subscription Events

    func trackTrialStarted(plan: String) {
        PostHogSDK.shared.capture("trial_started", properties: [
            "plan": plan
        ])
        PostHogSDK.shared.flush()
    }

    func trackSubscriptionPurchased(plan: String, price: String) {
        PostHogSDK.shared.capture("subscription_purchased", properties: [
            "plan": plan,
            "price": price
        ])
        PostHogSDK.shared.flush()
    }

    func trackSubscriptionRestored() {
        PostHogSDK.shared.capture("subscription_restored")
        PostHogSDK.shared.flush()
    }

    func trackPurchaseFailed(reason: String) {
        PostHogSDK.shared.capture("purchase_failed", properties: [
            "reason": reason
        ])
        PostHogSDK.shared.flush()
    }

    // MARK: - Notification Events

    func trackNotificationPermissionRequested() {
        PostHogSDK.shared.capture("notification_permission_requested")
        PostHogSDK.shared.flush()
    }

    func trackNotificationPermissionGranted() {
        PostHogSDK.shared.capture("notification_permission_granted")
        PostHogSDK.shared.flush()
    }

    func trackNotificationPermissionDenied() {
        PostHogSDK.shared.capture("notification_permission_denied")
        PostHogSDK.shared.flush()
    }

    func trackNotificationSkipped() {
        PostHogSDK.shared.capture("notification_skipped")
        PostHogSDK.shared.flush()
    }

    // MARK: - Habit Events

    func trackHabitCreated(habitType: String, frequency: String, isTimerBased: Bool) {
        PostHogSDK.shared.capture("habit_created", properties: [
            "habit_type": habitType,
            "frequency": frequency,
            "is_timer_based": isTimerBased
        ])
    }

    func trackHabitCompleted(habitId: String, habitName: String) {
        PostHogSDK.shared.capture("habit_completed", properties: [
            "habit_id": habitId,
            "habit_name": habitName
        ])
    }

    func trackHabitDeleted(habitId: String) {
        PostHogSDK.shared.capture("habit_deleted", properties: [
            "habit_id": habitId
        ])
    }

    // MARK: - App Usage Events

    func trackAppOpened() {
        PostHogSDK.shared.capture("app_opened")
        PostHogSDK.shared.flush()
    }

    func trackDailyActiveUser() {
        let today = ISO8601DateFormatter().string(from: Date()).prefix(10) // "2026-02-12"
        PostHogSDK.shared.capture("daily_active", properties: [
            "date": String(today)
        ])
        PostHogSDK.shared.flush()
    }

    func trackSessionStarted() {
        PostHogSDK.shared.capture("session_started", properties: [
            "timestamp": ISO8601DateFormatter().string(from: Date())
        ])
        PostHogSDK.shared.flush()
    }

    func trackSessionEnded(durationSeconds: Int) {
        PostHogSDK.shared.capture("session_ended", properties: [
            "duration_seconds": durationSeconds,
            "duration_minutes": durationSeconds / 60
        ])
        PostHogSDK.shared.flush()
    }

    func trackFeatureUsed(feature: String) {
        PostHogSDK.shared.capture("feature_used", properties: [
            "feature": feature
        ])
        PostHogSDK.shared.flush()
    }

    func trackDaysSinceInstall() {
        let installDateKey = "app_install_date"
        let defaults = UserDefaults.standard

        if defaults.object(forKey: installDateKey) == nil {
            defaults.set(Date(), forKey: installDateKey)
        }

        if let installDate = defaults.object(forKey: installDateKey) as? Date {
            let daysSinceInstall = Calendar.current.dateComponents([.day], from: installDate, to: Date()).day ?? 0
            PostHogSDK.shared.capture("app_usage", properties: [
                "days_since_install": daysSinceInstall
            ])
            PostHogSDK.shared.flush()
        }
    }

    // MARK: - User Properties

    func setUserProperty(key: String, value: Any) {
        PostHogSDK.shared.capture("$set", properties: [
            "$set": [key: value]
        ])
    }

    func identifyUser(userId: String, properties: [String: Any]? = nil) {
        if let properties = properties {
            PostHogSDK.shared.identify(userId, userProperties: properties)
        } else {
            PostHogSDK.shared.identify(userId)
        }
    }
}
