//
//  HabitFormView.swift
//  Stick
//
//  Created by Kian Jain on 02.02.26.
//

import SwiftUI
import SwiftData
#if canImport(UIKit)
import UIKit
#endif

/// Wrapper for scheduled times with stable identity
struct ScheduledTime: Identifiable {
    let id = UUID()
    var time: Date

    init(_ time: Date = Date()) {
        self.time = time
    }
}

struct HabitFormView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @Query(sort: \Goal.createdDate, order: .forward) private var goals: [Goal]

    // MARK: - Form State

    @State private var name: String = ""
    @State private var habitDescription: String = ""
    @State private var selectedColor: String = Color.habitColorHexes[0]
    @State private var selectedEmoji: String = "✨"
    @State private var useEmoji: Bool = true
    @State private var selectedSymbol: String = "star.fill"

    @State private var frequency: HabitFrequency = .daily
    @State private var selectedDays: Set<Int> = []
    @State private var useSpecificDays: Bool = true  // For weekly: specific days vs flexible
    @State private var weeklyRepetitions: Int = 3    // Times per week (1-7)
    @State private var monthlyRepetitions: Int = 10  // Times per month (1-31)
    @State private var customInterval: Int = 2

    @State private var scheduledTimes: [ScheduledTime] = []

    @State private var isTimerBased: Bool = false
    @State private var durationMinutes: Int = 30

    @State private var hasTargetCount: Bool = false
    @State private var targetCount: Int = 8

    @State private var selectedGoal: Goal?

    @State private var notificationsEnabled: Bool = true
    @State private var reminderMessage: String = ""

    // Goal creation
    @State private var showingGoalCreation = false
    @State private var newGoalName = ""
    @State private var newGoalDescription = ""

    // HealthKit
    @StateObject private var healthKitManager = HealthKitManager.shared
    @State private var linkToHealthKit = false
    @State private var selectedHealthKitType: HealthKitDataType = .steps
    @State private var healthKitTodayValue: Double = 0
    @State private var healthKitTarget: Double = 10000 // Default for steps

    // MARK: - Validation

    private var isValid: Bool {
        !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    // MARK: - Editing Mode

    var habitToEdit: Habit?

    var isEditing: Bool {
        habitToEdit != nil
    }

    // MARK: - Body

    var body: some View {
        NavigationStack {
            Form {
                // Basic Info
                basicInfoSection

                // Appearance
                appearanceSection

                // Schedule
                scheduleSection

                // Completion type (count/timer)
                completionTypeSection

                // Goal
                goalSection

                // HealthKit
                healthKitSection

                // Notifications
                notificationSection
            }
            .dimThemeBackground()
            .navigationTitle(isEditing ? String(localized: "habit_form_edit_title") : String(localized: "habit_form_new_title"))
            #if os(iOS)
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            #endif
            .tint(Color(red: 0.4, green: 0.4, blue: 0.45))
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(String(localized: "settings_cancel")) {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(isEditing ? String(localized: "settings_save") : String(localized: "habit_form_add")) {
                        saveHabit()
                    }
                    .fontWeight(.semibold)
                    .disabled(!isValid)
                }
            }
            .onAppear {
                loadExistingHabit()
            }
            .sheet(isPresented: $showingGoalCreation) {
                GoalCreationSheet(
                    goalName: $newGoalName,
                    goalDescription: $newGoalDescription,
                    accentColor: selectedColor,
                    onCreate: createGoal
                )
                .interactiveDismissDisabled(false)
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
                // Schedule type picker
                Picker(String(localized: "habit_form_schedule_type"), selection: $useSpecificDays) {
                    Text(String(localized: "habit_form_specific_days")).tag(true)
                    Text(String(localized: "habit_form_flexible")).tag(false)
                }
                .pickerStyle(.segmented)

                if useSpecificDays {
                    // Specific days selector
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
                    // Flexible repetitions
                    Stepper(String(format: String(localized: "habit_form_times_per_week"), weeklyRepetitions), value: $weeklyRepetitions, in: 1...7)
                }
            }

            // Monthly options
            if frequency == .monthly {
                Stepper(String(format: String(localized: "habit_form_times_per_month"), monthlyRepetitions), value: $monthlyRepetitions, in: 1...31)
            }

            // Custom interval picker
            if frequency == .customInterval {
                Stepper(String(format: String(localized: "habit_form_every_days"), customInterval), value: $customInterval, in: 2...30)
            }

            // Scheduled times
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text(String(localized: "habit_form_reminder_times"))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)

                    Spacer()

                    Button {
                        addDefaultTime()
                    } label: {
                        Image(systemName: "plus.circle.fill")
                            .foregroundStyle(Color(hex: selectedColor))
                    }
                }

                if scheduledTimes.isEmpty {
                    Text(String(localized: "habit_form_no_reminders"))
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                } else {
                    ForEach($scheduledTimes) { $scheduledTime in
                        HStack {
                            DatePicker(
                                "",
                                selection: $scheduledTime.time,
                                displayedComponents: .hourAndMinute
                            )
                            .labelsHidden()

                            Spacer()

                            Button {
                                removeTime(scheduledTime)
                            } label: {
                                Image(systemName: "minus.circle.fill")
                                    .foregroundStyle(.red)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
            .padding(.vertical, 4)
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

    // MARK: - Goal Section

    private var goalSection: some View {
        Section {
            HStack {
                if goals.isEmpty {
                    Text(String(localized: "settings_no_goals"))
                        .foregroundStyle(.secondary)
                } else {
                    Picker(String(localized: "habit_form_assign_goal"), selection: $selectedGoal) {
                        Text(String(localized: "habit_form_none")).tag(nil as Goal?)
                        ForEach(goals) { goal in
                            Text(goal.name).tag(goal as Goal?)
                        }
                    }
                }

                Spacer()

                Button {
                    showingGoalCreation = true
                } label: {
                    Image(systemName: "plus.circle.fill")
                        .foregroundStyle(Color(hex: selectedColor))
                        .font(.title2)
                }
                .buttonStyle(.plain)
            }
        } header: {
            Text(String(localized: "habit_form_goal"))
        } footer: {
            Text(String(localized: "habit_form_goal_footer"))
                .foregroundStyle(.secondary)
        }
    }

    private func createGoal(name: String, description: String) {
        let goal = Goal(name: name, description: description.isEmpty ? nil : description)
        modelContext.insert(goal)
        selectedGoal = goal
        newGoalName = ""
        newGoalDescription = ""
    }

    // MARK: - HealthKit Section

    private var healthKitSection: some View {
        Section {
            if !healthKitManager.isHealthKitAvailable {
                HStack {
                    Image(systemName: "heart.slash")
                        .foregroundStyle(.secondary)
                    Text(String(localized: "habit_form_healthkit_unavailable"))
                        .foregroundStyle(.secondary)
                }
            } else {
                Toggle(String(localized: "habit_form_link_health"), isOn: $linkToHealthKit)
                    .onChange(of: linkToHealthKit) { _, newValue in
                        if newValue && !healthKitManager.isAuthorized {
                            Task {
                                let authorized = await healthKitManager.requestAuthorization()
                                if !authorized {
                                    linkToHealthKit = false
                                } else {
                                    await updateHealthKitTodayValue()
                                }
                            }
                        } else if newValue {
                            Task {
                                await updateHealthKitTodayValue()
                            }
                        }
                    }

                if linkToHealthKit {
                    Picker(String(localized: "habit_form_data_type"), selection: $selectedHealthKitType) {
                        ForEach(HealthKitDataType.allCases, id: \.self) { type in
                            Label(type.localizedName, systemImage: type.systemImage)
                                .tag(type)
                        }
                    }
                    .onChange(of: selectedHealthKitType) { _, newType in
                        // Set appropriate default target for each type
                        healthKitTarget = defaultTarget(for: newType)
                        Task {
                            await updateHealthKitTodayValue()
                        }
                    }

                    HStack {
                        Image(systemName: selectedHealthKitType.systemImage)
                            .foregroundStyle(Color(hex: selectedColor))
                        Text(String(format: String(localized: "habit_form_today_value"), healthKitManager.formatValue(healthKitTodayValue, for: selectedHealthKitType), selectedHealthKitType.unit))
                            .foregroundStyle(.secondary)
                    }

                    // Target slider
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text(String(localized: "habit_form_daily_target"))
                            Spacer()
                            Text("\(formatTarget(healthKitTarget)) \(selectedHealthKitType.unit)")
                                .font(.headline)
                                .foregroundStyle(Color(hex: selectedColor))
                        }

                        Slider(
                            value: $healthKitTarget,
                            in: targetRange(for: selectedHealthKitType),
                            step: targetStep(for: selectedHealthKitType)
                        )
                        .tint(Color(hex: selectedColor))

                        // Quick preset buttons
                        HStack(spacing: 8) {
                            ForEach(targetPresets(for: selectedHealthKitType), id: \.self) { preset in
                                Button {
                                    healthKitTarget = preset
                                } label: {
                                    Text(formatTarget(preset))
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
                Image(systemName: "heart.fill")
                    .foregroundStyle(.red)
                Text(String(localized: "habit_form_healthkit"))
            }
        } footer: {
            if linkToHealthKit {
                Text(String(localized: "habit_form_healthkit_footer"))
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func updateHealthKitTodayValue() async {
        healthKitTodayValue = await healthKitManager.fetchValue(for: selectedHealthKitType, date: Date())
    }

    private func defaultTarget(for type: HealthKitDataType) -> Double {
        type.defaultTarget
    }

    private func formatTarget(_ value: Double) -> String {
        selectedHealthKitType.formatTarget(value)
    }

    private func targetRange(for type: HealthKitDataType) -> ClosedRange<Double> {
        type.targetRange
    }

    private func targetStep(for type: HealthKitDataType) -> Double {
        type.targetStep
    }

    private func targetPresets(for type: HealthKitDataType) -> [Double] {
        type.targetPresets
    }

    // MARK: - Notification Section

    private var notificationSection: some View {
        Section {
            Toggle(String(localized: "settings_enable_notifications"), isOn: $notificationsEnabled)

            if notificationsEnabled {
                TextField(String(localized: "habit_form_custom_message"), text: $reminderMessage)
                    .submitLabel(.done)
            }
        } header: {
            Text(String(localized: "settings_notifications"))
        } footer: {
            if notificationsEnabled {
                Text(String(localized: "habit_form_notifications_footer"))
                    .foregroundStyle(.secondary)
            }
        }
    }

    // MARK: - Actions

    private func addDefaultTime() {
        var components = Calendar.current.dateComponents([.year, .month, .day], from: Date())
        components.hour = 9
        components.minute = 0
        if let defaultTime = Calendar.current.date(from: components) {
            withAnimation {
                scheduledTimes.append(ScheduledTime(defaultTime))
            }
        }
    }

    private func removeTime(_ time: ScheduledTime) {
        withAnimation {
            scheduledTimes.removeAll { $0.id == time.id }
        }
    }

    private func saveHabit() {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else { return }

        // Determine scheduled days (only for weekly with specific days)
        let daysToSave: [Int] = (frequency == .weekly && useSpecificDays) ? Array(selectedDays) : []

        // Determine repetitions based on frequency and schedule type
        let weeklyRepsToSave: Int? = (frequency == .weekly && !useSpecificDays) ? weeklyRepetitions : nil
        let monthlyRepsToSave: Int? = (frequency == .monthly) ? monthlyRepetitions : nil

        // Determine target count and duration
        // When HealthKit is linked, use healthKitTarget as the target count
        let countToSave: Int? = linkToHealthKit ? Int(healthKitTarget) : (hasTargetCount ? targetCount : nil)
        let durationToSave: TimeInterval? = (!hasTargetCount && isTimerBased) ? TimeInterval(durationMinutes * 60) : nil

        let habitToSchedule: Habit

        // Determine HealthKit settings
        let healthKitTypeToSave: String? = linkToHealthKit ? selectedHealthKitType.rawValue : nil

        if let habit = habitToEdit {
            // Update existing habit
            habit.name = trimmedName
            habit.habitDescription = habitDescription.isEmpty ? nil : habitDescription
            habit.color = selectedColor
            habit.emoji = useEmoji ? selectedEmoji : nil
            habit.symbolName = useEmoji ? nil : selectedSymbol
            habit.frequency = frequency
            habit.scheduledDays = daysToSave
            habit.weeklyRepetitions = weeklyRepsToSave
            habit.monthlyRepetitions = monthlyRepsToSave
            habit.customInterval = frequency == .customInterval ? customInterval : nil
            habit.scheduledTimes = scheduledTimes.map(\.time)
            habit.duration = durationToSave
            habit.targetCount = countToSave
            habit.goal = selectedGoal
            habit.notificationsEnabled = notificationsEnabled
            habit.reminderMessage = reminderMessage.isEmpty ? nil : reminderMessage
            habit.healthKitType = healthKitTypeToSave
            habit.healthKitAutoComplete = linkToHealthKit
            habitToSchedule = habit
        } else {
            // Create new habit
            let habit = Habit(
                name: trimmedName,
                description: habitDescription.isEmpty ? nil : habitDescription,
                color: selectedColor,
                symbolName: useEmoji ? nil : selectedSymbol,
                emoji: useEmoji ? selectedEmoji : nil,
                frequency: frequency,
                scheduledDays: daysToSave,
                scheduledTimes: scheduledTimes.map(\.time),
                customInterval: frequency == .customInterval ? customInterval : nil,
                duration: durationToSave,
                targetCount: countToSave,
                weeklyRepetitions: weeklyRepsToSave,
                monthlyRepetitions: monthlyRepsToSave,
                notificationsEnabled: notificationsEnabled,
                reminderMessage: reminderMessage.isEmpty ? nil : reminderMessage,
                goal: selectedGoal,
                healthKitType: healthKitTypeToSave,
                healthKitAutoComplete: linkToHealthKit
            )
            modelContext.insert(habit)
            habitToSchedule = habit
        }

        // Schedule notifications for the habit
        Task {
            await NotificationManager.shared.scheduleNotifications(for: habitToSchedule)
        }

        dismiss()
    }

    private func loadExistingHabit() {
        guard let habit = habitToEdit else { return }

        name = habit.name
        habitDescription = habit.habitDescription ?? ""
        selectedColor = habit.color
        useEmoji = habit.emoji != nil
        selectedEmoji = habit.emoji ?? "✨"
        selectedSymbol = habit.symbolName ?? "star.fill"
        frequency = habit.frequency
        selectedDays = Set(habit.scheduledDays)

        // Determine if using specific days or flexible repetitions
        if habit.frequency == .weekly {
            useSpecificDays = habit.weeklyRepetitions == nil
            weeklyRepetitions = habit.weeklyRepetitions ?? 3
        }
        monthlyRepetitions = habit.monthlyRepetitions ?? 10

        customInterval = habit.customInterval ?? 2
        scheduledTimes = habit.scheduledTimes.map { ScheduledTime($0) }
        isTimerBased = habit.isTimerBased
        durationMinutes = habit.duration.map { Int($0 / 60) } ?? 30
        hasTargetCount = habit.hasTargetCount
        targetCount = habit.targetCount ?? 8
        selectedGoal = habit.goal
        notificationsEnabled = habit.notificationsEnabled
        reminderMessage = habit.reminderMessage ?? ""

        // Load HealthKit settings
        linkToHealthKit = habit.isHealthKitLinked
        if let dataType = habit.healthKitDataType {
            selectedHealthKitType = dataType
            // Restore HealthKit target from saved targetCount
            if let savedTarget = habit.targetCount {
                healthKitTarget = Double(savedTarget)
            } else {
                healthKitTarget = defaultTarget(for: dataType)
            }
        }

        // Fetch today's HealthKit value if linked
        if linkToHealthKit {
            Task {
                await updateHealthKitTodayValue()
            }
        }
    }
}

// MARK: - Weekday Button

struct WeekdayButton: View {
    let day: Weekday
    let isSelected: Bool
    let accentColor: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(String(day.shortName.prefix(1)))
                .font(.caption.weight(.medium))
                .frame(width: 36, height: 36)
                .background(isSelected ? Color(hex: accentColor) : Color.gray.opacity(0.2))
                .foregroundStyle(isSelected ? .white : .primary)
                .clipShape(Circle())
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Emoji Picker Grid

struct EmojiPickerGrid: View {
    @Binding var selectedEmoji: String
    let accentColor: String

    @State private var showingCustomEmojiInput = false
    @State private var customEmojiText: String = ""
    @State private var isEmojiFieldFocused: Bool = false

    // 23 emojis + 1 plus button = 24 total (3 rows of 8)
    private let emojis = [
        "✨", "💪", "🏃", "🧘", "📚", "💧", "🍎",
        "🎯", "💡", "🎨", "🎵", "✍️", "🧠", "❤️", "🌟",
        "☀️", "🌙", "🔥", "💎", "🏆", "🎉", "🌱", "🧹"
    ]

    var body: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 8), spacing: 8) {
            // Plus button for custom emoji - first item
            ZStack {
                if showingCustomEmojiInput {
                    EmojiTextField(text: $customEmojiText, isFirstResponder: $isEmojiFieldFocused)
                        .frame(width: 36, height: 36)
                        .background(Color(hex: accentColor).opacity(0.2))
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                        .onChange(of: customEmojiText) { _, newValue in
                            if let first = newValue.first, first.isEmoji {
                                selectedEmoji = String(first)
                                customEmojiText = ""
                                showingCustomEmojiInput = false
                                isEmojiFieldFocused = false
                            } else if !newValue.isEmpty {
                                customEmojiText = ""
                            }
                        }
                } else {
                    Button {
                        showingCustomEmojiInput = true
                        customEmojiText = ""
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                            isEmojiFieldFocused = true
                        }
                    } label: {
                        Image(systemName: "plus")
                            .font(.system(size: 18, weight: .medium))
                            .foregroundStyle(Color(hex: accentColor))
                            .frame(width: 36, height: 36)
                            .background(Color(hex: accentColor).opacity(0.15))
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                    }
                    .buttonStyle(.plain)
                }
            }

            // Preset emojis
            ForEach(emojis, id: \.self) { emoji in
                Text(emoji)
                    .font(.title2)
                    .frame(width: 36, height: 36)
                    .background(
                        selectedEmoji == emoji
                            ? Color(hex: accentColor).opacity(0.3)
                            : Color.clear
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                    .onTapGesture {
                        selectedEmoji = emoji
                        showingCustomEmojiInput = false
                    }
            }
        }
    }
}

// MARK: - Emoji TextField (opens emoji keyboard directly)

#if canImport(UIKit)
struct EmojiTextField: UIViewRepresentable {
    @Binding var text: String
    @Binding var isFirstResponder: Bool

    func makeUIView(context: Context) -> UITextField {
        let textField = EmojiOnlyTextField()
        textField.delegate = context.coordinator
        textField.textAlignment = .center
        textField.font = .systemFont(ofSize: 24)
        textField.backgroundColor = .clear
        textField.tintColor = .clear
        return textField
    }

    func updateUIView(_ uiView: UITextField, context: Context) {
        uiView.text = text
        if isFirstResponder && !uiView.isFirstResponder {
            uiView.becomeFirstResponder()
        } else if !isFirstResponder && uiView.isFirstResponder {
            uiView.resignFirstResponder()
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    class Coordinator: NSObject, UITextFieldDelegate {
        var parent: EmojiTextField

        init(_ parent: EmojiTextField) {
            self.parent = parent
        }

        func textField(_ textField: UITextField, shouldChangeCharactersIn range: NSRange, replacementString string: String) -> Bool {
            if let char = string.first, char.isEmoji {
                parent.text = String(char)
            }
            return false
        }

        func textFieldDidEndEditing(_ textField: UITextField) {
            parent.isFirstResponder = false
        }
    }
}

class EmojiOnlyTextField: UITextField {
    override var textInputMode: UITextInputMode? {
        for mode in UITextInputMode.activeInputModes {
            if mode.primaryLanguage == "emoji" {
                return mode
            }
        }
        return super.textInputMode
    }
}
#else
struct EmojiTextField: View {
    @Binding var text: String
    @Binding var isFirstResponder: Bool

    var body: some View {
        TextField("", text: $text)
            .font(.title2)
            .multilineTextAlignment(.center)
    }
}
#endif

// MARK: - Character Extension for Emoji Detection

extension Character {
    var isEmoji: Bool {
        guard let scalar = unicodeScalars.first else { return false }
        return scalar.properties.isEmoji && (scalar.value > 0x238C || unicodeScalars.count > 1)
    }
}

// MARK: - Symbol Picker Grid

struct SymbolPickerGrid: View {
    @Binding var selectedSymbol: String
    let accentColor: String

    private let symbols = [
        "star.fill", "heart.fill", "bolt.fill", "flame.fill",
        "leaf.fill", "drop.fill", "moon.fill", "sun.max.fill",
        "figure.run", "figure.yoga", "dumbbell.fill", "sportscourt.fill",
        "book.fill", "pencil", "brain.head.profile", "lightbulb.fill",
        "cup.and.saucer.fill", "fork.knife", "bed.double.fill", "shower.fill",
        "music.note", "paintbrush.fill", "camera.fill", "gamecontroller.fill"
    ]

    var body: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 8), spacing: 8) {
            ForEach(symbols, id: \.self) { symbol in
                Image(systemName: symbol)
                    .font(.system(size: 18))
                    .frame(width: 36, height: 36)
                    .background(
                        selectedSymbol == symbol
                            ? Color(hex: accentColor).opacity(0.3)
                            : Color.clear
                    )
                    .foregroundStyle(
                        selectedSymbol == symbol
                            ? Color(hex: accentColor)
                            : .primary
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                    .onTapGesture {
                        selectedSymbol = symbol
                    }
            }
        }
    }
}

// MARK: - Habit Icon Preview

struct HabitIconPreview: View {
    let icon: String
    let isEmoji: Bool
    let color: String

    var body: some View {
        Group {
            if isEmoji {
                Text(icon)
                    .font(.title)
            } else {
                Image(systemName: icon)
                    .font(.title2)
                    .foregroundStyle(Color(hex: color))
            }
        }
        .frame(width: 50, height: 50)
        .background(Color(hex: color).opacity(0.15))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}

// MARK: - Previews

// MARK: - Goal Creation Sheet

struct GoalCreationSheet: View {
    @Binding var goalName: String
    @Binding var goalDescription: String
    let accentColor: String
    let onCreate: (String, String) -> Void

    @Environment(\.dismiss) private var dismiss

    private var isValid: Bool {
        !goalName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField(String(localized: "settings_goal_name"), text: $goalName)
                        .submitLabel(.done)

                    TextField(String(localized: "settings_description_optional"), text: $goalDescription, axis: .vertical)
                        .lineLimit(2...4)
                        .submitLabel(.done)
                        .onSubmit {
                            #if canImport(UIKit)
                            UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
                            #endif
                        }
                } header: {
                    Text(String(localized: "settings_goal_details"))
                } footer: {
                    if goalName.isEmpty {
                        Text(String(localized: "habit_form_name_required"))
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .dimThemeBackground()
            .navigationTitle(String(localized: "habit_form_new_goal"))
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .tint(Color(hex: accentColor))
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(String(localized: "settings_cancel")) {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(String(localized: "habit_form_create")) {
                        onCreate(goalName.trimmingCharacters(in: .whitespacesAndNewlines), goalDescription)
                        dismiss()
                    }
                    .fontWeight(.semibold)
                    .disabled(!isValid)
                }
            }
        }
        .presentationDetents([.medium])
    }
}

#Preview("New Habit") {
    HabitFormView()
        .modelContainer(.preview)
}

#Preview("Edit Habit") {
    HabitFormView()
        .modelContainer(.preview)
}
