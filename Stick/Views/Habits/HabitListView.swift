//
//  HabitListView.swift
//  Stick
//
//  Created by Kian Jain on 02.02.26.
//

import SwiftUI
import SwiftData
import Combine
#if canImport(UIKit)
import UIKit
#endif

struct HabitListView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    /// Whether to use the wide (iPad / regular width) layout
    private var isWideLayout: Bool {
        horizontalSizeClass == .regular
    }
    @Query(sort: \Habit.sortOrder, order: .forward) private var allHabits: [Habit]
    @Query private var preferences: [UserPreferences]
    @Query private var skippedDays: [SkippedDay]
    @Query private var allDailyNotes: [DailyNote]

    @Query private var allChallenges: [SharedChallenge]
    @Query private var cloudProfiles: [MyCloudProfile]
    @StateObject private var challengeSyncService = ChallengeSyncService.shared
    @StateObject private var cloudKitService = CloudKitService.shared

    @ObservedObject private var subscriptionService = SubscriptionService.shared
    @ObservedObject private var weeklyWrapService = WeeklyWrapService.shared
    @State private var showingAddHabit = false
    @State private var showingSettings = false
    @State private var isChallengesSectionExpanded: Bool = true
    @State private var selectedChallengeForDetail: SharedChallenge?
    @State private var showingPaywall = false
    @State private var showingWeeklyWrap = false
    @State private var habitToEdit: Habit?
    @State private var habitToDelete: Habit?
    @State private var showingDeleteConfirmation = false
    @State private var selectedDate: Date = Date()
    @State private var completionRefreshTrigger = UUID()
    @State private var showingSkipConfirmation = false
    @State private var showingSkipNotTodayAlert = false
    @State private var showingDailyNoteEditor = false
    @State private var showingFullCalendar = false
    @State private var showingExplore = false
    @State private var isRefreshing = false

    struct FlatGroupBoxStyle: GroupBoxStyle {
        func makeBody(configuration: Configuration) -> some View {
            VStack(alignment: .leading, spacing: 8) {
                configuration.content
            }
            .padding(12)
            .background(Color(uiColor: .secondarySystemGroupedBackground))
            .clipShape(RoundedRectangle(cornerRadius: 24)) // Kleinerer Radius, damit es nicht kollidiert
        }
    }

    /// App accent color from preferences
    private var accentColor: Color {
        let colorValue = preferences.first?.appAccentColor ?? UserPreferences.adaptiveAccentColor
        if colorValue == UserPreferences.adaptiveAccentColor {
            return Color.primary
        }
        return Color(hex: colorValue)
    }

    /// Active habits only
    private var habits: [Habit] {
        allHabits.filter { $0.isActive }
    }

    /// Habits scheduled for selected date (daily, specific days, custom interval)
    private var habitsForSelectedDate: [Habit] {
        habits.filter { habit in
            guard habit.isScheduled(for: selectedDate) else { return false }
            // Exclude flexible weekly/monthly - they have their own section
            if habit.frequency == .weekly && habit.isFlexibleWeekly { return false }
            if habit.frequency == .monthly { return false }
            return true
        }
    }

    /// Flexible weekly habits (X times per week)
    private var flexibleWeeklyHabits: [Habit] {
        habits.filter { $0.frequency == .weekly && $0.isFlexibleWeekly }
    }

    /// Monthly habits
    private var monthlyHabits: [Habit] {
        habits.filter { $0.frequency == .monthly }
    }

    /// All timeframe habits combined
    private var timeframeHabits: [Habit] {
        flexibleWeeklyHabits + monthlyHabits
    }

    /// Check if selected date is today
    private var isToday: Bool {
        Calendar.current.isDateInToday(selectedDate)
    }

    /// Set of all skipped dates for efficient lookup
    private var skippedDateSet: Set<Date> {
        Set(skippedDays.map { Calendar.current.startOfDay(for: $0.date) })
    }

    /// Check if today is skipped
    private var isTodaySkipped: Bool {
        let today = Calendar.current.startOfDay(for: Date())
        return skippedDateSet.contains(today)
    }

    /// Check if selected date is skipped
    private var isSelectedDateSkipped: Bool {
        let day = Calendar.current.startOfDay(for: selectedDate)
        return skippedDateSet.contains(day)
    }

    /// Get note for selected date
    private var noteForSelectedDate: DailyNote? {
        let selectedDayStart = Calendar.current.startOfDay(for: selectedDate)
        return allDailyNotes.first { Calendar.current.isDate($0.date, inSameDayAs: selectedDayStart) }
    }

    /// Today's note (for widget syncing)
    private var todayNote: DailyNote? {
        allDailyNotes.first { Calendar.current.isDateInToday($0.date) }
    }

    // MARK: - List Content (broken out for compiler performance)

    /// Active challenges the current user can interact with today
    private var todayChallenges: [SharedChallenge] {
        let userID = cloudKitService.currentUserID ?? ""
        guard !userID.isEmpty else { return [] }
        return allChallenges.filter { $0.isActive && $0.canMarkTodayComplete }
    }

    private var listContent: some View {
        List {
            progressListSection
            if !todayChallenges.isEmpty && isToday {
                sharedChallengesSection
            }
            habitsListSection
            timeframeListSection
        }
        .listStyle(.insetGrouped)
        .dimThemeBackground()
        .scrollIndicators(.hidden)
        .refreshable {
            await refreshHealthKitData()
        }
    }

    /// Refresh HealthKit data and sync habits
    @MainActor
    private func refreshHealthKitData() async {
        isRefreshing = true

        // Refresh HealthKit today data
        await HealthKitManager.shared.refreshTodayData()

        // Sync all HealthKit-linked habits
        let healthKitHabits = habits.filter { $0.isHealthKitLinked }
        for habit in healthKitHabits {
            await HealthKitManager.shared.syncHabit(habit, for: Date(), context: modelContext)
        }

        // Auto-complete HealthKit-linked shared challenges
        await challengeSyncService.syncHealthKitForChallenges(context: modelContext)

        // Refresh the view
        completionRefreshTrigger = UUID()

        // Update widgets
        WidgetDataService.shared.syncHabits(habits, todayNote: todayNote)

        isRefreshing = false
    }

    private var progressListSection: some View {
        Section {
            if isWideLayout {
                wideProgressLayout
            } else {
                VStack(spacing: 16) {
                    progressSection
                    calendarSection
                    weeklyWrapCard
                    DailyNotesCard(
                        note: noteForSelectedDate,
                        isToday: isToday,
                        onTap: { showingDailyNoteEditor = true }
                    )
                }
            }
        }
        .listRowInsets(EdgeInsets())
        .listRowBackground(Color.clear)
        .listRowSeparator(.hidden)
    }

    /// iPad / regular-width layout: large centered ring with the streak below,
    /// then the stats card and week card side by side.
    private var wideProgressLayout: some View {
        VStack(spacing: 40) {
            // Big centered progress ring resting on a soft ground shadow,
            // with the streak line underneath.
            VStack(spacing: 30) {
                bigProgressRing(diameter: 156, lineWidth: 14)

                streakInline
            }
            .frame(maxWidth: .infinity)
            .padding(.top, 16)

            // Cards group: stats/week row, weekly wrap, and note card share
            // the same 16pt spacing as the gap between the two cards.
            VStack(spacing: 16) {
                // Stats + week view side by side, matched to equal height
                HStack(alignment: .top, spacing: 16) {
                    statsCardView(fillHeight: true)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    calendarSection
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                }
                .fixedSize(horizontal: false, vertical: true)

                weeklyWrapCard

                DailyNotesCard(
                    note: noteForSelectedDate,
                    isToday: isToday,
                    onTap: { showingDailyNoteEditor = true }
                )
            }
        }
    }

    /// Large progress ring that appears to rest on a surface: a soft, flattened
    /// contact shadow sits beneath it, as if lit from above.
    private func bigProgressRing(diameter: CGFloat, lineWidth: CGFloat) -> some View {
        progressRing(diameter: diameter, lineWidth: lineWidth)
            // Soft directional shadow from the "overhead" light on the ring body
            .shadow(color: .black.opacity(0.10), radius: 7, x: 0, y: 6)
            // Flattened ground/contact shadow ellipse beneath the ring
            .background(alignment: .bottom) {
                Ellipse()
                    .fill(Color.black.opacity(0.32))
                    .frame(width: diameter * 0.85, height: diameter * 0.085)
                    .blur(radius: 15)
                    .offset(y: diameter * 0.22)
            }
            // Reserve room so the ground shadow doesn't overlap the streak line
            .padding(.bottom, diameter * 0.18)
    }

    @ViewBuilder
    private var weeklyWrapCard: some View {
        if let wrap = weeklyWrapService.pendingWrap, !wrap.isDismissed {
            WeeklyWrapNotificationCard(wrap: wrap) {
                showingWeeklyWrap = true
            } onDismiss: {
                weeklyWrapService.dismissWrap(wrap, context: modelContext)
            }
        }
    }

    @ViewBuilder
    private var habitsListSection: some View {
        Section {
            if habitsForSelectedDate.isEmpty && timeframeHabits.isEmpty {
                emptyStateView
                    .listRowBackground(Color.clear)
            } else if habitsForSelectedDate.isEmpty {
                Text(String(localized: "habits_no_scheduled_today"))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
            } else {
                ForEach(habitsForSelectedDate) { habit in
                    habitRow(for: habit)
                }
                .onMove(perform: moveHabits)
            }
        } header: {
            habitSectionHeader
        }
    }

    // MARK: - Shared Challenges Section

    @ViewBuilder
    private var sharedChallengesSection: some View {
        Section(isExpanded: $isChallengesSectionExpanded) {
            ForEach(todayChallenges) { challenge in
                SharedChallengeHabitRow(
                    challenge: challenge,
                    currentUserID: cloudKitService.currentUserID ?? "",
                    isCompleted: challengeSyncService.isCompletedToday(challenge, context: modelContext),
                    accentColor: accentColor,
                    onMarkComplete: {
                        Task {
                            try? await challengeSyncService.markTodayComplete(challenge, context: modelContext)
                            completionRefreshTrigger = UUID()
                        }
                    }
                )
                .contentShape(Rectangle())
                .onTapGesture {
                    selectedChallengeForDetail = challenge
                }
            }
        } header: {
            HStack {
                Text(String(localized: "challenges_title"))
                Spacer()
                Text(String(format: String(localized: "habits_count"), todayChallenges.count))
                    .foregroundStyle(.secondary)
            }
            .font(.subheadline)
            .textCase(nil)
        }
    }

    @ViewBuilder
    private var timeframeListSection: some View {
        if !timeframeHabits.isEmpty && isToday {
            Section {
                ForEach(timeframeHabits) { habit in
                    habitRow(for: habit)
                }
                .onMove(perform: moveTimeframeHabits)
            } header: {
                HStack {
                    Text(String(localized: "habits_week_month"))
                    Spacer()
                    Text(String(format: String(localized: "habits_count"), timeframeHabits.count))
                        .foregroundStyle(.secondary)
                }
                .font(.subheadline)
                .textCase(nil)
            }
        }
    }

    // MARK: - Progress

    /// Selected date's progress for the main ring
    /// Only counts daily-type habits (daily, specific-day weekly, custom interval)
    /// Flexible weekly and monthly do NOT count
    /// Skipped days show 0% progress
    private var selectedDateProgress: Double {
        // If selected date is skipped, show 0% progress
        if isSelectedDateSkipped {
            return 0.0
        }
        // If no habits at all, show 0%
        if habits.isEmpty {
            return 0.0
        }
        // Use ProgressTracker for the selected date
        let progress = ProgressTracker.progress(for: selectedDate, habits: habits)
        // If no habits scheduled for that day (but user has habits), show as 100%
        return progress < 0 ? 1.0 : progress
    }

    var body: some View {
        NavigationStack {
            listContent
                .navigationTitle("")
                .toolbar {
                    ToolbarItem(placement: .topBarLeading) {
                        Button { showingSettings = true } label: {
                            if let emoji = cloudProfiles.first?.avatarEmoji, !emoji.isEmpty {
                                Text(emoji).font(.system(size: 20))
                            } else {
                                Image(systemName: "person.fill")
                                    .foregroundStyle(accentColor)
                            }
                        }
                        .buttonStyle(.plain)
                    }

                    ToolbarSpacer(placement: .topBarLeading)

                    ToolbarItem(placement: .topBarLeading) {
                        Button {
                            if isToday {
                                if isTodaySkipped { undoSkipToday() } else { showingSkipConfirmation = true }
                            } else {
                                showingSkipNotTodayAlert = true
                            }
                        } label: {
                            HStack(spacing: 4) {
                                Image(systemName: "zzz").font(.system(size: 12))
                                Text("Skip")
                                    .padding(.leading, 2)
                            }
                            .foregroundStyle(isTodaySkipped ? Color.orange : .primary)
                        }
                    }

                    ToolbarSpacer(placement: .topBarLeading)

                    ToolbarItem(placement: .topBarLeading) {
                        Button { showingExplore = true } label: {
                            HStack(spacing: 4) {
                                Image(systemName: "magnifyingglass").font(.system(size: 12))
                                Text("Explore")
                                    .padding(.leading, 2)
                            }
                        }
                        .tint(.primary)
                    }

                    ToolbarItem(placement: .topBarTrailing) {
                        Button {
                            if subscriptionService.canAddHabit(currentActiveCount: habits.count) {
                                showingAddHabit = true
                            } else {
                                showingPaywall = true
                            }
                        } label: {
                            Image(systemName: "plus")
                        }
                        .tint(.primary)
                    }
                }
        }
        .sheet(isPresented: $showingSettings) {
            SettingsView()
        }
        .sheet(isPresented: $showingAddHabit) {
            HabitFormView()
        }
        .sheet(item: $selectedChallengeForDetail) { challenge in
            ChallengeDetailView(challenge: challenge)
        }
        .sheet(isPresented: $showingPaywall) {
            PaywallView(source: "habit_limit")
        }
        .sheet(item: $habitToEdit) { habit in
            HabitFormView(habitToEdit: habit)
        }
        .alert(
            String(localized: "habits_delete_title"),
            isPresented: $showingDeleteConfirmation
        ) {
            Button(String(localized: "settings_cancel"), role: .cancel) {
                habitToDelete = nil
            }
            Button(String(localized: "settings_delete"), role: .destructive) {
                if let habit = habitToDelete {
                    deleteHabit(habit)
                }
            }
        } message: {
            if let habit = habitToDelete {
                Text(String(format: String(localized: "habits_delete_message"), habit.name))
            }
        }
        .onChange(of: completionRefreshTrigger) { _, _ in
            // Sync widgets when any habit completion changes
            WidgetDataService.shared.syncHabits(habits, todayNote: todayNote)

            // Upload progress to CloudKit for friends to see
            Task {
                await FriendSyncService.shared.uploadProgress(
                    habits: habits,
                    skippedDates: skippedDateSet,
                    threshold: preferences.first?.streakThreshold ?? 1.0
                )
            }
        }
        .fullScreenCover(isPresented: $showingWeeklyWrap) {
            if let wrap = weeklyWrapService.pendingWrap {
                WeeklyWrapStoryView(wrap: wrap) {
                    weeklyWrapService.markAsViewed(wrap, context: modelContext)
                    showingWeeklyWrap = false
                }
            }
        }
        .sheet(isPresented: $showingDailyNoteEditor) {
            DailyNotesEditorView(date: selectedDate, existingNote: noteForSelectedDate)
        }
        .sheet(isPresented: $showingFullCalendar) {
            FullCalendarSheet(
                habits: habits,
                skippedDates: skippedDateSet,
                selectedDate: $selectedDate,
                accentColor: accentColor
            )
        }
        .sheet(isPresented: $showingExplore) {
            ExploreView()
        }
        .alert(
            String(localized: "skip_today_title"),
            isPresented: $showingSkipConfirmation
        ) {
            Button(String(localized: "settings_cancel"), role: .cancel) {}
            Button(String(localized: "skip_today_confirm"), role: .destructive) {
                skipToday()
            }
        } message: {
            Text(String(localized: "skip_today_message"))
        }
        .alert(
            String(localized: "skip_not_today_title"),
            isPresented: $showingSkipNotTodayAlert
        ) {
            Button(String(localized: "timer_done"), role: .cancel) {}
        } message: {
            Text(String(localized: "skip_not_today_message"))
        }
        .onAppear {
            // Check for new weekly wrap
            weeklyWrapService.checkForNewWrap(context: modelContext)

            // Populate progress cache if needed
            if !ProgressCache.shared.isLoaded {
                ProgressCache.shared.populate(habits: habits, skippedDates: skippedDateSet)
            }

            // Sync HealthKit data on appear
            Task {
                await refreshHealthKitData()
                // Upload progress to CloudKit for friends
                await FriendSyncService.shared.uploadProgress(
                    habits: habits,
                    skippedDates: skippedDateSet,
                    threshold: preferences.first?.streakThreshold ?? 1.0
                )
            }
        }
        .onChange(of: scenePhase) { oldPhase, newPhase in
            if newPhase == .active {
                // Sync HealthKit data when returning to app
                Task {
                    await refreshHealthKitData()
                    // Then update progress cache
                    await MainActor.run {
                        ProgressCache.shared.updateDate(Date(), habits: habits, skippedDates: skippedDateSet)
                    }
                    // Upload progress to CloudKit for friends
                    await FriendSyncService.shared.uploadProgress(
                        habits: habits,
                        skippedDates: skippedDateSet,
                        threshold: preferences.first?.streakThreshold ?? 1.0
                    )
                }
            }
        }
        .onChange(of: habits.count) { _, _ in
            // Repopulate cache when habits change
            ProgressCache.shared.populate(habits: habits, skippedDates: skippedDateSet)
        }
    }

    // MARK: - Actions

    private func deleteHabit(_ habit: Habit) {
        // Cancel notifications for this habit
        Task {
            await NotificationManager.shared.cancelNotifications(for: habit)
        }

        // Delete the habit (completions will cascade delete)
        modelContext.delete(habit)

        do {
            try modelContext.save()
            completionRefreshTrigger = UUID()
        } catch {
            print("Failed to delete habit: \(error)")
        }

        habitToDelete = nil
    }

    private func archiveHabit(_ habit: Habit) {
        Task {
            await NotificationManager.shared.cancelNotifications(for: habit)
        }
        habit.isActive = false
        do {
            try modelContext.save()
            completionRefreshTrigger = UUID()
        } catch {
            print("Failed to archive habit: \(error)")
        }
    }

    private func skipToday() {
        let today = Calendar.current.startOfDay(for: Date())

        // Check if already skipped
        guard !skippedDateSet.contains(today) else { return }

        let skippedDay = SkippedDay(date: today)
        modelContext.insert(skippedDay)

        do {
            try modelContext.save()
            completionRefreshTrigger = UUID()
        } catch {
            print("Failed to skip today: \(error)")
        }
    }

    private func undoSkipToday() {
        let today = Calendar.current.startOfDay(for: Date())

        // Find and delete the skipped day for today
        if let skippedDay = skippedDays.first(where: { Calendar.current.isDate($0.date, inSameDayAs: today) }) {
            modelContext.delete(skippedDay)

            do {
                try modelContext.save()
                completionRefreshTrigger = UUID()
            } catch {
                print("Failed to undo skip: \(error)")
            }
        }
    }

    private func moveHabits(from source: IndexSet, to destination: Int) {
        // Create a mutable copy of the habits for selected date
        var reorderedHabits = habitsForSelectedDate

        // Perform the move
        reorderedHabits.move(fromOffsets: source, toOffset: destination)

        // Update sort order for all affected habits
        for (index, habit) in reorderedHabits.enumerated() {
            habit.sortOrder = index
        }

        do {
            try modelContext.save()
            completionRefreshTrigger = UUID()
        } catch {
            print("Failed to reorder habits: \(error)")
        }
    }

    private func moveTimeframeHabits(from source: IndexSet, to destination: Int) {
        // Create a mutable copy of the timeframe habits
        var reorderedHabits = timeframeHabits

        // Perform the move
        reorderedHabits.move(fromOffsets: source, toOffset: destination)

        // Update sort order - offset by 1000 to keep them after daily habits
        for (index, habit) in reorderedHabits.enumerated() {
            habit.sortOrder = 1000 + index
        }

        do {
            try modelContext.save()
            completionRefreshTrigger = UUID()
        } catch {
            print("Failed to reorder timeframe habits: \(error)")
        }
    }

    // MARK: - Progress Section

    /// Calculate overall streak (consecutive days meeting completion threshold)
    /// Skipped days don't break the streak
    private var overallStreak: Int {
        let threshold = preferences.first?.streakThreshold ?? 1.0
        return ProgressTracker.calculateStreak(habits: habits, skippedDates: skippedDateSet, threshold: threshold)
    }

    /// Total time spent on habits this week (in seconds)
    /// Only counts completed timer habits at their full target duration
    private var weeklyTimeSpent: TimeInterval {
        ProgressTracker.weeklyTimeSpent(habits: habits)
    }

    /// Format time spent as readable string
    private var formattedWeeklyTime: String {
        ProgressTracker.formattedWeeklyTime(habits: habits)
    }

    /// Total fully completed habit-days this week
    /// Only counts when target is reached (for count/HealthKit habits) or any completion (for binary habits)
    private var weeklyCompletions: Int {
        let calendar = Calendar.current
        guard let weekInterval = calendar.dateInterval(of: .weekOfYear, for: Date()) else { return 0 }

        var count = 0
        var checkDate = weekInterval.start

        // Check each day of the week
        while checkDate <= Date() {
            for habit in habits {
                if habit.isScheduled(for: checkDate) && habit.isFullyCompleted(for: checkDate) {
                    count += 1
                }
            }
            guard let nextDay = calendar.date(byAdding: .day, value: 1, to: checkDate) else { break }
            checkDate = nextDay
        }

        return count
    }

    private var progressSection: some View {
        HStack(spacing: 0) {
            // Progress ring
            progressRing(diameter: 100, lineWidth: 10)

            Spacer().frame(width: 10)

            // Streak display
            streakCard

            Spacer().frame(width: 10)

            // Stats card
            statsCardView()
        }
    }

    /// Reusable progress ring; fonts scale with the diameter.
    private func progressRing(diameter: CGFloat, lineWidth: CGFloat) -> some View {
        ZStack {
            Circle()
                .strokeBorder(Color.gray.opacity(0.2), lineWidth: lineWidth)

            Circle()
                .trim(from: 0, to: selectedDateProgress)
                .stroke(
                    selectedDateProgress >= 1.0 ? Color.green : accentColor,
                    style: StrokeStyle(lineWidth: lineWidth, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))
                .animation(.spring(duration: 0.5), value: selectedDateProgress)
                .padding(lineWidth / 2) // Inset to match strokeBorder

            VStack(spacing: 2) {
                Text("\(Int(selectedDateProgress * 100))%")
                    .font(.system(size: diameter * 0.22, weight: .bold, design: .rounded))
                    .foregroundStyle(selectedDateProgress >= 1.0 ? .green : .primary)
                Text(String(localized: "habits_today"))
                    .font(.system(size: max(9, diameter * 0.095)))
                    .foregroundStyle(.secondary)
            }
        }
        .frame(width: diameter, height: diameter)
    }

    /// Compact streak line (icon + count + label) used under the big iPad ring.
    private var streakInline: some View {
        HStack(spacing: 6) {
            Image(systemName: "flame.fill")
                .font(.subheadline)
                .foregroundStyle(overallStreak > 0 ? .orange : .gray.opacity(0.4))
            Text("\(overallStreak)")
                .font(.subheadline.bold())
                .foregroundStyle(overallStreak > 0 ? .orange : .secondary)
            Text(String(localized: "habits_streak"))
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }

    private var streakCard: some View {
        VStack(spacing: 4) {
            Image(systemName: "flame.fill")
                .font(.system(size: 24))
                .foregroundStyle(overallStreak > 0 ? .orange : .gray.opacity(0.4))

            Text("\(overallStreak)")
                .font(.title3.bold())
                .foregroundStyle(overallStreak > 0 ? .orange : .secondary)

            Text(String(localized: "habits_streak"))
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .frame(width: 70)
        .frame(height: 100)
//        #if canImport(UIKit)
//        .background(Color(uiColor: .secondarySystemGroupedBackground))
//        #else
//        .background(Color(nsColor: .controlBackgroundColor))
//        #endif
//        .clipShape(RoundedRectangle(cornerRadius: 16))
    }

    private func statsCardView(fillHeight: Bool = false) -> some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 10) {
                // Weekly completions
                HStack(spacing: 6) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(String(format: String(localized: "habits_done_this_week"), weeklyCompletions))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                // Time spent this week
                HStack(spacing: 6) {
                    Image(systemName: "clock.fill")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(String(format: String(localized: "habits_spent_this_week"), formattedWeeklyTime))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                // Motivational text
                Text(motivationalText)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .lineLimit(2)
            }
            .frame(
                maxWidth: .infinity,
                maxHeight: fillHeight ? .infinity : nil,
                alignment: .topLeading
            )
            .padding(.vertical, 4)
        }
        .groupBoxStyle(FlatGroupBoxStyle())
    }

    private var motivationalText: String {
        if habits.isEmpty {
            return String(localized: "motivation_add_first")
        } else if selectedDateProgress >= 1.0 {
            return String(localized: "motivation_amazing") + " 🎉"
        } else if selectedDateProgress >= 0.5 {
            return String(localized: "motivation_halfway")
        } else if overallStreak > 7 {
            return String(localized: "motivation_incredible_streak")
        } else if overallStreak > 0 {
            return String(localized: "motivation_keep_momentum")
        } else {
            return String(localized: "motivation_every_journey")
        }
    }

    // MARK: - Calendar Section

    private var calendarSection: some View {
        VStack(spacing: 12) {
            // Header with calendar button
            HStack {
                Text(String(localized: "habits_this_week"))
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.secondary)

                Spacer()

                Button {
                    showingFullCalendar = true
                } label: {
                    Image(systemName: "arrow.up.right")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }

            // Date header when viewing past date
            if !isToday {
                HStack {
                    Text(selectedDate.formatted(.dateTime.weekday(.wide).month(.wide).day()))
                        .font(.headline)
                        .foregroundStyle(accentColor)

                    Spacer()

                    Button(String(localized: "habits_back_to_today")) {
                        selectedDate = Date()
                    }
                    .font(.subheadline)
                    .foregroundStyle(accentColor)
                    .buttonStyle(.borderless)
                }
            }

            // Week view
            weekViewContent
        }
        .padding()
        #if canImport(UIKit)
        .background(Color(uiColor: .secondarySystemGroupedBackground))
        #else
        .background(Color(nsColor: .controlBackgroundColor))
        #endif
        .clipShape(RoundedRectangle(cornerRadius: 24))
    }

    private var weekViewContent: some View {
        VStack(spacing: 8) {
            // Weekday headers
            HStack(spacing: 4) {
                ForEach(Array(weekdaySymbols.enumerated()), id: \.offset) { _, symbol in
                    Text(symbol)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity)
                }
            }

            // Current week days
            HStack(spacing: 4) {
                ForEach(currentWeekDays, id: \.self) { date in
                    DayCell(
                        date: date,
                        progress: progressForDate(date),
                        isToday: Calendar.current.isDateInToday(date),
                        isSelected: Calendar.current.isDate(date, inSameDayAs: selectedDate),
                        isFuture: date > Date(),
                        accentColor: accentColor,
                        onTap: {
                            var transaction = Transaction()
                            transaction.disablesAnimations = true
                            withTransaction(transaction) {
                                selectedDate = date
                            }
                        }
                    )
                    .frame(maxWidth: .infinity)
                }
            }
        }
    }

    private var currentWeekDays: [Date] {
        let calendar = Calendar.current

        // Get start of week for the selected date
        guard let weekInterval = calendar.dateInterval(of: .weekOfYear, for: selectedDate) else {
            return []
        }

        // Generate all 7 days of that week
        return (0..<7).compactMap { dayOffset in
            calendar.date(byAdding: .day, value: dayOffset, to: weekInterval.start)
        }
    }

    private func progressForDate(_ date: Date) -> Double {
        // Use cached progress for better performance
        return ProgressCache.shared.progress(for: date, habits: habits, skippedDates: skippedDateSet)
    }

    private var weekdaySymbols: [String] {
        let calendar = Calendar.current
        let symbols = calendar.veryShortWeekdaySymbols
        let firstWeekday = calendar.firstWeekday
        let rotationIndex = firstWeekday - 1
        return Array(symbols[rotationIndex...]) + Array(symbols[..<rotationIndex])
    }

    // MARK: - Habit List Section

    private var habitSectionHeader: some View {
        HStack {
            if isToday {
                Text(String(localized: "habits_todays_habits"))
            } else {
                Text(selectedDate.formatted(.dateTime.weekday(.wide).month(.abbreviated).day()))
                Text(String(localized: "habits_view_only"))
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Text(String(format: String(localized: "habits_count"), habitsForSelectedDate.count))
                .foregroundStyle(.secondary)
        }
        .font(.subheadline)
        .textCase(nil)
    }

    private func habitRow(for habit: Habit) -> some View {
        HabitRowView(
            habit: habit,
            date: selectedDate,
            isEditable: isToday,
            accentColor: accentColor,
            refreshTrigger: $completionRefreshTrigger
        )
        .listRowSeparator(.hidden)
        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
            Button {
                habitToDelete = habit
                showingDeleteConfirmation = true
            } label: {
                Image(systemName: "trash")
            }
            .tint(.red)

            Button {
                archiveHabit(habit)
            } label: {
                Image(systemName: "archivebox")
            }
            .tint(.orange)
        }
        .swipeActions(edge: .leading, allowsFullSwipe: true) {
            Button {
                habitToEdit = habit
            } label: {
                Image(systemName: "pencil")
            }
            .tint(.blue)
        }
    }

    private var emptyStateView: some View {
        VStack(spacing: 12) {
            if habits.isEmpty {
                Image(systemName: "checklist")
                    .font(.system(size: 48))
                    .foregroundStyle(.secondary)
                    .padding(.bottom, 4)

                Text(String(localized: "habits_no_habits_yet"))
                    .font(.headline)

                Text(String(localized: "habits_create_first"))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)

                Button {
                    if subscriptionService.canAddHabit(currentActiveCount: habits.count) {
                        showingAddHabit = true
                    } else {
                        showingPaywall = true
                    }
                } label: {
                    Text(String(localized: "habits_add_habit"))
                }
                .buttonStyle(.borderless)
                .foregroundStyle(accentColor)
                .padding(.top, 4)
            } else {
                Image(systemName: "calendar.badge.checkmark")
                    .font(.system(size: 48))
                    .foregroundStyle(.secondary)
                    .padding(.bottom, 4)

                Text(isToday ? String(localized: "habits_no_scheduled_today") : String(localized: "habits_no_scheduled_day"))
                    .font(.headline)

                Text(isToday ? String(localized: "habits_enjoy_day_off") : "")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 32)
    }
}

