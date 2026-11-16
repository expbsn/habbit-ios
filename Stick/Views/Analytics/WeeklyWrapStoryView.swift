//
//  WeeklyWrapStoryView.swift
//  Stick
//
//  Instagram-style story viewer for weekly wrap stats.
//

import SwiftUI
import SwiftData
import Photos
#if canImport(UIKit)
import UIKit
#endif

struct WeeklyWrapStoryView: View {
    let wrap: WeeklyWrap
    let onDismiss: () -> Void

    @Query private var preferences: [UserPreferences]
    @State private var currentPage = 0
    @State private var showingSaveConfirmation = false
    @State private var dragOffset: CGFloat = 0
    @Environment(\.colorScheme) private var colorScheme

    private var appTheme: AppTheme {
        preferences.first?.theme ?? .system
    }

    private var totalPages: Int {
        var count = 6 // Base screens: intro, completion, highlight, time, top habit, summary
        if wrap.hasComparison { count += 1 } // Comparison screen
        return count
    }

    // Accent colors for each screen based on emoji theme
    private var accentColors: [Color] {
        [
            Color.purple.opacity(0.6),   // Intro 👋
            Color.orange.opacity(0.6),   // Completion 🔥
            Color.yellow.opacity(0.6),   // Highlight ⭐️
            Color.green.opacity(0.6),    // Comparison 📈
            Color.blue.opacity(0.6),     // Time ⏱️
            Color.pink.opacity(0.6),     // Top habit 🏆
            Color.purple.opacity(0.6),   // Summary 🎉
            Color.indigo.opacity(0.6)    // Extra
        ]
    }

    private var backgroundColor: Color {
        switch appTheme {
        case .dark:
            return .black
        case .dim:
            return Color(white: 0.1)
        case .light:
            return .white
        case .system:
            return colorScheme == .dark ? .black : .white
        }
    }

    private var isDarkAppearance: Bool {
        switch appTheme {
        case .dark, .dim:
            return true
        case .light:
            return false
        case .system:
            return colorScheme == .dark
        }
    }

    private var textColor: Color {
        isDarkAppearance ? .white : .black
    }

    private var secondaryTextColor: Color {
        isDarkAppearance ? .white.opacity(0.7) : .black.opacity(0.6)
    }

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                // Background with subtle gradient
                ZStack {
                    backgroundColor.ignoresSafeArea()

                    // Subtle gradient overlay based on current screen's accent
                    RadialGradient(
                        colors: [
                            accentColors[min(currentPage, accentColors.count - 1)].opacity(0.3),
                            Color.clear
                        ],
                        center: .topTrailing,
                        startRadius: 0,
                        endRadius: geometry.size.width * 1.2
                    )
                    .ignoresSafeArea()
                    .animation(.easeInOut(duration: 0.4), value: currentPage)
                }

                VStack(spacing: 0) {
                    // Progress indicators
                    progressIndicators
                        .padding(.top, 16)
                        .padding(.horizontal, 16)

                    Spacer()

                    // Page content
                    pageContent
                        .padding(.horizontal, 24)

                    Spacer()
                    Spacer()
                }

