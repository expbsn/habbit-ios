//
//  CreateChallengeSheet.swift
//  Stick
//
//  Sheet for creating a new shared challenge - follows HabitFormView UI/UX patterns.
//

import SwiftUI
import SwiftData
#if canImport(UIKit)
import UIKit
#endif

struct CreateChallengeSheet: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @Query(filter: #Predicate<FriendProfile> { $0.connectionStatus == "accepted" },
           sort: \FriendProfile.displayName) private var friends: [FriendProfile]
    @Query(sort: \Goal.createdDate, order: .forward) private var goals: [Goal]

    @StateObject private var challengeSyncService = ChallengeSyncService.shared

    // MARK: - Form State (same as HabitFormView)

    @State private var name: String = ""
    @State private var habitDescription: String = ""
    @State private var selectedColor: String = Color.habitColorHexes[0]
    @State private var selectedEmoji: String = "✨"
    @State private var useEmoji: Bool = true
    @State private var selectedSymbol: String = "star.fill"

    @State private var frequency: HabitFrequency = .daily
    @State private var selectedDays: Set<Int> = []
    @State private var useSpecificDays: Bool = true
    @State private var weeklyRepetitions: Int = 3
    @State private var monthlyRepetitions: Int = 10
    @State private var customInterval: Int = 2

    @State private var isTimerBased: Bool = false
    @State private var durationMinutes: Int = 30

    @State private var hasTargetCount: Bool = false
    @State private var targetCount: Int = 8

    @State private var selectedGoal: Goal?

    // MARK: - Challenge-specific State

    @State private var challengeDuration: Int = 30
    @State private var isCollaborative: Bool = false
    @State private var selectedFriend: FriendProfile?
    @State private var selectedHealthKitType: HealthKitDataType? = nil
    @State private var healthKitTarget: Double = 10000

    // MARK: - UI State

    @State private var isCreating = false
    @State private var showError = false
    @State private var errorMessage = ""

    private let durationOptions = [7, 14, 30, 60, 90]

    // MARK: - Validation

    private var isValid: Bool {
        !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        selectedFriend != nil
    }

    // MARK: - Body

    var body: some View {
        NavigationStack {
            Form {
                // Basic Info
                basicInfoSection

                // Appearance
                appearanceSection

                // Schedule (simplified for challenges - daily by default)
                scheduleSection

                // Completion type (count/timer)
                completionTypeSection

                // Challenge Settings (NEW - challenge-specific)
                challengeSettingsSection

                // Friend Selection (NEW - challenge-specific)
                friendSelectionSection
            }
            .dimThemeBackground()
            .navigationTitle(String(localized: "challenges_create"))
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .tint(Color(red: 0.4, green: 0.4, blue: 0.45))
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(String(localized: "settings_cancel")) {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        createChallenge()
                    } label: {
                        if isCreating {
                            ProgressView()
                        } else {
                            Text(String(localized: "challenges_start"))
                                .fontWeight(.semibold)
                        }
                    }
                    .disabled(!isValid || isCreating)
                }
            }
            .alert(String(localized: "cloudkit_error_server"), isPresented: $showError) {
                Button(String(localized: "settings_cancel"), role: .cancel) {}
            } message: {
                Text(errorMessage)
            }
            .scrollDismissesKeyboard(.immediately)
        }
    }

    // MARK: - Basic Info Section

    private var basicInfoSection: some View {
        Section {
            TextField(String(localized: "habit_form_habit_name"), text: $name)
                .submitLabel(.done)

            TextField(String(localized: "settings_description_optional"), text: $habitDescription, axis: .vertical)
                .lineLimit(2...4)
                .submitLabel(.done)
                .onSubmit {
                    #if canImport(UIKit)
                    UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
                    #endif
                }
        } header: {
            Text(String(localized: "habit_form_basic_info"))
        } footer: {
            if name.isEmpty {
                Text(String(localized: "habit_form_name_required"))
                    .foregroundStyle(.secondary)
            }
        }
    }

    // MARK: - Appearance Section

    private var appearanceSection: some View {
        Section(String(localized: "settings_appearance")) {
            // Color picker
            VStack(alignment: .leading, spacing: 12) {
                Text(String(localized: "habit_form_color"))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 5), spacing: 12) {
                    ForEach(Color.habitColorHexes, id: \.self) { hex in
                        Circle()
                            .fill(Color(hex: hex))
                            .frame(width: 40, height: 40)
                            .overlay {
                                if selectedColor == hex {
                                    Image(systemName: "checkmark")
                                        .font(.system(size: 16, weight: .bold))
                                        .foregroundStyle(.white)
                                }
                            }
                            .onTapGesture {
                                selectedColor = hex
                            }
                    }
                }
            }
            .padding(.vertical, 4)

            // Icon picker
            VStack(alignment: .leading, spacing: 12) {
                Text(String(localized: "habit_form_icon"))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                Picker(String(localized: "habit_form_icon"), selection: $useEmoji) {
                    Text(String(localized: "habit_form_emoji")).tag(true)
                    Text(String(localized: "habit_form_symbol")).tag(false)
                }
                .pickerStyle(.segmented)

                if useEmoji {
                    EmojiPickerGrid(selectedEmoji: $selectedEmoji, accentColor: selectedColor)
                } else {
                    SymbolPickerGrid(selectedSymbol: $selectedSymbol, accentColor: selectedColor)
                }
            }
            .padding(.vertical, 4)

            // Preview
            HStack {
                Text(String(localized: "habit_form_preview"))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                Spacer()

                HabitIconPreview(
                    icon: useEmoji ? selectedEmoji : selectedSymbol,
                    isEmoji: useEmoji,
                    color: selectedColor
                )
            }
        }
    }

    // MARK: - Schedule Section

    private var scheduleSection: some View {
        Section(String(localized: "habit_form_schedule")) {
            // Frequency picker
            Picker(String(localized: "habit_form_frequency"), selection: $frequency) {
                ForEach(HabitFrequency.allCases, id: \.self) { freq in
                    Text(freq.localizedName).tag(freq)
                }
            }

            // Weekly options
            if frequency == .weekly {
                Picker(String(localized: "habit_form_schedule_type"), selection: $useSpecificDays) {
                    Text(String(localized: "habit_form_specific_days")).tag(true)
                    Text(String(localized: "habit_form_flexible")).tag(false)
                }
                .pickerStyle(.segmented)

                if useSpecificDays {
                    VStack(alignment: .leading, spacing: 12) {
                        Text(String(localized: "habit_form_select_days"))
                            .font(.subheadline)
                            .foregroundStyle(.secondary)

                        HStack(spacing: 8) {
                            ForEach(Weekday.weekdaysFromMonday) { day in
                                WeekdayButton(
                                    day: day,
                                    isSelected: selectedDays.contains(day.rawValue),
                                    accentColor: selectedColor
                                ) {
                                    if selectedDays.contains(day.rawValue) {
                                        selectedDays.remove(day.rawValue)
                                    } else {
                                        selectedDays.insert(day.rawValue)
                                    }
                                }
                            }
                        }
                    }
                    .padding(.vertical, 4)
                } else {
                    Stepper(String(format: String(localized: "habit_form_times_per_week"), weeklyRepetitions), value: $weeklyRepetitions, in: 1...7)
                }
            }

            // Monthly options
            if frequency == .monthly {
                Stepper(String(format: String(localized: "habit_form_times_per_month"), monthlyRepetitions), value: $monthlyRepetitions, in: 1...31)
            }

            // Custom interval
            if frequency == .customInterval {
                Stepper(String(format: String(localized: "habit_form_every_days"), customInterval), value: $customInterval, in: 2...30)
            }
        }
    }

    // MARK: - Completion Type Section

    private var completionTypeSection: some View {
        Section {
            // Target count toggle
            Toggle(String(localized: "habit_form_track_count"), isOn: $hasTargetCount)

            if hasTargetCount {
                HStack {
                    Text(String(localized: "habit_form_target_label"))
                    Spacer()
                    TextField("", value: $targetCount, format: .number)
                        .keyboardType(.numberPad)
                        .multilineTextAlignment(.trailing)
                        .frame(width: 80)
                }

                Text(String(localized: "habit_form_count_example"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            // Timer toggle (only if not count-based)
            if !hasTargetCount {
                Toggle(String(localized: "habit_form_timer_based"), isOn: $isTimerBased)

                if isTimerBased {
                    Stepper(
                        String(format: String(localized: "habit_form_duration"), durationMinutes),
                        value: $durationMinutes,
                        in: 1...180,
                        step: 5
                    )
                }
            }
        } header: {
            Text(String(localized: "habit_form_completion_type"))
        } footer: {
            if hasTargetCount {
                Text(String(localized: "habit_form_count_hint"))
                    .foregroundStyle(.secondary)
            } else if isTimerBased {
                Text(String(localized: "habit_form_timer_hint"))
                    .foregroundStyle(.secondary)
            } else {
                Text(String(localized: "habit_form_simple_hint"))
                    .foregroundStyle(.secondary)
            }
        }
    }

    // MARK: - Challenge Settings Section

    private var challengeSettingsSection: some View {
        Section {
            // Duration picker
            VStack(alignment: .leading, spacing: 12) {
                Text(String(localized: "challenges_duration"))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                Picker(String(localized: "challenges_duration"), selection: $challengeDuration) {
                    ForEach(durationOptions, id: \.self) { days in
                        Text(String(format: String(localized: "challenges_days_format"), days))
                            .tag(days)
                    }
                }
                .pickerStyle(.segmented)
            }
            .padding(.vertical, 4)

            // Collaborative mode toggle
            Toggle(String(localized: "challenges_collaborative"), isOn: $isCollaborative)

            // Apple Health auto-tracking
            if HealthKitManager.shared.isHealthKitAvailable {
                Picker(String(localized: "challenges_health_tracking"), selection: $selectedHealthKitType) {
                    Text(String(localized: "challenges_health_none")).tag(Optional<HealthKitDataType>.none)
                    ForEach(HealthKitDataType.allCases, id: \.self) { type in
                        Label(type.displayName, systemImage: type.systemImage).tag(Optional(type))
                    }
                }
                .onChange(of: selectedHealthKitType) { _, newType in
                    if let newType { healthKitTarget = newType.defaultTarget }
                }

                if let hkType = selectedHealthKitType {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text(String(localized: "habit_form_daily_target"))
                            Spacer()
                            Text("\(hkType.formatTarget(healthKitTarget)) \(hkType.unit)")
                                .font(.headline)
                        }

                        Slider(
                            value: $healthKitTarget,
                            in: hkType.targetRange,
                            step: hkType.targetStep
                        )

                        HStack(spacing: 8) {
                            ForEach(hkType.targetPresets, id: \.self) { preset in
                                Button {
                                    healthKitTarget = preset
                                } label: {
                                    Text(hkType.formatTarget(preset))
                                        .font(.caption.weight(.medium))
                                        .padding(.horizontal, 10)
                                        .padding(.vertical, 6)
                                        .background(healthKitTarget == preset ? Color(hex: selectedColor) : Color.gray.opacity(0.2))
                                        .foregroundStyle(healthKitTarget == preset ? .white : .primary)
                                        .clipShape(RoundedRectangle(cornerRadius: 6))
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                    .padding(.vertical, 4)
                }
            }
        } header: {
            HStack {
                Image(systemName: "trophy.fill")
                    .foregroundStyle(.orange)
                Text(String(localized: "challenges_settings"))
            }
        } footer: {
            Text(isCollaborative
                ? String(localized: "challenges_collaborative_footer")
                : String(localized: "challenges_competitive_footer"))
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - Friend Selection Section

    private var friendSelectionSection: some View {
        Section {
            if friends.isEmpty {
                HStack {
                    Image(systemName: "person.2")
                        .foregroundStyle(.secondary)
                    Text(String(localized: "challenges_no_friends"))
                        .foregroundStyle(.secondary)
                }
            } else {
                ForEach(friends) { friend in
                    Button {
                        selectedFriend = friend
                    } label: {
                        HStack(spacing: 12) {
                            Text(friend.avatarEmoji)
                                .font(.title2)
                                .frame(width: 40, height: 40)
                                .background(Color(.systemGray5))
                                .clipShape(Circle())

                            VStack(alignment: .leading, spacing: 2) {
                                Text(friend.displayName)
                                    .font(.body)
                                    .foregroundStyle(.primary)

                                if friend.currentStreak > 0 {
                                    HStack(spacing: 4) {
                                        Image(systemName: "flame.fill")
                                            .font(.caption2)
                                            .foregroundStyle(.orange)
                                        Text(String(format: String(localized: "friends_streak_count"), friend.currentStreak))
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                }
                            }

                            Spacer()

                            if selectedFriend?.id == friend.id {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundStyle(Color(hex: selectedColor))
                                    .font(.title2)
                            } else {
                                Image(systemName: "circle")
                                    .foregroundStyle(.secondary)
                                    .font(.title2)
                            }
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
        } header: {
            HStack {
                Image(systemName: "person.2.fill")
                    .foregroundStyle(Color(hex: selectedColor))
                Text(String(localized: "challenges_invite_friend"))
            }
        } footer: {
            if selectedFriend == nil && !friends.isEmpty {
                Text(String(localized: "challenges_select_friend_footer"))
                    .foregroundStyle(.secondary)
            }
        }
    }

    // MARK: - Actions

    private func createChallenge() {
        guard let friend = selectedFriend else { return }

        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else { return }

        isCreating = true

        Task {
            do {
                // Create the challenge with all the habit properties
                let challenge = try await challengeSyncService.createChallenge(
                    participantUserID: friend.cloudUserID,
                    habitName: trimmedName,
                    habitEmoji: useEmoji ? selectedEmoji : selectedSymbol,
                    habitColor: selectedColor,
                    targetDays: challengeDuration,
                    context: modelContext
                )

                // Store additional habit settings on the challenge
                challenge.habitDescription = habitDescription.isEmpty ? nil : habitDescription
                challenge.frequencyRaw = frequency.rawValue
                challenge.scheduledDays = (frequency == .weekly && useSpecificDays) ? Array(selectedDays) : []
                challenge.weeklyRepetitions = (frequency == .weekly && !useSpecificDays) ? weeklyRepetitions : nil
                challenge.monthlyRepetitions = frequency == .monthly ? monthlyRepetitions : nil
                challenge.customInterval = frequency == .customInterval ? customInterval : nil
                challenge.isTimerBased = !hasTargetCount && isTimerBased
                challenge.duration = (!hasTargetCount && isTimerBased) ? durationMinutes * 60 : nil
                challenge.targetCount = hasTargetCount ? targetCount : nil
                challenge.isCollaborative = isCollaborative
                challenge.healthKitType = selectedHealthKitType?.rawValue
                challenge.healthKitTarget = selectedHealthKitType != nil ? healthKitTarget : nil

                try modelContext.save()

                dismiss()
            } catch {
                errorMessage = error.localizedDescription
                showError = true
            }
            isCreating = false
        }
    }
}

#Preview {
    CreateChallengeSheet()
        .modelContainer(.preview)
}
