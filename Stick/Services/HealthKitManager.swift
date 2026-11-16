//
//  HealthKitManager.swift
//  Stick
//
//  Created by Kian Jain on 05.02.26.
//

import Foundation
import HealthKit
import SwiftData
import Combine

/// Manages HealthKit integration for automatic habit tracking
@MainActor
final class HealthKitManager: ObservableObject {
    static let shared = HealthKitManager()

    @Published var isAuthorized = false
    @Published var todaySteps: Int = 0
    @Published var todayCalories: Double = 0
    @Published var todayDistance: Double = 0
    @Published var isHealthKitAvailable: Bool = false

    private let healthStore: HKHealthStore?
    private var syncTimer: Timer?
    private var observerQueries: [HKObserverQuery] = []
    private let authorizationRequestedKey = "healthKitAuthorizationRequested"

    /// Callback for background sync - set by StickApp to sync habits
    var onBackgroundUpdate: (() async -> Void)?

    private init() {
        if HKHealthStore.isHealthDataAvailable() {
            healthStore = HKHealthStore()
            isHealthKitAvailable = true
            // If we've previously requested authorization, assume it's available
            // (HealthKit doesn't tell us about read-only permission status for privacy)
            isAuthorized = UserDefaults.standard.bool(forKey: authorizationRequestedKey)
        } else {
            healthStore = nil
            isHealthKitAvailable = false
        }
    }

    // MARK: - Authorization

    /// Request HealthKit permissions
    /// Note: For read-only access, Apple doesn't reveal if permission was granted.
    /// We just request and then try to read data - it will return 0 if denied.
    func requestAuthorization() async -> Bool {
        guard let healthStore = healthStore else {
            return false
        }

        let typesToRead: Set<HKSampleType> = [
            HKQuantityType.quantityType(forIdentifier: .stepCount)!,
            HKQuantityType.quantityType(forIdentifier: .activeEnergyBurned)!,
            HKQuantityType.quantityType(forIdentifier: .distanceWalkingRunning)!,
            HKWorkoutType.workoutType()
        ]

        do {
            try await healthStore.requestAuthorization(toShare: [], read: typesToRead)

            // Mark that we've requested authorization
            // For read-only access, we assume success after the prompt is shown
            UserDefaults.standard.set(true, forKey: authorizationRequestedKey)
            isAuthorized = true

            // Fetch initial data
            await refreshTodayData()

            return true
        } catch {
            print("HealthKit authorization error: \(error)")
            return false
        }
    }

    // MARK: - Data Fetching

    /// Fetch step count for a specific date
    func fetchSteps(for date: Date) async -> Int {
        guard let healthStore = healthStore else { return 0 }

        let stepType = HKQuantityType.quantityType(forIdentifier: .stepCount)!
        let calendar = Calendar.current
        let startOfDay = calendar.startOfDay(for: date)
        let endOfDay = calendar.date(byAdding: .day, value: 1, to: startOfDay)!

        let predicate = HKQuery.predicateForSamples(withStart: startOfDay, end: endOfDay, options: .strictStartDate)

        return await withCheckedContinuation { continuation in
            let query = HKStatisticsQuery(quantityType: stepType, quantitySamplePredicate: predicate, options: .cumulativeSum) { _, result, error in
                if let error = error {
                    print("Failed to fetch steps: \(error)")
                    continuation.resume(returning: 0)
                    return
                }

                let steps = result?.sumQuantity()?.doubleValue(for: .count()) ?? 0
                continuation.resume(returning: Int(steps))
            }

            healthStore.execute(query)
        }
    }

