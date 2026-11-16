//
//  AnalyticsView.swift
//  Stick
//
//  Created by Kian Jain on 02.02.26.
//

import SwiftUI
import SwiftData
import Charts
import Combine

struct AnalyticsView: View {
    @Query(sort: \Habit.createdDate, order: .forward) private var allHabits: [Habit]
    @Query(sort: \HabitCompletion.completionDate, order: .reverse) private var allCompletions: [HabitCompletion]
    @Query private var preferences: [UserPreferences]

    @State private var selectedTimeRange: TimeRange = .week

    private var activeHabits: [Habit] {
        allHabits.filter { $0.isActive }
    }

    /// Accent color from preferences
    private var accentColor: Color {
        let colorValue = preferences.first?.appAccentColor ?? UserPreferences.adaptiveAccentColor
        if colorValue == UserPreferences.adaptiveAccentColor {
            return Color.primary
        }
        return Color(hex: colorValue)
    }

    enum TimeRange: String, CaseIterable {
        case week = "Week"
        case month = "Month"
        case year = "Year"

        var localizedName: String {
            switch self {
            case .week: return String(localized: "analytics_week")
            case .month: return String(localized: "analytics_month")
            case .year: return String(localized: "analytics_year")
            }
        }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    // Picker right under title
                    timeRangePicker
                        .padding(.horizontal)

                    // 4 stat cards
                    summarySection
                        .padding(.horizontal)

                    // Sections
                    AnalyticsSection(String(localized: "analytics_completion_trend")) {
                        trendChartSection
                    }
                    .padding(.horizontal)

                    AnalyticsSection(String(localized: "analytics_completion_history")) {
                        completionCalendarSection
                    }
                    .padding(.horizontal)