// MARK: - Month Calendar View

struct MonthCalendarView: View {
    let month: Date
    let habits: [Habit]
    let skippedDates: Set<Date>
    let selectedDate: Date
    let accentColor: Color
    let onDayTapped: (Date) -> Void

    private let calendar = Calendar.current
    private let columns = Array(repeating: GridItem(.flexible(), spacing: 4), count: 7)

    private var weekdaySymbols: [String] {
        let symbols = calendar.veryShortWeekdaySymbols
        let firstWeekday = calendar.firstWeekday
        let rotationIndex = firstWeekday - 1
        return Array(symbols[rotationIndex...]) + Array(symbols[..<rotationIndex])
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Month header
            Text(month.formatted(.dateTime.month(.wide).year()))
                .font(.headline)
                .padding(.leading, 4)

            // Weekday headers
            HStack(spacing: 4) {
                ForEach(Array(weekdaySymbols.enumerated()), id: \.offset) { _, symbol in
                    Text(symbol)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity)
                }
            }

            // Days grid
            LazyVGrid(columns: columns, spacing: 8) {
                // Empty cells for offset
                ForEach(0..<firstWeekdayOffset, id: \.self) { _ in
                    Color.clear
                        .frame(height: 50)
                }

                // Day cells
                ForEach(daysInMonth, id: \.self) { date in
                    DayCell(
                        date: date,
                        progress: progressForDate(date),
                        isToday: calendar.isDateInToday(date),
                        isSelected: calendar.isDate(date, inSameDayAs: selectedDate),
                        isFuture: date > Date(),
                        accentColor: accentColor,
                        onTap: { onDayTapped(date) }
                    )
                }
            }
        }
        .padding(.bottom, 24)
    }

    private var firstWeekdayOffset: Int {
        let firstDayOfMonth = calendar.component(.weekday, from: month)
        let firstWeekday = calendar.firstWeekday
        return (firstDayOfMonth - firstWeekday + 7) % 7
    }

    private var daysInMonth: [Date] {
        guard let range = calendar.range(of: .day, in: .month, for: month) else { return [] }

        return range.compactMap { day -> Date? in
            calendar.date(bySetting: .day, value: day, of: month)
        }
    }

    private func progressForDate(_ date: Date) -> Double {
        // Use cached progress for better performance
        return ProgressCache.shared.progress(for: date, habits: habits, skippedDates: skippedDates)
    }
}