    /// Fetch active calories burned for a specific date
    func fetchCalories(for date: Date) async -> Double {
        guard let healthStore = healthStore else { return 0 }

        let calorieType = HKQuantityType.quantityType(forIdentifier: .activeEnergyBurned)!
        let calendar = Calendar.current
        let startOfDay = calendar.startOfDay(for: date)
        let endOfDay = calendar.date(byAdding: .day, value: 1, to: startOfDay)!

        let predicate = HKQuery.predicateForSamples(withStart: startOfDay, end: endOfDay, options: .strictStartDate)

        return await withCheckedContinuation { continuation in
            let query = HKStatisticsQuery(quantityType: calorieType, quantitySamplePredicate: predicate, options: .cumulativeSum) { _, result, error in
                if let error = error {
                    print("Failed to fetch calories: \(error)")
                    continuation.resume(returning: 0)
                    return
                }

                let calories = result?.sumQuantity()?.doubleValue(for: .kilocalorie()) ?? 0
                continuation.resume(returning: calories)
            }

            healthStore.execute(query)
        }
    }

    /// Fetch walking/running distance for a specific date (in kilometers)
    func fetchDistance(for date: Date) async -> Double {
        guard let healthStore = healthStore else { return 0 }

        let distanceType = HKQuantityType.quantityType(forIdentifier: .distanceWalkingRunning)!
        let calendar = Calendar.current
        let startOfDay = calendar.startOfDay(for: date)
        let endOfDay = calendar.date(byAdding: .day, value: 1, to: startOfDay)!

        let predicate = HKQuery.predicateForSamples(withStart: startOfDay, end: endOfDay, options: .strictStartDate)

        return await withCheckedContinuation { continuation in
            let query = HKStatisticsQuery(quantityType: distanceType, quantitySamplePredicate: predicate, options: .cumulativeSum) { _, result, error in
                if let error = error {
                    print("Failed to fetch distance: \(error)")
                    continuation.resume(returning: 0)
                    return
                }

                let distance = result?.sumQuantity()?.doubleValue(for: .meterUnit(with: .kilo)) ?? 0
                continuation.resume(returning: distance)
            }

            healthStore.execute(query)
        }
    }

    /// Fetch workout count for a specific date
    func fetchWorkoutCount(for date: Date) async -> Int {
        guard let healthStore = healthStore else { return 0 }

        let calendar = Calendar.current
        let startOfDay = calendar.startOfDay(for: date)
        let endOfDay = calendar.date(byAdding: .day, value: 1, to: startOfDay)!

        let predicate = HKQuery.predicateForSamples(withStart: startOfDay, end: endOfDay, options: .strictStartDate)

        return await withCheckedContinuation { continuation in
            let query = HKSampleQuery(sampleType: HKWorkoutType.workoutType(), predicate: predicate, limit: HKObjectQueryNoLimit, sortDescriptors: nil) { _, samples, error in
                if let error = error {
                    print("Failed to fetch workouts: \(error)")
                    continuation.resume(returning: 0)
                    return
                }

                continuation.resume(returning: samples?.count ?? 0)
            }

            healthStore.execute(query)
        }
    }

    /// Fetch value for a specific HealthKit data type
    func fetchValue(for dataType: HealthKitDataType, date: Date) async -> Double {
        switch dataType {
        case .steps:
            return Double(await fetchSteps(for: date))
        case .calories:
            return await fetchCalories(for: date)
        case .distance:
            return await fetchDistance(for: date)
        case .workouts:
            return Double(await fetchWorkoutCount(for: date))
        }
    }

    /// Refresh today's data for display
    func refreshTodayData() async {
        todaySteps = await fetchSteps(for: Date())
        todayCalories = await fetchCalories(for: Date())
        todayDistance = await fetchDistance(for: Date())
        // Keep widget step count in sync
        WidgetDataService.shared.syncSteps(count: todaySteps)
    }

    // MARK: - Habit Syncing

