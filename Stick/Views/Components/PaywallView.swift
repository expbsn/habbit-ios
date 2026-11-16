//
//  PaywallView.swift
//  Stick
//
//  Reusable paywall component for premium gating
//

import SwiftUI
import RevenueCat

struct PaywallView: View {
    let source: String
    var onSubscribed: (() -> Void)?

    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    @ObservedObject private var subscriptionService = SubscriptionService.shared
    @State private var selectedPlan: PaywallPlan = .yearly
    @State private var showErrorAlert = false

    /// Localized billed price for the currently selected plan (falls back to a static price).
    private var selectedPriceString: String {
        if let package = (selectedPlan == .yearly ? subscriptionService.annualPackage : subscriptionService.monthlyPackage) {
            return package.localizedPriceString
        }
        return selectedPlan == .yearly ? "$24.99" : "$4.99"
    }

    /// Prominent billed-amount summary: the total the user will be charged is the
    /// most conspicuous pricing element (App Store Review 3.1.2).
    private var billedAmountSummary: some View {
        VStack(spacing: 2) {
            Text("\(selectedPriceString) \(selectedPlan.renewalPeriodKey)")
                .font(.title2.bold())
                .foregroundStyle(.primary)
            Text(String(localized: "paywall_trial_note"))
                .font(.caption2)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(.horizontal, 24)
        .padding(.top, 16)
    }

    private var autoRenewalDisclosure: some View {
        let price: String
        if let package = (selectedPlan == .yearly ? subscriptionService.annualPackage : subscriptionService.monthlyPackage) {
            price = package.localizedPriceString
        } else {
            price = selectedPlan == .yearly ? "$24.99" : "$4.99"
        }
        let period = selectedPlan.renewalPeriodKey
        return Text(String(format: String(localized: "paywall_auto_renew_disclosure"), price, period))
            .font(.caption2)
            .foregroundStyle(.secondary)
            .multilineTextAlignment(.center)
            .padding(.horizontal, 32)
            .padding(.top, 12)
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Header
                VStack(spacing: 8) {
                    Image(systemName: "crown.fill")
                        .font(.system(size: 48))
                        .foregroundStyle(.yellow)
                        .padding(.bottom, 8)

                    Text(String(localized: "paywall_habit_limit_title"))
                        .font(.title2.bold())
                        .foregroundStyle(.primary)
                        .multilineTextAlignment(.center)

                    Text(String(localized: "paywall_subtitle"))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .padding(.top, 24)

                // Timeline
                VStack(alignment: .leading, spacing: 0) {
                    PaywallTimelineRow(
                        step: "1",
                        title: String(localized: "paywall_timeline1_title"),
                        subtitle: String(localized: "paywall_timeline1_subtitle"),
                        isLast: false,
                        colorScheme: colorScheme
                    )
                    PaywallTimelineRow(
                        step: "2",
                        title: String(localized: "paywall_timeline2_title"),
                        subtitle: String(localized: "paywall_timeline2_subtitle"),
                        isLast: false,
                        colorScheme: colorScheme
                    )
                    PaywallTimelineRow(
                        step: "3",
                        title: String(localized: "paywall_timeline3_title"),
                        subtitle: String(localized: "paywall_timeline3_subtitle"),
                        isLast: true,
                        colorScheme: colorScheme
                    )
                }
                .padding(.horizontal, 32)
                .padding(.top, 32)
                .padding(.bottom, 24)

                Spacer()

                // Plan selection cards
                HStack(spacing: 12) {
                    PaywallPlanCard(
                        plan: .yearly,
                        isSelected: selectedPlan == .yearly,
                        badge: String(localized: "paywall_badge_save"),
                        colorScheme: colorScheme,
                        package: subscriptionService.annualPackage
                    ) {
                        selectedPlan = .yearly
                    }

                    PaywallPlanCard(
                        plan: .monthly,
                        isSelected: selectedPlan == .monthly,
                        badge: nil,
                        colorScheme: colorScheme,
                        package: subscriptionService.monthlyPackage
                    ) {
                        selectedPlan = .monthly
                    }
                }
                .padding(.horizontal, 24)
                .padding(.top, 16)

                // Prominent billed-amount summary (billed amount is the most conspicuous element)
                billedAmountSummary

                // Subscribe button
                Button {
                    Task { await startPurchase() }
                } label: {
                    HStack {
                        if subscriptionService.isLoading || subscriptionService.isFetchingOfferings {
                            ProgressView()
                                .tint(Color(.systemBackground))
                        } else {
                            Text(String(localized: "paywall_start_trial"))
                                .font(.headline)
                            Spacer()
                            Image(systemName: "arrow.right")
                                .font(.headline)
                        }
                    }
                    .foregroundStyle(Color(.systemBackground))
                    .padding()
                    .frame(maxWidth: .infinity)
                    .background(Color.primary)
                    .clipShape(RoundedRectangle(cornerRadius: 14))
                }
                .disabled(subscriptionService.isLoading || subscriptionService.isFetchingOfferings)
                .padding(.horizontal, 24)
                .padding(.top, 20)

                // Auto-renewal disclosure (required by App Store Review 3.1.2c)
                autoRenewalDisclosure

                // Footer links
                HStack(spacing: 20) {
                    Link(String(localized: "paywall_terms"), destination: URL(string: "https://get-habbit.com/terms")!)
                    Link(String(localized: "paywall_privacy"), destination: URL(string: "https://get-habbit.com/privacy")!)
                    Button(String(localized: "paywall_restore")) {
                        Task {
                            let success = await subscriptionService.restorePurchases()
                            if success {
                                AnalyticsService.shared.trackSubscriptionRestored()
                                onSubscribed?()
                                dismiss()
                            }
                        }
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.top, 8)
                .padding(.bottom, 24)
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button {
                        AnalyticsService.shared.trackPaywallDismissed(source: source)
                        dismiss()
                    } label: {
                        Image(systemName: "xmark")
                            .font(.body.weight(.medium))
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .onAppear {
            AnalyticsService.shared.trackPaywallViewed(source: source)
        }
        .task {
            if subscriptionService.currentOffering == nil {
                await subscriptionService.fetchOfferings()
            }
        }
        .alert(String(localized: "paywall_error_title"), isPresented: $showErrorAlert) {
            Button(String(localized: "paywall_ok"), role: .cancel) {}
        } message: {
            Text(String(localized: "paywall_offerings_error"))
        }
    }

    /// Runs the purchase flow and always gives the user feedback: if the
    /// offerings/package can't be loaded, it shows an error instead of silently
    /// doing nothing.
    @MainActor
    private func startPurchase() async {
        let planName = selectedPlan == .yearly ? "yearly" : "monthly"
        AnalyticsService.shared.trackPlanSelected(plan: planName)

        // Make sure offerings are loaded (retry once if needed).
        if subscriptionService.currentOffering == nil {
            await subscriptionService.fetchOfferings()
        }

        let package = selectedPlan == .yearly
            ? subscriptionService.annualPackage
            : subscriptionService.monthlyPackage

        guard let package else {
            AnalyticsService.shared.trackPurchaseFailed(reason: "offerings_unavailable")
            showErrorAlert = true
            return
        }

        let success = await subscriptionService.purchase(package)
        if success {
            AnalyticsService.shared.trackTrialStarted(plan: planName)
            onSubscribed?()
            dismiss()
        } else {
            AnalyticsService.shared.trackPurchaseFailed(reason: "purchase_cancelled_or_failed")
        }
    }
}

// MARK: - Paywall Timeline Row

private struct PaywallTimelineRow: View {
    let step: String
    let title: String
    let subtitle: String
    let isLast: Bool
    let colorScheme: ColorScheme

    var body: some View {
        HStack(alignment: .top, spacing: 16) {
            // Timeline indicator
            VStack(spacing: 0) {
                ZStack {
                    Circle()
                        .stroke(Color.primary.opacity(0.3), lineWidth: 2)
                        .frame(width: 28, height: 28)

                    Text(step)
                        .font(.caption.bold())
                        .foregroundStyle(.primary)
                }

                if !isLast {
                    Rectangle()
                        .fill(Color.primary.opacity(0.2))
                        .frame(width: 2, height: 40)
                }
            }

            // Content
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.headline)
                    .foregroundStyle(.primary)

                Text(subtitle)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.bottom, isLast ? 0 : 16)

            Spacer()
        }
    }
}

// MARK: - Paywall Plan Card

private struct PaywallPlanCard: View {
    let plan: PaywallPlan
    let isSelected: Bool
    let badge: String?
    let colorScheme: ColorScheme
    var package: Package?
    let action: () -> Void

    private var displayPrice: String {
        if let package = package {
            return package.localizedPriceString + (plan == .yearly ? "/yr" : "/mo")
        }
        return plan.price
    }

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 8) {
                Image(systemName: plan.icon)
                    .font(.title2)
                    .foregroundStyle(plan == .yearly ? .yellow : .primary)

                Text(plan.title)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                // Billed amount — the most conspicuous pricing element in the card
                Text(displayPrice)
                    .font(.title3.bold())
                    .foregroundStyle(.primary)

                Text(plan.renewalLabel)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(16)
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(Color.primary.opacity(0.05))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 16)
                    .stroke(isSelected ? Color.primary : Color.primary.opacity(0.2), lineWidth: isSelected ? 2 : 1)
            )
            .overlay(alignment: .topTrailing) {
                if let badge = badge {
                    Text(badge)
                        .font(.caption2.bold())
                        .foregroundStyle(Color(.systemBackground))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color.primary)
                        .clipShape(Capsule())
                        .offset(x: -8, y: -10)
                }
            }
        }
        .buttonStyle(.plain)
    }
}

#Preview {
    PaywallView(source: "preview")
}