// MARK: - Day Cell

struct DayCell: View {
    let date: Date
    let progress: Double
    let isToday: Bool
    let isSelected: Bool
    let isFuture: Bool
    let accentColor: Color
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            VStack(spacing: 4) {
                // Day number
                Text("\(Calendar.current.component(.day, from: date))")
                    .font(.caption.weight(isToday ? .bold : .regular))
                    .foregroundColor(dayTextColor)

                // Progress ring
                ZStack {
                    Circle()
                        .stroke(ringBackgroundColor, lineWidth: 3)

                    if progress >= 0 && !isFuture {
                        Circle()
                            .trim(from: 0, to: progress)
                            .stroke(
                                progress == 1.0 ? Color.green : accentColor,
                                style: StrokeStyle(lineWidth: 3, lineCap: .round)
                            )
                            .rotationEffect(.degrees(-90))
                    }
                }
                .frame(width: 28, height: 28)
                .overlay {
                    // Today: small dot, Selected: bigger dot
                    if isToday {
                        Circle()
                            .fill(accentColor)
                            .frame(width: 6, height: 6)
                    } else if isSelected {
                        Circle()
                            .fill(accentColor)
                            .frame(width: 12, height: 12)
                    }
                }
            }
            .frame(height: 50)
            .opacity(isFuture ? 0.3 : 1)
        }
        .buttonStyle(.plain)
        .disabled(isFuture)
    }

    private var dayTextColor: Color {
        if isToday {
            return accentColor
        } else if isFuture {
            return Color.gray.opacity(0.4)
        } else {
            return Color.primary
        }
    }

    private var ringBackgroundColor: Color {
        if isToday {
            return accentColor.opacity(0.3)
        } else {
            return Color.gray.opacity(0.2)
        }
    }
}