                // Tap zones for navigation
                HStack(spacing: 0) {
                    // Left tap zone - go back
                    Color.clear
                        .contentShape(Rectangle())
                        .onTapGesture {
                            if currentPage > 0 {
                                withAnimation { currentPage -= 1 }
                            }
                        }

                    // Right tap zone - go forward (except on last page)
                    Color.clear
                        .contentShape(Rectangle())
                        .onTapGesture {
                            if currentPage < totalPages - 1 {
                                withAnimation { currentPage += 1 }
                            }
                        }
                }
                .allowsHitTesting(currentPage < totalPages - 1) // Disable on last page for buttons
            }
            .offset(y: dragOffset)
            .gesture(
                DragGesture()
                    .onChanged { value in
                        if value.translation.height > 0 {
                            dragOffset = value.translation.height
                        }
                    }
                    .onEnded { value in
                        if value.translation.height > 100 {
                            onDismiss()
                        } else {
                            withAnimation(.spring(duration: 0.3)) {
                                dragOffset = 0
                            }
                        }
                    }
            )
        }
        .alert(String(localized: "weekly_wrap_saved_title"), isPresented: $showingSaveConfirmation) {
            Button(String(localized: "timer_done")) {
                onDismiss()
            }
        } message: {
            Text(String(localized: "weekly_wrap_saved_message"))
        }
    }

    // MARK: - Progress Indicators

    private var progressIndicators: some View {
        HStack(spacing: 4) {
            ForEach(0..<totalPages, id: \.self) { index in
                Capsule()
                    .fill(index <= currentPage ? textColor : textColor.opacity(0.3))
                    .frame(height: 3)
            }
        }
    }

    // MARK: - Page Content Router

    @ViewBuilder
    private var pageContent: some View {
        switch currentPage {
        case 0:
            introScreen
        case 1:
            completionRateScreen
        case 2:
            highlightDayScreen
        case 3:
            if wrap.hasComparison {
                comparisonScreen
            } else {
                timeTrackedScreen
            }
        case 4:
            if wrap.hasComparison {
                timeTrackedScreen
            } else {
                topHabitScreen
            }
        case 5:
            if wrap.hasComparison {
                topHabitScreen
            } else {
                summaryScreen
            }
        case 6:
            summaryScreen
        default:
            summaryScreen
        }
    }

    // MARK: - Screen 1: Intro

    private var introScreen: some View {
        VStack(spacing: 32) {
            Text("👋")
                .font(.system(size: 72))

            VStack(spacing: 16) {
                Text(String(localized: "weekly_wrap_intro_personal"))
                    .font(.title.bold())
                    .foregroundStyle(textColor)
                    .multilineTextAlignment(.center)

                Text(wrap.dateRangeString)
                    .font(.title3.weight(.medium))
                    .foregroundStyle(secondaryTextColor)

                Text(String(localized: "weekly_wrap_intro_subtitle"))
                    .font(.body)
                    .foregroundStyle(secondaryTextColor)
                    .multilineTextAlignment(.center)
                    .padding(.top, 8)
            }
        }
    }

    // MARK: - Screen 2: Completion Rate

    private var completionRateScreen: some View {
        VStack(spacing: 32) {
            Text(completionEmoji)
                .font(.system(size: 72))

            VStack(spacing: 16) {
                Text("\(wrap.completionRatePercent)%")
                    .font(.system(size: 80, weight: .bold))
                    .foregroundStyle(textColor)

                Text(completionComment)
                    .font(.title3)
                    .foregroundStyle(secondaryTextColor)
                    .multilineTextAlignment(.center)

                if wrap.perfectDays > 0 {
                    HStack(spacing: 6) {
                        Image(systemName: "star.fill")
                            .foregroundStyle(.yellow)
                        Text(String(format: String(localized: "weekly_wrap_perfect_days_inline"), wrap.perfectDays))
                            .foregroundStyle(secondaryTextColor)
                    }
                    .font(.subheadline.weight(.medium))
                    .padding(.top, 8)
                }
            }
        }
    }

    private var completionEmoji: String {
        if wrap.completionRate >= 0.9 { return "🔥" }
        if wrap.completionRate >= 0.7 { return "💪" }
        if wrap.completionRate >= 0.5 { return "👊" }
        if wrap.completionRate >= 0.3 { return "🌱" }
        return "🌱"
    }

    private var completionComment: String {
        if wrap.completionRate >= 0.9 {
            return String(localized: "weekly_wrap_completion_amazing")
        } else if wrap.completionRate >= 0.7 {
            return String(localized: "weekly_wrap_completion_solid")
        } else if wrap.completionRate >= 0.5 {
            return String(localized: "weekly_wrap_completion_halfway")
        } else if wrap.completionRate >= 0.3 {
            return String(localized: "weekly_wrap_completion_building")
        } else {
            return String(localized: "weekly_wrap_completion_start")
        }
    }

    // MARK: - Screen 3: Highlight Day

    private var highlightDayScreen: some View {
        VStack(spacing: 32) {
            Text("⭐️")
                .font(.system(size: 72))

            VStack(spacing: 16) {
                if let dayName = wrap.highlightDayName {
                    Text(dayName)
                        .font(.system(size: 40, weight: .bold))
                        .foregroundStyle(textColor)

                    Text(highlightDayComment)
                        .font(.title3)
                        .foregroundStyle(secondaryTextColor)
                        .multilineTextAlignment(.center)

                    if let completions = wrap.highlightDayCompletions, completions > 0 {
                        HStack(spacing: 6) {
                            Image(systemName: "checkmark.circle.fill")
                            Text(String(format: String(localized: "weekly_wrap_highlight_completions"), completions))
                        }
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(secondaryTextColor)
                        .padding(.top, 8)
                    }
                } else {
                    Text(String(localized: "weekly_wrap_every_day_counts"))
                        .font(.title2.bold())
                        .foregroundStyle(textColor)
                        .multilineTextAlignment(.center)

                    Text(String(localized: "weekly_wrap_consistency_matters"))
                        .font(.body)
                        .foregroundStyle(secondaryTextColor)
                        .multilineTextAlignment(.center)
                }
            }
        }
    }

    private var highlightDayComment: String {
        if wrap.highlightDayReason == "perfect_day" {
            return String(localized: "weekly_wrap_highlight_perfect")
        } else {
            return String(localized: "weekly_wrap_highlight_best")
        }
    }

    // MARK: - Screen 4: Comparison (if available)

    private var comparisonScreen: some View {
        VStack(spacing: 32) {
            Text(comparisonEmoji)
                .font(.system(size: 72))

            VStack(spacing: 16) {
                if let improvement = wrap.improvementFromLastWeek {
                    HStack(alignment: .firstTextBaseline, spacing: 4) {
                        Image(systemName: improvement >= 0 ? "arrow.up.right" : "arrow.down.right")
                            .font(.title.weight(.bold))
                        Text(String(format: "%.0f%%", abs(improvement * 100)))
                            .font(.system(size: 56, weight: .bold))
                    }
                    .foregroundStyle(textColor)
                }

                Text(wrap.comparisonMessage)
                    .font(.title3)
                    .foregroundStyle(secondaryTextColor)
                    .multilineTextAlignment(.center)

                Text(String(localized: "weekly_wrap_vs_last_week"))
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(secondaryTextColor.opacity(0.7))
                    .padding(.top, 8)
            }
        }
    }

    private var comparisonEmoji: String {
        guard let improvement = wrap.improvementFromLastWeek else { return "📊" }
        if improvement >= 0.1 { return "🚀" }
        if improvement >= 0 { return "📈" }
        if improvement >= -0.1 { return "📉" }
        return "💭"
    }

    // MARK: - Screen 5: Time Tracked

    private var timeTrackedScreen: some View {
        VStack(spacing: 32) {
            Text("⏱️")
                .font(.system(size: 72))

            VStack(spacing: 16) {
                if wrap.totalMinutesTracked > 0 {
                    Text(wrap.formattedTimeTracked)
                        .font(.system(size: 56, weight: .bold))
                        .foregroundStyle(textColor)

                    Text(timeComment)
                        .font(.title3)
                        .foregroundStyle(secondaryTextColor)
                        .multilineTextAlignment(.center)
                } else {
                    Text(String(localized: "weekly_wrap_no_timer_habits"))
                        .font(.title2.bold())
                        .foregroundStyle(textColor)
                        .multilineTextAlignment(.center)

                    Text(String(localized: "weekly_wrap_quick_wins"))
                        .font(.body)
                        .foregroundStyle(secondaryTextColor)
                        .multilineTextAlignment(.center)
                }
            }
        }
    }

    private var timeComment: String {
        let hours = wrap.totalMinutesTracked / 60
        if hours >= 5 {
            return String(localized: "weekly_wrap_time_dedicated")
        } else if hours >= 2 {
            return String(localized: "weekly_wrap_time_solid")
        } else if wrap.totalMinutesTracked >= 30 {
            return String(localized: "weekly_wrap_time_building")
        } else {
            return String(localized: "weekly_wrap_time_every_minute")
        }
    }

    // MARK: - Screen 6: Top Habit

    private var topHabitScreen: some View {
        VStack(spacing: 32) {
            Text("🏆")
                .font(.system(size: 72))

            VStack(spacing: 16) {
                if let habitName = wrap.mostConsistentHabitName {
                    Text(habitName)
                        .font(.system(size: 32, weight: .bold))
                        .foregroundStyle(textColor)
                        .multilineTextAlignment(.center)

                    Text(String(localized: "weekly_wrap_top_habit_comment"))
                        .font(.title3)
                        .foregroundStyle(secondaryTextColor)
                        .multilineTextAlignment(.center)
                } else {
                    Text(String(localized: "weekly_wrap_all_habits_equal"))
                        .font(.title2.bold())
                        .foregroundStyle(textColor)
                        .multilineTextAlignment(.center)

                    Text(String(localized: "weekly_wrap_balanced_approach"))
                        .font(.body)
                        .foregroundStyle(secondaryTextColor)
                        .multilineTextAlignment(.center)
                }
            }
        }
    }

    // MARK: - Screen 7: Summary

    private var summaryScreen: some View {
        VStack(spacing: 32) {
            Spacer()

            Text(wrap.summaryEmoji)
                .font(.system(size: 72))

            VStack(spacing: 16) {
                Text(wrap.summaryMessage)
                    .font(.title.bold())
                    .foregroundStyle(textColor)
                    .multilineTextAlignment(.center)

                Text(String(localized: "weekly_wrap_new_week_ahead"))
                    .font(.body)
                    .foregroundStyle(secondaryTextColor)
                    .multilineTextAlignment(.center)
            }

            Spacer()

            // Action buttons
            VStack(spacing: 24) {
                HStack {
                    // Back button
                    Button {
                        withAnimation { currentPage -= 1 }
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "chevron.left")
                            Text(String(localized: "weekly_wrap_back"))
                        }
                        .font(.headline)
                        .foregroundStyle(secondaryTextColor)
                    }

                    Spacer()

                    // Close button
                    Button {
                        onDismiss()
                    } label: {
                        Text(String(localized: "weekly_wrap_close"))
                            .font(.headline)
                            .foregroundStyle(secondaryTextColor)
                    }
                }

                Button {
                    saveScreenshot()
                } label: {
                    HStack {
                        Image(systemName: "square.and.arrow.down")
                        Text(String(localized: "weekly_wrap_save"))
                    }
                    .font(.headline)
                    .foregroundStyle(isDarkAppearance ? .black : .white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(textColor)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                }
            }
            .padding(.bottom, 0)
        }
    }

    // MARK: - Save Functionality

    private func saveScreenshot() {
        #if canImport(UIKit)
        PHPhotoLibrary.requestAuthorization(for: .addOnly) { status in
            guard status == .authorized || status == .limited else {
                return
            }

            DispatchQueue.main.async {
                let summaryView = WrapSummaryCard(wrap: wrap, appTheme: appTheme, colorScheme: colorScheme)
                let renderer = ImageRenderer(content: summaryView)
                renderer.scale = 3.0

                if let image = renderer.uiImage {
                    PHPhotoLibrary.shared().performChanges {
                        PHAssetChangeRequest.creationRequestForAsset(from: image)
                    } completionHandler: { success, error in
                        DispatchQueue.main.async {
                            if success {
                                showingSaveConfirmation = true
                            }
                        }
                    }
                }
            }
        }
        #endif
    }
}