    /// Sync HealthKit data to a specific habit's completion
    func syncHabit(_ habit: Habit, for date: Date, context: ModelContext) async {
        guard habit.isHealthKitLinked,
              let dataType = habit.healthKitDataType else { return }

        let value = await fetchValue(for: dataType, date: date)
        let calendar = Calendar.current

        // Get or create today's completion
        let existingCompletion = habit.safeCompletions.first { completion in
            calendar.isDate(completion.completionDate, inSameDayAs: date) &&
            completion.source == "healthkit"
        }

        // Only update if habit has a target count
        guard let targetCount = habit.targetCount else {
            // For binary habits, mark complete if value > 0 and auto-complete is enabled
            if habit.healthKitAutoComplete && value > 0 {
                if existingCompletion == nil && !habit.isCompleted(for: date) {
                    let completion = HabitCompletion(habit: habit, completionDate: date, source: "healthkit")
                    context.insert(completion)
                    habit.safeCompletions.append(completion)
                }
            }
            return
        }

        let intValue = Int(value)

        if let existing = existingCompletion {
            // Update existing HealthKit completion
            existing.count = intValue
        } else if intValue > 0 {
            // Create new HealthKit completion
            let completion = HabitCompletion(habit: habit, completionDate: date, count: intValue, source: "healthkit")
            context.insert(completion)
            habit.safeCompletions.append(completion)
        }

        do {
            try context.save()
        } catch {
            print("Failed to save HealthKit sync: \(error)")
        }
    }

    /// Sync all HealthKit-linked habits.
    /// Syncs today and the previous 2 days so that data written after midnight
    /// (or late corrections) don't leave past days permanently under-counted.
    func syncAllHealthKitHabits(habits: [Habit], context: ModelContext) async {
        let healthKitHabits = habits.filter { $0.isHealthKitLinked && $0.isActive }
        let calendar = Calendar.current
        let today = Date()
        let dates: [Date] = [
            today,
            calendar.date(byAdding: .day, value: -1, to: today) ?? today,
            calendar.date(byAdding: .day, value: -2, to: today) ?? today
        ]

        for habit in healthKitHabits {
            for date in dates {
                await syncHabit(habit, for: date, context: context)
            }
        }
    }

    // MARK: - Background Delivery

    /// Set up background delivery for HealthKit data
    /// This allows the app to be woken up when new health data is available
    func setupBackgroundDelivery() {
        guard let healthStore = healthStore else { return }

        let dataTypes: [HKQuantityType] = [
            HKQuantityType.quantityType(forIdentifier: .stepCount)!,
            HKQuantityType.quantityType(forIdentifier: .activeEnergyBurned)!,
            HKQuantityType.quantityType(forIdentifier: .distanceWalkingRunning)!
        ]

        for dataType in dataTypes {
            // Enable background delivery - iOS will wake the app when new data is available
            healthStore.enableBackgroundDelivery(for: dataType, frequency: .hourly) { success, error in
                if let error = error {
                    print("Failed to enable background delivery for \(dataType): \(error)")
                } else if success {
                    print("Background delivery enabled for \(dataType)")
                }
            }

            // Set up observer query to be notified of changes
            let query = HKObserverQuery(sampleType: dataType, predicate: nil) { [weak self] _, completionHandler, error in
                if let error = error {
                    print("Observer query error for \(dataType): \(error)")
                    completionHandler()
                    return
                }

                // New data available - trigger sync
                Task { @MainActor [weak self] in
                    await self?.refreshTodayData()
                    await self?.onBackgroundUpdate?()
                }

                // Must call completion handler to let HealthKit know we're done
                completionHandler()
            }

            healthStore.execute(query)
            observerQueries.append(query)
        }
    }

    /// Stop all observer queries
    func stopBackgroundDelivery() {
        guard let healthStore = healthStore else { return }

        for query in observerQueries {
            healthStore.stop(query)
        }
        observerQueries.removeAll()
    }

    // MARK: - Periodic Sync

    /// Start periodic sync (every 5 minutes when app is active)
    func startPeriodicSync() {
        stopPeriodicSync()

        syncTimer = Timer.scheduledTimer(withTimeInterval: 300, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                await self?.refreshTodayData()
            }
        }
    }

    /// Stop periodic sync
    func stopPeriodicSync() {
        syncTimer?.invalidate()
        syncTimer = nil
    }

    // MARK: - Helpers

    /// Format a HealthKit value for display
    func formatValue(_ value: Double, for dataType: HealthKitDataType) -> String {
        switch dataType {
        case .steps:
            return "\(Int(value))"
        case .calories:
            return String(format: "%.0f", value)
        case .distance:
            return String(format: "%.1f", value)
        case .workouts:
            return "\(Int(value))"
        }
    }
}