// MARK: - Habit Row View

struct HabitRowView: View {
    let habit: Habit
    let date: Date
    let isEditable: Bool
    let accentColor: Color
    @Binding var refreshTrigger: UUID

    @Environment(\.modelContext) private var modelContext
    @StateObject private var healthKitManager = HealthKitManager.shared
    @StateObject private var activityManager = TimerActivityManager.shared

    @State private var isCompleted: Bool = false
    @State private var currentCount: Int = 0
    @State private var showingCountPicker: Bool = false
    @State private var showingTimer: Bool = false
    @State private var showingHealthKitInfo: Bool = false
    @State private var healthKitValue: Double = 0
    @State private var displayedRemainingSeconds: Int = 0

    private var isCountBased: Bool { habit.hasTargetCount }
    private var targetCount: Int { habit.targetCount ?? 1 }
    private var isHealthKitLinked: Bool { habit.isHealthKitLinked }

    /// Weekly flexible habit (e.g. "3x/week") without a per-day target count
    private var isWeeklyFlexible: Bool {
        habit.frequency == .weekly && habit.weeklyRepetitions != nil && !habit.usesSpecificDays && !habit.hasTargetCount
    }

    private var weeklyFlexibleProgress: Double {
        guard let reps = habit.weeklyRepetitions, reps > 0 else { return isCompleted ? 1.0 : 0.0 }
        return min(1.0, Double(habit.completionsThisWeek()) / Double(reps))
    }