// MARK: - Summary Card for Saving (9:16 vertical)

struct WrapSummaryCard: View {
    let wrap: WeeklyWrap
    let appTheme: AppTheme
    let colorScheme: ColorScheme

    private var backgroundColor: Color {
        switch appTheme {
        case .dark:
            return .black
        case .dim:
            return Color(white: 0.1)
        case .light:
            return .white
        case .system:
            return colorScheme == .dark ? .black : .white
        }
    }

    private var isDarkAppearance: Bool {
        switch appTheme {
        case .dark, .dim:
            return true
        case .light:
            return false
        case .system:
            return colorScheme == .dark
        }
    }

    private var textColor: Color {
        isDarkAppearance ? .white : .black
    }

    private var secondaryTextColor: Color {
        isDarkAppearance ? .white.opacity(0.6) : .black.opacity(0.5)
    }

    var body: some View {
        VStack(spacing: 0) {
            Spacer()

            // Header
            VStack(spacing: 8) {
                Text("👀")
                    .font(.system(size: 36))

                Text(wrap.dateRangeString)
                    .font(.footnote.weight(.medium))
                    .foregroundStyle(secondaryTextColor)
            }

            Spacer()

            // Main stat
            VStack(spacing: 4) {
                Text("\(wrap.completionRatePercent)%")
                    .font(.system(size: 48, weight: .bold))
                    .foregroundStyle(textColor)

                Text(String(localized: "weekly_wrap_stat_rate"))
                    .font(.caption2)
                    .foregroundStyle(secondaryTextColor)
            }

            Spacer()

            // Stats row
            HStack(spacing: 24) {
                VStack(spacing: 2) {
                    Text("\(wrap.perfectDays)")
                        .font(.title3.bold())
                        .foregroundStyle(textColor)
                    Text(String(localized: "weekly_wrap_stat_perfect"))
                        .font(.caption2)
                        .foregroundStyle(secondaryTextColor)
                }

                VStack(spacing: 2) {
                    Text("\(wrap.totalCompletions)")
                        .font(.title3.bold())
                        .foregroundStyle(textColor)
                    Text(String(localized: "weekly_wrap_stat_completed"))
                        .font(.caption2)
                        .foregroundStyle(secondaryTextColor)
                }

                if wrap.totalMinutesTracked > 0 {
                    VStack(spacing: 2) {
                        Text(wrap.formattedTimeTracked)
                            .font(.title3.bold())
                            .foregroundStyle(textColor)
                        Text(String(localized: "weekly_wrap_stat_time"))
                            .font(.caption2)
                            .foregroundStyle(secondaryTextColor)
                    }
                }
            }

            Spacer()

            // Top habit
            if let habitName = wrap.mostConsistentHabitName {
                VStack(spacing: 4) {
                    Text("🏆")
                        .font(.body)
                    Text(habitName)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(textColor)
                    Text(String(localized: "weekly_wrap_most_consistent"))
                        .font(.caption2)
                        .foregroundStyle(secondaryTextColor)
                }
            }

            Spacer()

            // App branding
            Text("Habbit")
                .font(.caption2.weight(.medium))
                .foregroundStyle(secondaryTextColor.opacity(0.5))
                .padding(.bottom, 16)
        }
        .frame(width: 270, height: 480) // 9:16 vertical aspect ratio
        .background(backgroundColor)
    }
}

#Preview {
    WeeklyWrapStoryView(
        wrap: {
            let calendar = Calendar.current
            let today = Date()
            let lastMonday = calendar.date(byAdding: .day, value: -7, to: today)!
            let lastSunday = calendar.date(byAdding: .day, value: -1, to: today)!
            let wednesday = calendar.date(byAdding: .day, value: -5, to: today)!

            return WeeklyWrap(
                weekStartDate: lastMonday,
                weekEndDate: lastSunday,
                totalCompletions: 28,
                completionRate: 0.85,
                perfectDays: 4,
                bestStreak: 5,
                totalMinutesTracked: 225,
                mostConsistentHabitName: "Morning Run",
                improvementFromLastWeek: 0.12,
                totalHabitsTracked: 5,
                totalScheduledCompletions: 33,
                highlightDayDate: wednesday,
                highlightDayCompletions: 6,
                highlightDayReason: "perfect_day"
            )
        }(),
        onDismiss: {}
    )
}
