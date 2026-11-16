//
//  SubscriptionService.swift
//  Stick
//
//  Service to manage subscriptions via RevenueCat
//

import Foundation
import Combine
import RevenueCat

@MainActor
final class SubscriptionService: ObservableObject {
    static let shared = SubscriptionService()

    /// Maximum number of active habits for free users
    static let freeHabitLimit = 6

    /// The entitlement identifier from RevenueCat dashboard
    private let entitlementID = "Habbit Pro"

    /// The offering identifier from RevenueCat dashboard
    private let offeringID = "appstore"

    @Published private(set) var isSubscribed: Bool = false
    @Published private(set) var currentOffering: Offering?
    @Published private(set) var isLoading: Bool = false
    @Published private(set) var isFetchingOfferings: Bool = false

    private init() {
        Task {
            await checkSubscriptionStatus()
            await fetchOfferings()
        }
    }

    /// Check if user has an active subscription
    func checkSubscriptionStatus() async {
        do {
            let customerInfo = try await Purchases.shared.customerInfo()
            isSubscribed = customerInfo.entitlements[entitlementID]?.isActive == true
        } catch {
            print("Failed to fetch customer info: \(error)")
            isSubscribed = false
        }
    }

    /// Fetch available offerings.
    ///
    /// Retries a few times because on a fresh install / cold StoreKit cache the
    /// first `offerings()` call can return before products have propagated,
    /// yielding an empty offering. We only keep an offering that actually
    /// contains purchasable packages.
    func fetchOfferings(retries: Int = 3) async {
        guard !isFetchingOfferings else { return }
        isFetchingOfferings = true
        defer { isFetchingOfferings = false }

        for attempt in 0...max(0, retries) {
            do {
                let offerings = try await Purchases.shared.offerings()
                // Prefer the configured offering, then the current one, then any offering.
                let resolved = offerings[offeringID]
                    ?? offerings.current
                    ?? offerings.all.values.first

                if let resolved, !resolved.availablePackages.isEmpty {
                    currentOffering = resolved
                    return
                }
                print("Offerings loaded but no purchasable packages yet (attempt \(attempt + 1)).")
            } catch {
                print("Failed to fetch offerings (attempt \(attempt + 1)): \(error)")
            }

            // Back off briefly before retrying (skip the wait after the last try).
            if attempt < retries {
                try? await Task.sleep(nanoseconds: 1_200_000_000)
            }
        }
    }

    /// Purchase a package
    func purchase(_ package: Package) async -> Bool {
        isLoading = true
        defer { isLoading = false }

        do {
            let result = try await Purchases.shared.purchase(package: package)
            isSubscribed = result.customerInfo.entitlements[entitlementID]?.isActive == true
            return isSubscribed
        } catch {
            if let purchaseError = error as? RevenueCat.ErrorCode {
                if purchaseError == .purchaseCancelledError {
                    print("Purchase cancelled by user")
                } else {
                    print("Purchase error: \(purchaseError)")
                }
            } else {
                print("Purchase failed: \(error)")
            }
            return false
        }
    }

    /// Restore purchases
    func restorePurchases() async -> Bool {
        isLoading = true
        defer { isLoading = false }

        do {
            let customerInfo = try await Purchases.shared.restorePurchases()
            isSubscribed = customerInfo.entitlements[entitlementID]?.isActive == true
            return isSubscribed
        } catch {
            print("Restore failed: \(error)")
            return false
        }
    }

    /// Get monthly package from current offering
    var monthlyPackage: Package? {
        currentOffering?.monthly
    }

    /// Get annual package from current offering
    var annualPackage: Package? {
        currentOffering?.annual
    }

    /// Check if user can add another habit based on subscription status
    /// - Parameter currentActiveCount: Number of currently active habits
    /// - Returns: True if user can add more habits
    func canAddHabit(currentActiveCount: Int) -> Bool {
        if isSubscribed { return true }
        return currentActiveCount < Self.freeHabitLimit
    }
}