    /// Whether this habit has an active timer running
    private var hasActiveTimer: Bool {
        activityManager.hasActiveTimer(for: habit.id)
    }

    /// Timer to update the remaining time display (only when needed)
    private let displayUpdateTimer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    private var progress: Double {
        if isCountBased {
            return min(1.0, Double(currentCount) / Double(targetCount))
        } else if isWeeklyFlexible {
            return weeklyFlexibleProgress
        } else {
            return isCompleted ? 1.0 : 0.0
        }
    }

    var body: some View {
        HStack(spacing: 12) {
            // Completion control
            completionControl

            // Icon
            habitIcon

            // Info
            VStack(alignment: .leading, spacing: 4) {
                Text(habit.name)
                    .font(.body.weight(.medium))
                    .strikethrough(isCompleted && isEditable, color: .secondary)
                    .foregroundStyle(isCompleted && isEditable ? .secondary : .primary)

                habitMetadata
            }

            Spacer()
        }
        .contentShape(Rectangle())
        .onTapGesture {
            guard isEditable else { return }

            if isHealthKitLinked {
                showingHealthKitInfo = true
            } else if habit.isTimerBased {
                // Always open timer popup for timer-based habits
                showingTimer = true
            } else if isCountBased || isWeeklyFlexible {
                showingCountPicker = true
            } else {
                toggleBinaryCompletion()
            }
        }
        .onAppear {
            syncCompletionState()
            // Initialize displayed remaining seconds if there's an active timer
            if hasActiveTimer {
                displayedRemainingSeconds = activityManager.getCurrentRemainingSeconds()
            }
        }
        .onChange(of: refreshTrigger) {
            syncCompletionState()
        }
        .onChange(of: date) {
            syncCompletionState()
        }
        .sheet(isPresented: $showingCountPicker) {
            CountPickerSheet(
                currentCount: isWeeklyFlexible ? habit.completionsThisWeek() : currentCount,
                targetCount: isWeeklyFlexible ? (habit.weeklyRepetitions ?? 1) : targetCount,
                habitColor: habit.color,
                onSave: { newCount in
                    if isWeeklyFlexible {
                        setWeeklyCount(newCount)
                    } else {
                        setCount(newCount)
                    }
                }
            )
            .presentationDetents([.height(280)])
        }
        .sheet(isPresented: $showingTimer) {
            HabitTimerView(habit: habit) {
                syncCompletionState()
                refreshTrigger = UUID()
            }
            .presentationDetents([.medium, .large])
            .presentationDragIndicator(.visible)
        }
        .sheet(isPresented: $showingHealthKitInfo) {
            HealthKitInfoSheet(
                habit: habit,
                currentValue: healthKitValue,
                targetValue: targetCount
            )
            .presentationDetents([.height(280)])
        }
        .onReceive(displayUpdateTimer) { _ in
            // Only update remaining seconds if this habit has an active timer
            if hasActiveTimer {
                displayedRemainingSeconds = activityManager.getCurrentRemainingSeconds()
            }
        }
    }