                    AnalyticsSection(String(localized: "analytics_habit_statistics")) {
                        if activeHabits.isEmpty {
                            Text(String(localized: "habits_no_habits_yet"))
                                .foregroundStyle(.secondary)
                                .frame(maxWidth: .infinity)
                                .padding()
                        } else {
                            VStack(spacing: 0) {
                                ForEach(activeHabits) { habit in
                                    HabitStatRow(habit: habit)
                                    if habit.id != activeHabits.last?.id {

                                        Divider()
                                    }
                                }
                            }
                        }
                    }
                    .padding(.horizontal)

                }
                .padding(.bottom, 35)
            }
            .dimThemeScrollBackground()
            .navigationTitle(String(localized: "analytics_title"))
        }
    }

    // MARK: - Time Range Picker

    private var timeRangePicker: some View {
        Picker("Time Range", selection: $selectedTimeRange) {
            ForEach(TimeRange.allCases, id: \.self) { range in
                Text(range.localizedName).tag(range)
            }
        }
        .pickerStyle(.segmented)
    }

    // MARK: - Summary Section

    private var summarySection: some View {
        let spacing: CGFloat = 12
        return LazyVGrid(columns: [
            GridItem(.flexible(), spacing: spacing),
            GridItem(.flexible(), spacing: spacing)
        ], spacing: spacing) {
            StatCard(
                title: String(localized: "analytics_active_habits"),
                value: "\(activeHabits.count)",
                icon: "checkmark.circle.fill",
                color: accentColor
            )

            StatCard(
                title: String(localized: "analytics_completion_rate"),
                value: "\(Int(completionRate * 100))%",
                icon: "chart.pie.fill",
                color: completionRate >= 0.7 ? .green : (completionRate >= 0.4 ? .orange : .red)
            )

            StatCard(
                title: String(localized: "analytics_best_streak"),
                value: "\(bestStreak)",
                icon: "flame.fill",
                color: .orange
            )

            StatCard(
                title: String(localized: "analytics_total_completions"),
                value: "\(totalCompletions)",
                icon: "star.fill",
                color: .purple
            )
        }
    }

    // MARK: - Completion Calendar Section

    private var completionCalendarSection: some View {
        CompletionHeatmap(
            completions: allCompletions,
            habits: activeHabits,
            weeks: selectedTimeRange == .week ? 1 : (selectedTimeRange == .month ? 5 : 52),
            accentColor: accentColor
        )
    }

    // MARK: - Trend Chart Section

    private var trendChartSection: some View {
        Group {
            if #available(iOS 17.0, macOS 14.0, *) {
                CompletionTrendChart(
                    data: trendData,
                    timeRange: selectedTimeRange,
                    accentColor: accentColor
                )
                .frame(height: 200)
                .padding(.top, 16)
            } else {
                Text(String(localized: "analytics_charts_require"))
                    .foregroundStyle(.secondary)
                    .frame(height: 200)
            }
        }
    }

    // MARK: - Computed Statistics

    private var completionRate: Double {
        let calendar = Calendar.current
        let startDate: Date

        switch selectedTimeRange {
        case .week:
            startDate = calendar.date(byAdding: .day, value: -7, to: Date()) ?? Date()
        case .month:
            startDate = calendar.date(byAdding: .month, value: -1, to: Date()) ?? Date()
        case .year:
            startDate = calendar.date(byAdding: .year, value: -1, to: Date()) ?? Date()
        }

        guard !activeHabits.isEmpty else { return 0 }

        var totalProgress = 0.0
        var daysWithHabits = 0

        var checkDate = startDate
        while checkDate <= Date() {
            // Use ProgressTracker for consistency - includes partial completion
            let progress = ProgressTracker.progress(for: checkDate, habits: activeHabits)
            if progress >= 0 { // -1 means no habits scheduled
                totalProgress += progress
                daysWithHabits += 1
            }
            checkDate = calendar.date(byAdding: .day, value: 1, to: checkDate) ?? Date()
        }

        guard daysWithHabits > 0 else { return 0 }
        return totalProgress / Double(daysWithHabits)
    }

    private var bestStreak: Int {
        activeHabits.map { $0.currentStreak() }.max() ?? 0
    }

    /// Total fully completed habit-days in the selected time range
    private var totalCompletions: Int {
        let calendar = Calendar.current
        let startDate: Date

        switch selectedTimeRange {
        case .week:
            startDate = calendar.date(byAdding: .day, value: -7, to: Date()) ?? Date()
        case .month:
            startDate = calendar.date(byAdding: .month, value: -1, to: Date()) ?? Date()
        case .year:
            startDate = calendar.date(byAdding: .year, value: -1, to: Date()) ?? Date()
        }

        var count = 0
        var checkDate = startDate

        while checkDate <= Date() {
            for habit in activeHabits {
                if habit.isScheduled(for: checkDate) && habit.isFullyCompleted(for: checkDate) {
                    count += 1
                }
            }
            guard let nextDay = calendar.date(byAdding: .day, value: 1, to: checkDate) else { break }
            checkDate = nextDay
        }

        return count
    }

    private var trendData: [DailyCompletion] {
        let calendar = Calendar.current
        let days: Int

        switch selectedTimeRange {
        case .week:
            days = 7
        case .month:
            days = 30
        case .year:
            days = 365
        }

        var data: [DailyCompletion] = []

        for dayOffset in (0..<days).reversed() {
            guard let date = calendar.date(byAdding: .day, value: -dayOffset, to: Date()) else { continue }

            // Use ProgressTracker for consistency - includes partial completion, capped at 1.0
            let scheduled = ProgressTracker.scheduledHabits(from: activeHabits, for: date)
            let progress = ProgressTracker.progress(for: date, habits: activeHabits)
            let rate = progress >= 0 ? progress : 0

            // Count actually completed habits
            let completedCount = scheduled.filter { habit in
                habit.isFullyCompleted(for: date)
            }.count

            data.append(DailyCompletion(date: date, rate: rate, completed: completedCount, scheduled: scheduled.count))
        }

        return data
    }
}