    // MARK: - Completion Control

    @ViewBuilder
    private var completionControl: some View {
        if !isEditable {
            // View-only: just show progress
            viewOnlyProgress
        } else if habit.isTimerBased {
            timerButton
        } else if isCountBased {
            countProgressButton
        } else if isWeeklyFlexible {
            weeklyProgressButton
        } else {
            simpleCompletionButton
        }
    }

    private var viewOnlyProgress: some View {
        ZStack {
            Circle()
                .stroke(Color(hex: habit.color).opacity(0.3), lineWidth: 3)
                .frame(width: 28, height: 28)

            Circle()
                .trim(from: 0, to: progress)
                .stroke(Color(hex: habit.color), style: StrokeStyle(lineWidth: 3, lineCap: .round))
                .frame(width: 28, height: 28)
                .rotationEffect(.degrees(-90))

            if isCompleted {
                Image(systemName: "checkmark")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(Color(hex: habit.color))
            }
        }
    }

    private var timerButton: some View {
        ZStack {
            Circle()
                .stroke(Color(hex: habit.color), lineWidth: 2)
                .frame(width: 28, height: 28)

            if isCompleted {
                Circle()
                    .fill(Color(hex: habit.color))
                    .frame(width: 28, height: 28)

                Image(systemName: "checkmark")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(.white)
            } else if hasActiveTimer {
                // Show active timer indicator
                Circle()
                    .fill(Color(hex: habit.color).opacity(0.2))
                    .frame(width: 28, height: 28)

                Image(systemName: activityManager.isTimerRunning ? "pause.fill" : "play.fill")
                    .font(.system(size: 10))
                    .foregroundStyle(Color(hex: habit.color))
            } else {
                Image(systemName: "play.fill")
                    .font(.system(size: 10))
                    .foregroundStyle(Color(hex: habit.color))
            }
        }
        .contentShape(Circle())
        .highPriorityGesture(
            TapGesture().onEnded {
                // Always open timer popup for timer-based habits
                showingTimer = true
            }
        )
    }

    private var simpleCompletionButton: some View {
        ZStack {
            Circle()
                .stroke(Color(hex: habit.color), lineWidth: 2)
                .frame(width: 28, height: 28)

            if isCompleted {
                Circle()
                    .fill(Color(hex: habit.color))
                    .frame(width: 28, height: 28)

                Image(systemName: "checkmark")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(.white)
            }
        }
        .contentShape(Circle())
        .highPriorityGesture(
            TapGesture().onEnded { toggleBinaryCompletion() }
        )
    }