// MARK: - Analytics Section

struct AnalyticsSection<Content: View>: View {
    let title: String
    let content: Content

    init(_ title: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.headline)
                .padding(.horizontal)
                .padding(.top)

            content
                .padding([.horizontal, .bottom])
        }
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 20))
    }
}

// MARK: - Data Types

struct DailyCompletion: Identifiable {
    let id = UUID()
    let date: Date
    let rate: Double
    let completed: Int
    let scheduled: Int
}

// MARK: - Stat Card

struct StatCard: View {
    let title: String
    let value: String
    let icon: String
    let color: Color

    var body: some View {
        VStack(spacing: 4) {
            Image(systemName: icon)
                .font(.system(size: 22))
                .foregroundStyle(color)

            Text(value)
                .font(.title3.bold())

            Text(title)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 24))
    }
}

// MARK: - Completion Heatmap

struct CompletionHeatmap: View {
    let completions: [HabitCompletion]
    let habits: [Habit]
    let weeks: Int
    let accentColor: Color

    private let calendar = Calendar.current
    private let spacing: CGFloat = 6

    // Locale-aware day labels
    private var dayLabels: [String] {
        let symbols = calendar.veryShortWeekdaySymbols
        let firstWeekday = calendar.firstWeekday
        let rotationIndex = firstWeekday - 1
        return Array(symbols[rotationIndex...]) + Array(symbols[..<rotationIndex])
    }

    private var gridColumns: [GridItem] {
        Array(repeating: GridItem(.flexible(), spacing: spacing), count: 7)
    }