    private var weeklyProgressButton: some View {
        ZStack {
            if isCompleted {
                Circle()
                    .fill(Color(hex: habit.color))
                    .frame(width: 28, height: 28)

                Image(systemName: "checkmark")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(.white)
            } else {
                Circle()
                    .stroke(Color(hex: habit.color).opacity(0.2), lineWidth: 2)
                    .frame(width: 28, height: 28)

                Circle()
                    .trim(from: 0, to: weeklyFlexibleProgress)
                    .stroke(Color(hex: habit.color), style: StrokeStyle(lineWidth: 2, lineCap: .round))
                    .frame(width: 28, height: 28)
                    .rotationEffect(.degrees(-90))

                Text("\(habit.completionsThisWeek())")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(Color(hex: habit.color))
            }
        }
        .contentShape(Circle())
        .highPriorityGesture(
            TapGesture().onEnded { showingCountPicker = true }
        )
    }

    private var countProgressButton: some View {
        ZStack {
            if isCompleted {
                // Completed state: filled circle with white checkmark (matches other habits)
                Circle()
                    .fill(Color(hex: habit.color))
                    .frame(width: 28, height: 28)

                Image(systemName: "checkmark")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(.white)
            } else {
                // In progress: show ring with progress
                Circle()
                    .stroke(Color(hex: habit.color).opacity(0.2), lineWidth: 2)
                    .frame(width: 28, height: 28)

                Circle()
                    .trim(from: 0, to: progress)
                    .stroke(Color(hex: habit.color), style: StrokeStyle(lineWidth: 2, lineCap: .round))
                    .frame(width: 28, height: 28)
                    .rotationEffect(.degrees(-90))

                if habit.healthKitDataType == .steps {
                    // Show footprint for steps since numbers are too large
                    Image(systemName: "figure.walk")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(Color(hex: habit.color))
                } else {
                    Text("\(currentCount)")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(Color(hex: habit.color))
                }
            }
        }
        .contentShape(Circle())
        .onTapGesture {
            if isHealthKitLinked {
                showingHealthKitInfo = true
            } else {
                incrementCount()
            }
        }
    }

    // MARK: - Habit Icon

    @ViewBuilder
    private var habitIcon: some View {
        ZStack(alignment: .bottomTrailing) {
            Group {
                if let emoji = habit.emoji, !emoji.isEmpty {
                    Text(emoji)
                        .font(.title2)
                } else if let symbolName = habit.symbolName, !symbolName.isEmpty {
                    Image(systemName: symbolName)
                        .font(.title2)
                        .foregroundStyle(Color(hex: habit.color))
                } else {
                    Image(systemName: "checkmark.circle")
                        .font(.title2)
                        .foregroundStyle(Color(hex: habit.color))
                }
            }
            .frame(width: 40, height: 40)
            .background(Color(hex: habit.color).opacity(0.15))
            .clipShape(RoundedRectangle(cornerRadius: 10))

            // HealthKit badge
            if isHealthKitLinked {
                Image(systemName: "heart.fill")
                    .font(.system(size: 10))
                    .foregroundStyle(.white)
                    .padding(3)
                    .background(.red)
                    .clipShape(Circle())
                    .offset(x: 4, y: 4)
            }
        }
    }

    // MARK: - Habit Metadata

    private var habitMetadata: some View {
        HStack(spacing: 12) {
            if isCountBased {
                if isHealthKitLinked, let dataType = habit.healthKitDataType {
                    // Show HealthKit value with unit
                    Text("\(healthKitManager.formatValue(healthKitValue, for: dataType))/\(targetCount) \(dataType.unit)")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.secondary)
                } else {
                    Text("\(currentCount)/\(targetCount)")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.secondary)
                }
            }

            if let progressText = habit.repetitionProgressText() {
                Text(progressText)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
            }

            // Timer display - show active timer or target duration
            if habit.isTimerBased {
                if hasActiveTimer {
                    // Show active timer with remaining time
                    HStack(spacing: 3) {
                        Image(systemName: activityManager.isTimerRunning ? "timer" : "pause.fill")
                        Text(formatSeconds(displayedRemainingSeconds))
                    }
                    .font(.caption.weight(.medium))
                    .foregroundStyle(Color(hex: habit.color))
                } else if let duration = habit.duration {
                    HStack(spacing: 3) {
                        Image(systemName: "timer")
                        Text(formatDuration(duration))
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
            }
        }
    }

    // MARK: - State Management

    private func syncCompletionState() {
        currentCount = habit.currentCount(for: date)

        if isCountBased {
            isCompleted = habit.isTargetReached(for: date)
        } else {
            isCompleted = habit.isEffectivelyCompleted(for: date)
        }

        // Fetch HealthKit data if linked
        if isHealthKitLinked, let dataType = habit.healthKitDataType {
            Task {
                healthKitValue = await healthKitManager.fetchValue(for: dataType, date: date)

                // Update current count from HealthKit value for display
                if isCountBased {
                    let hkCount = Int(healthKitValue)
                    if hkCount > currentCount {
                        currentCount = hkCount
                        isCompleted = currentCount >= targetCount
                    }
                }
            }
        }
    }

    private func toggleBinaryCompletion() {
        guard isEditable else { return }

        let wasCompleted = isCompleted
        withAnimation(.spring(duration: 0.3)) {
            isCompleted.toggle()
        }

        if wasCompleted {
            let todayCompletions = habit.completions(for: date)
            for completion in todayCompletions {
                modelContext.delete(completion)
            }
        } else {
            let completion = HabitCompletion(
                habit: habit,
                actualDuration: habit.isTimerBased ? habit.duration : nil
            )
            modelContext.insert(completion)
            habit.safeCompletions.append(completion)
        }

        saveAndRefresh(revertCompletion: wasCompleted)
    }

    private func incrementCount() {
        guard isEditable else { return }

        let previousCount = currentCount
        let newCount = currentCount + 1

        withAnimation(.spring(duration: 0.3)) {
            currentCount = newCount
            isCompleted = newCount >= targetCount
        }

        let todayCompletions = habit.completions(for: date)

        if let existing = todayCompletions.first {
            existing.count = newCount
        } else {
            let completion = HabitCompletion(habit: habit, count: 1)
            modelContext.insert(completion)
            habit.safeCompletions.append(completion)
        }

        saveAndRefresh(revertCount: previousCount)
    }

    private func setCount(_ newCount: Int) {
        guard isEditable else { return }

        let previousCount = currentCount

        withAnimation(.spring(duration: 0.3)) {
            currentCount = newCount
            isCompleted = newCount >= targetCount
        }

        let todayCompletions = habit.completions(for: date)

        if newCount == 0 {
            for completion in todayCompletions {
                modelContext.delete(completion)
            }
        } else if let existing = todayCompletions.first {
            existing.count = newCount
        } else {
            let completion = HabitCompletion(habit: habit, count: newCount)
            modelContext.insert(completion)
            habit.safeCompletions.append(completion)
        }

        saveAndRefresh(revertCount: previousCount)
    }