    var body: some View {
        let today = Date()

        // Get the end of the current week to align the grid
        let weekInterval = calendar.dateInterval(of: .weekOfYear, for: today)
        let endOfWeek = weekInterval.map { calendar.date(byAdding: .day, value: 6, to: $0.start) ?? today } ?? today

        // Calculate total days: full weeks ending at end of current week
        let totalDays = weeks * 7
        let startDate = calendar.date(byAdding: .day, value: -(totalDays - 1), to: endOfWeek) ?? today

        VStack(spacing: 12) {
            // Day labels row
            LazyVGrid(columns: gridColumns, spacing: spacing) {
                ForEach(0..<7, id: \.self) { index in
                    Text(dayLabels[index])
                        .font(.caption)
                        .fontWeight(.medium)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity)
                }
            }

            // Heatmap grid - aligned to week boundaries
            LazyVGrid(columns: gridColumns, spacing: spacing) {
                ForEach(0..<totalDays, id: \.self) { dayOffset in
                    if let date = calendar.date(byAdding: .day, value: dayOffset, to: startDate) {
                        let isFuture = date > today
                        let rate = isFuture ? -1 : completionRate(for: date)
                        RoundedRectangle(cornerRadius: 4)
                            .fill(isFuture ? Color.clear : colorForRate(rate))
                            .aspectRatio(1, contentMode: .fit)
                    }
                }
            }

            // Legend
            HStack(spacing: 6) {
                Text(String(localized: "analytics_less"))
                    .font(.caption2)
                    .foregroundStyle(.secondary)

                ForEach([0.0, 0.25, 0.5, 0.75, 1.0], id: \.self) { rate in
                    RoundedRectangle(cornerRadius: 3)
                        .fill(colorForRate(rate))
                        .frame(width: 14, height: 14)
                }

                Text(String(localized: "analytics_more"))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func completionRate(for date: Date) -> Double {
        // Use ProgressTracker for consistency with main view
        ProgressTracker.progress(for: date, habits: habits)
    }

    private func colorForRate(_ rate: Double) -> Color {
        if rate < 0 {
            return Color.gray.opacity(0.1)
        } else if rate == 0 {
            return Color.gray.opacity(0.2)
        } else if rate < 0.25 {
            return accentColor.opacity(0.25)
        } else if rate < 0.5 {
            return accentColor.opacity(0.5)
        } else if rate < 0.75 {
            return accentColor.opacity(0.75)
        } else {
            return accentColor
        }
    }
}

// MARK: - Completion Trend Chart

@available(iOS 17.0, macOS 14.0, *)
struct CompletionTrendChart: View {
    let data: [DailyCompletion]
    let timeRange: AnalyticsView.TimeRange
    let accentColor: Color

    @State private var selectedDate: Date?

    /// Valid date range from the data
    private var dateRange: ClosedRange<Date>? {
        guard let first = data.first?.date, let last = data.last?.date else { return nil }
        return first...last
    }

    /// The item to display stats for - selected date or today
    private var displayItem: DailyCompletion? {
        let calendar = Calendar.current
        if let selectedDate {
            return data.first { calendar.isDate($0.date, inSameDayAs: selectedDate) }
        }
        // Default to today
        return data.first { calendar.isDateInToday($0.date) } ?? data.last
    }

    var body: some View {
        VStack(spacing: 16) {
            // Chart
            Chart(data) { item in
                if timeRange == .year {
                    // For year view, use bar marks aggregated by week
                    BarMark(
                        x: .value("Date", item.date, unit: .weekOfYear),
                        y: .value("Rate", item.rate * 100)
                    )
                    .foregroundStyle(accentColor.gradient)
                } else {
                    // For week/month, use smooth area chart (no dots)
                    AreaMark(
                        x: .value("Date", item.date, unit: .day),
                        y: .value("Rate", item.rate * 100)
                    )
                    .foregroundStyle(accentColor.opacity(0.2).gradient)
                    .interpolationMethod(.catmullRom)

                    LineMark(
                        x: .value("Date", item.date, unit: .day),
                        y: .value("Rate", item.rate * 100)
                    )
                    .foregroundStyle(accentColor)
                    .lineStyle(StrokeStyle(lineWidth: 2.5, lineCap: .round, lineJoin: .round))
                    .interpolationMethod(.catmullRom)
                }

                // Selection indicator line
                if let selectedDate, timeRange != .year {
                    RuleMark(x: .value("Date", selectedDate, unit: .day))
                        .foregroundStyle(Color.gray.opacity(0.5))
                        .lineStyle(StrokeStyle(lineWidth: 1))
                }
            }
            .chartYScale(domain: 0...100)
            .chartYAxis {
                AxisMarks(position: .leading) { value in
                    AxisValueLabel {
                        if let intValue = value.as(Int.self) {
                            Text("\(intValue)%")
                        }
                    }
                    AxisGridLine()
                }
            }
            .chartXAxis {
                if timeRange == .week {
                    // Week: Show abbreviated weekday names (Mon, Tue, etc.)
                    AxisMarks(values: .stride(by: .day)) { value in
                        AxisValueLabel(format: .dateTime.weekday(.abbreviated))
                    }
                } else if timeRange == .month {
                    // Month: Show day numbers only (1, 8, 15, 22, 29)
                    AxisMarks(values: .stride(by: .day, count: 7)) { value in
                        AxisValueLabel(format: .dateTime.day())
                    }
                } else {
                    // Year: Show short month names every 2 months (Jan, Mar, May, etc.)
                    AxisMarks(values: .stride(by: .month, count: 2)) { value in
                        AxisValueLabel(format: .dateTime.month(.abbreviated))
                    }
                }
            }
            .chartXSelection(value: $selectedDate)
            .onChange(of: selectedDate) { _, newValue in
                // Clamp selection to valid date range
                guard let newValue, let range = dateRange else { return }
                if newValue < range.lowerBound {
                    selectedDate = range.lowerBound
                } else if newValue > range.upperBound {
                    selectedDate = range.upperBound
                }
            }

            // Stats below chart
            if let item = displayItem {
                statsRow(for: item)
            }
        }
    }

    private func statsRow(for item: DailyCompletion) -> some View {
        HStack(spacing: 0) {
            // Date - fixed width to prevent layout shifts
            VStack(alignment: .leading, spacing: 2) {
                Text(Calendar.current.isDateInToday(item.date) && selectedDate == nil ? String(localized: "analytics_today") : item.date.formatted(.dateTime.weekday(.wide).month(.abbreviated).day()))
                    .font(.subheadline.weight(.medium))
                Text(selectedDate == nil ? String(localized: "analytics_current") : String(localized: "analytics_selected"))
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
            .frame(width: 140, alignment: .leading)

            Spacer()

            // Percentage
            VStack(alignment: .center, spacing: 2) {
                Text("\(Int(item.rate * 100))%")
                    .font(.title3.bold())
                    .foregroundStyle(item.rate >= 0.7 ? .green : (item.rate >= 0.4 ? accentColor : .secondary))
                Text(String(localized: "analytics_completion"))
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }

            Spacer()

            // Completed count
            VStack(alignment: .trailing, spacing: 2) {
                Text("\(item.completed)/\(item.scheduled)")
                    .font(.title3.bold())
                Text(String(localized: "analytics_habits"))
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(.horizontal, 4)
        .animation(.easeInOut(duration: 0.15), value: item.date)
    }
}

// MARK: - Habit Stat Row

struct HabitStatRow: View {
    let habit: Habit

    var body: some View {
        HStack(spacing: 12) {
            // Icon
            Group {
                if let emoji = habit.emoji, !emoji.isEmpty {
                    Text(emoji)
                        .font(.title3)
                } else if let symbolName = habit.symbolName, !symbolName.isEmpty {
                    Image(systemName: symbolName)
                        .font(.title3)
                        .foregroundStyle(Color(hex: habit.color))
                } else {
                    Image(systemName: "checkmark.circle")
                        .font(.title3)
                        .foregroundStyle(Color(hex: habit.color))
                }
            }
            .frame(width: 36, height: 36)
            .background(Color(hex: habit.color).opacity(0.15))
            .clipShape(RoundedRectangle(cornerRadius: 8))

            // Name
            VStack(alignment: .leading, spacing: 2) {
                Text(habit.name)
                    .font(.subheadline.weight(.medium))

                Text(habit.frequency.localizedName)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            // Stats
            HStack(spacing: 16) {
                // Streak
                VStack(spacing: 2) {
                    HStack(spacing: 2) {
                        Image(systemName: "flame.fill")
                            .font(.caption)
                            .foregroundStyle(.orange)
                        Text("\(habit.currentStreak())")
                            .font(.subheadline.weight(.semibold))
                    }
                    Text(String(localized: "analytics_streak"))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }

                // Completion rate
                VStack(spacing: 2) {
                    Text("\(Int(habitCompletionRate * 100))%")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(habitCompletionRate >= 0.7 ? .green : .primary)
                    Text(String(localized: "analytics_rate"))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(.vertical, 8)
    }

    private var habitCompletionRate: Double {
        let calendar = Calendar.current
        guard let startDate = calendar.date(byAdding: .day, value: -30, to: Date()) else { return 0 }

        var totalProgress = 0.0
        var scheduledDays = 0

        var checkDate = startDate
        while checkDate <= Date() {
            if habit.isScheduled(for: checkDate) && habit.createdDate <= checkDate {
                scheduledDays += 1
                // Use ProgressTracker for partial completion consistency
                totalProgress += ProgressTracker.habitProgress(habit, for: checkDate)
            }
            checkDate = calendar.date(byAdding: .day, value: 1, to: checkDate) ?? Date()
        }

        guard scheduledDays > 0 else { return 0 }
        return totalProgress / Double(scheduledDays)
    }
}

// MARK: - Preview

#Preview {
    AnalyticsView()
        .modelContainer(.preview)
}