    /// Set weekly completion count by adding/removing today's binary completion
    private func setWeeklyCount(_ newCount: Int) {
        guard isEditable else { return }
        let current = habit.completionsThisWeek()
        guard newCount != current else { return }

        let wasCompleted = isCompleted

        if newCount > current {
            // Mark today as done if not already
            if habit.completions(for: date).isEmpty {
                let completion = HabitCompletion(habit: habit)
                modelContext.insert(completion)
                habit.safeCompletions.append(completion)
            }
        } else {
            // Unmark today
            let todayCompletions = habit.completions(for: date)
            for completion in todayCompletions {
                modelContext.delete(completion)
            }
        }

        saveAndRefresh(revertCompletion: wasCompleted)
    }

    private func saveAndRefresh(revertCompletion: Bool? = nil, revertCount: Int? = nil) {
        do {
            try modelContext.save()
            // Widget sync happens in parent view via onChange of refreshTrigger
        } catch {
            if let wasCompleted = revertCompletion {
                isCompleted = wasCompleted
            }
            if let previousCount = revertCount {
                currentCount = previousCount
                isCompleted = previousCount >= targetCount
            }
            print("Failed to save: \(error)")
        }

        refreshTrigger = UUID()
    }

    private func formatDuration(_ duration: TimeInterval) -> String {
        let minutes = Int(duration) / 60
        if minutes >= 60 {
            let hours = minutes / 60
            let remainingMinutes = minutes % 60
            return remainingMinutes > 0 ? "\(hours)h \(remainingMinutes)m" : "\(hours)h"
        }
        return "\(minutes)m"
    }

    private func formatSeconds(_ seconds: Int) -> String {
        let mins = seconds / 60
        let secs = seconds % 60
        return String(format: "%d:%02d", mins, secs)
    }
}

// MARK: - Count Picker Sheet

struct CountPickerSheet: View {
    let currentCount: Int
    let targetCount: Int
    let habitColor: String
    let onSave: (Int) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var selectedCount: Int = 0

    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                Text("\(selectedCount) / \(targetCount)")
                    .font(.system(size: 48, weight: .bold, design: .rounded))
                    .foregroundStyle(Color(hex: habitColor))

                HStack(spacing: 32) {
                    Button {
                        if selectedCount > 0 { selectedCount -= 1 }
                    } label: {
                        Image(systemName: "minus.circle.fill")
                            .font(.system(size: 44))
                            .foregroundStyle(selectedCount > 0 ? Color(hex: habitColor) : .gray)
                    }
                    .disabled(selectedCount <= 0)

                    Button {
                        selectedCount += 1
                    } label: {
                        Image(systemName: "plus.circle.fill")
                            .font(.system(size: 44))
                            .foregroundStyle(Color(hex: habitColor))
                    }
                }

                HStack(spacing: 12) {
                    ForEach([0, targetCount / 2, targetCount], id: \.self) { value in
                        Button {
                            selectedCount = value
                        } label: {
                            Text("\(value)")
                                .font(.subheadline.weight(.medium))
                                .frame(width: 50, height: 36)
                                .background(selectedCount == value ? Color(hex: habitColor) : Color.gray.opacity(0.2))
                                .foregroundStyle(selectedCount == value ? .white : .primary)
                                .clipShape(RoundedRectangle(cornerRadius: 8))
                        }
                    }
                }
            }
            .padding()
            .navigationTitle(String(localized: "habits_set_count"))
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .tint(Color(red: 0.4, green: 0.4, blue: 0.45))
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(String(localized: "settings_cancel")) { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(String(localized: "settings_save")) {
                        onSave(selectedCount)
                        dismiss()
                    }
                    .fontWeight(.semibold)
                }
            }
        }
        .onAppear {
            selectedCount = currentCount
        }
    }
}

// MARK: - HealthKit Info Sheet

struct HealthKitInfoSheet: View {
    let habit: Habit
    let currentValue: Double
    let targetValue: Int

    @Environment(\.dismiss) private var dismiss

    private var progress: Double {
        guard targetValue > 0 else { return 0 }
        return min(1.0, currentValue / Double(targetValue))
    }

    private var dataType: HealthKitDataType? {
        habit.healthKitDataType
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 20) {
                // Current value + unit
                if let dataType = dataType {
                    VStack(spacing: 4) {
                        Text("\(Int(currentValue))")
                            .font(.system(size: 48, weight: .bold, design: .rounded))
                            .foregroundStyle(progress >= 1.0 ? .green : Color(hex: habit.color))
                        Text(dataType.unit)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }

                // Progress bar
                VStack(spacing: 8) {
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            RoundedRectangle(cornerRadius: 8)
                                .fill(Color(hex: habit.color).opacity(0.15))
                                .frame(height: 16)
                            RoundedRectangle(cornerRadius: 8)
                                .fill(progress >= 1.0 ? Color.green : Color(hex: habit.color))
                                .frame(width: geo.size.width * progress, height: 16)
                                .animation(.easeOut(duration: 0.4), value: progress)
                        }
                    }
                    .frame(height: 16)

                    if let dataType = dataType {
                        Text("\(Int(currentValue)) / \(targetValue) \(dataType.unit)")
                            .font(.caption.weight(.medium))
                            .foregroundStyle(progress >= 1.0 ? .green : .primary)
                    }
                }

                Spacer()

                // Open Health app button
                Button {
                    if let url = URL(string: "x-apple-health://") {
                        #if canImport(UIKit)
                        UIApplication.shared.open(url)
                        #endif
                    }
                } label: {
                    Label(String(localized: "healthkit_open_health"), systemImage: "heart.fill")
                        .font(.body.weight(.medium))
                        .foregroundStyle(.red)
                }
                .padding(.bottom, 8)
            }
            .padding(.horizontal, 24)
            .padding(.top, 28)
            .navigationTitle(habit.name)
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(String(localized: "timer_done")) { dismiss() }
                }
            }
        }
    }
}

// MARK: - Full Calendar Sheet

struct FullCalendarSheet: View {
    let habits: [Habit]
    let skippedDates: Set<Date>
    @Binding var selectedDate: Date
    let accentColor: Color

    @Environment(\.dismiss) private var dismiss

    private var allMonths: [Date] {
        let calendar = Calendar.current
        var months: [Date] = []

        for i in 0..<12 {
            if let month = calendar.date(byAdding: .month, value: -i, to: Date()) {
                months.append(calendar.startOfMonth(for: month))
            }
        }

        return months
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(allMonths, id: \.self) { month in
                        MonthCalendarView(
                            month: month,
                            habits: habits,
                            skippedDates: skippedDates,
                            selectedDate: selectedDate,
                            accentColor: accentColor,
                            onDayTapped: { date in
                                selectedDate = date
                                dismiss()
                            }
                        )
                        .padding(.horizontal)
                    }
                }
            }
            .navigationTitle(String(localized: "habits_calendar"))
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(String(localized: "timer_done")) {
                        dismiss()
                    }
                }
            }
        }
    }
}

// MARK: - Calendar Extension

extension Calendar {
    func startOfMonth(for date: Date) -> Date {
        let components = dateComponents([.year, .month], from: date)
        return self.date(from: components) ?? date
    }
}

// MARK: - Previews

#Preview("With Habits") {
    HabitListView()
        .modelContainer(.preview)
}

#Preview("Empty State") {
    HabitListView()
        .modelContainer(for: [Habit.self, Goal.self, HabitCompletion.self], inMemory: true)
}
