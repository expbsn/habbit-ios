//
//  OnboardingView.swift
//  Stick
//
//  Created by Kian Jain on 02.02.26.
//

import SwiftUI
import SwiftData
import RevenueCat

struct OnboardingView: View {
    @Environment(\.modelContext) private var modelContext
    @Query private var preferences: [UserPreferences]

    @State private var currentPage = 0
    @State private var notificationsRequested = false

    // Question answers
    @State private var statementAnswer: String?
    @State private var procrastinationAnswer: String?
    @State private var goalMeaningAnswer: String?
    @State private var holdingBackAnswer: String?
    @State private var whyHabitsAnswer: String?
    @State private var isWaving = false

    private let totalPages = 9

    // Progress bar only shows during question pages (1-5)
    private var questionProgress: Double {
        let questionPages = [1, 2, 3, 4, 5]
        guard let currentIndex = questionPages.firstIndex(of: currentPage) else { return 0 }
        return Double(currentIndex + 1) / Double(questionPages.count)
    }

    private var showProgressBar: Bool {
        (1...5).contains(currentPage)
    }

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        ZStack {
            // Background - consistent across all pages
            Color(.systemBackground)
                .ignoresSafeArea()

            if currentPage == 0 {
                // Welcome page rendered separately to allow safe area extension
                VStack(spacing: 0) {
                    welcomePage

                    navigationButtons
                        .padding(.horizontal, 24)
                        .padding(.bottom, 16)
                }
                .id(colorScheme) // Force re-render when color scheme changes
            } else {
                VStack(spacing: 0) {
                    // Progress bar (only during questions)
                    if showProgressBar {
                        progressBar
                            .padding(.horizontal, 24)
                            .padding(.top, 16)
                            .transition(.opacity)
                    }

                    // Page content
                    TabView(selection: $currentPage) {
                        statementPage.tag(1)
                        procrastinationPage.tag(2)
                        goalMeaningPage.tag(3)
                        holdingBackPage.tag(4)
                        whyHabitsPage.tag(5)
                        goodJobPage.tag(6)
                        notificationPage.tag(7)
                        paywallPage.tag(8)
                    }
                    .tabViewStyle(.page(indexDisplayMode: .never))
                    .animation(.easeInOut(duration: 0.3), value: currentPage)

                    // Navigation buttons (hidden on paywall)
                    if currentPage != 8 {
                        navigationButtons
                            .padding(.horizontal, 24)
                            .padding(.bottom, 16)
                    }
                }
            }
        }
        .animation(.easeInOut(duration: 0.3), value: currentPage == 0)
        .onAppear {
            AnalyticsService.shared.trackOnboardingStarted()
        }
        .onChange(of: currentPage) { oldPage, newPage in
            // Track step completion when moving forward
            if newPage > oldPage {
                AnalyticsService.shared.trackOnboardingStepCompleted(
                    step: oldPage,
                    stepName: stepName(for: oldPage)
                )
            }

            // Track paywall viewed
            if newPage == 8 {
                AnalyticsService.shared.trackPaywallViewed(source: "onboarding")
            }
        }
    }

    private func stepName(for page: Int) -> String {
        switch page {
        case 0: return "welcome"
        case 1: return "statement_question"
        case 2: return "procrastination_question"
        case 3: return "goal_meaning_question"
        case 4: return "holding_back_question"
        case 5: return "why_habits_question"
        case 6: return "good_job"
        case 7: return "notifications"
        case 8: return "paywall"
        default: return "unknown"
        }
    }

    // MARK: - Progress Bar

    private var progressBar: some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                // Background track
                Capsule()
                    .fill(Color.gray.opacity(0.2))
                    .frame(height: 6)

                // Progress fill
                Capsule()
                    .fill(Color.primary)
                    .frame(width: geometry.size.width * questionProgress, height: 6)
                    .animation(.spring(duration: 0.4), value: questionProgress)
            }
        }
        .frame(height: 6)
    }

    // MARK: - Page 0: Welcome

    private var welcomePage: some View {
        VStack(spacing: 0) {
            // Top section: Animated carousels with waving hand overlay
            ZStack {
                // Animated habit carousels
                HabitCarouselsBackground()

                // Gradient overlays for fade effect
                VStack {
                    // Top fade
                    LinearGradient(
                        colors: [
                            Color(.systemBackground),
                            Color(.systemBackground).opacity(0)
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                    .frame(height: 80)

                    Spacer()

                    // Bottom fade
                    LinearGradient(
                        colors: [
                            Color(.systemBackground).opacity(0),
                            Color(.systemBackground)
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                    .frame(height: 120)
                }

                // Waving hand centered (offset down)
                WavingHandView(isWaving: $isWaving)
                    .offset(y: 60)
            }
            .frame(height: 420)
            .clipped()

            // Title and subtitle
            VStack(spacing: 12) {
                Text(String(localized: "welcome_title"))
                    .font(.largeTitle.bold())

                Text(String(localized: "welcome_subtitle"))
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            .padding(.horizontal, 32)
            .padding(.top, 8)

            // Key features
            VStack(spacing: 20) {
                WelcomeFeatureRow(
                    icon: "arrow.up.forward",
                    text: String(localized: "welcome_feature_1")
                )
                WelcomeFeatureRow(
                    icon: "square.stack.3d.up.fill",
                    text: String(localized: "welcome_feature_2")
                )
                WelcomeFeatureRow(
                    icon: "calendar.badge.checkmark",
                    text: String(localized: "welcome_feature_3")
                )
            }
            .padding(.horizontal, 40)
            .padding(.top, 32)

            Spacer()
        }
        .ignoresSafeArea(edges: .top)
        .onAppear {
            startWaveLoop()
        }
    }

    private func startWaveLoop() {
        guard currentPage == 0 else { return }

        // Start waving after a short delay
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            withAnimation(.easeInOut(duration: 0.4)) {
                isWaving = true
            }
        }

        // Stop waving after the animation plays
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.8) {
            withAnimation(.easeInOut(duration: 0.4)) {
                isWaving = false
            }
        }

        // Repeat the loop
        DispatchQueue.main.asyncAfter(deadline: .now() + 5.0) {
            if currentPage == 0 {
                startWaveLoop()
            }
        }
    }

    // MARK: - Page 1: Statement Question

    private var statementPage: some View {
        QuestionPage(
            question: String(localized: "question1_title"),
            subtitle: String(localized: "question1_subtitle"),
            options: [
                String(localized: "question1_option1"),
                String(localized: "question1_option2"),
                String(localized: "question1_option3"),
                String(localized: "question1_option4"),
                String(localized: "question1_option5"),
                String(localized: "question1_option6")
            ],
            selectedOption: $statementAnswer
        )
    }

    // MARK: - Page 2: Procrastination Question

    private var procrastinationPage: some View {
        QuestionPage(
            question: String(localized: "question2_title"),
            subtitle: String(localized: "question2_subtitle"),
            options: [
                String(localized: "question2_option1"),
                String(localized: "question2_option2"),
                String(localized: "question2_option3")
            ],
            selectedOption: $procrastinationAnswer
        )
    }

    // MARK: - Page 3: Goal Meaning Question

    private var goalMeaningPage: some View {
        QuestionPage(
            question: String(localized: "question3_title"),
            subtitle: String(localized: "question3_subtitle"),
            options: [
                String(localized: "question3_option1"),
                String(localized: "question3_option2"),
                String(localized: "question3_option3")
            ],
            selectedOption: $goalMeaningAnswer
        )
    }

    // MARK: - Page 4: Holding Back Question

    private var holdingBackPage: some View {
        QuestionPage(
            question: String(localized: "question4_title"),
            subtitle: String(localized: "question4_subtitle"),
            options: [
                String(localized: "question4_option1"),
                String(localized: "question4_option2"),
                String(localized: "question4_option3"),
                String(localized: "question4_option4")
            ],
            selectedOption: $holdingBackAnswer
        )
    }

    // MARK: - Page 5: Why Habits Question

    private var whyHabitsPage: some View {
        QuestionPage(
            question: String(localized: "question5_title"),
            subtitle: String(localized: "question5_subtitle"),
            options: [
                String(localized: "question5_option1"),
                String(localized: "question5_option2"),
                String(localized: "question5_option3"),
                String(localized: "question5_option4")
            ],
            selectedOption: $whyHabitsAnswer
        )
    }

    // MARK: - Page 6: Good Job

    private var goodJobPage: some View {
        VStack(spacing: 16) {
            Spacer()

            Text(String(localized: "goodjob_title"))
                .font(.largeTitle.bold())

            Text(String(localized: "goodjob_subtitle"))
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)

            Spacer()
            Spacer()
        }
    }

    // MARK: - Page 7: Notifications

    private var notificationPage: some View {
        VStack(spacing: 32) {
            Spacer()

            ZStack {
                Circle()
                    .fill(Color.primary.opacity(0.15))
                    .frame(width: 120, height: 120)

                Image(systemName: "bell.badge.fill")
                    .font(.system(size: 50))
                    .foregroundStyle(Color.primary)
            }

            VStack(spacing: 16) {
                Text(String(localized: "notifications_title"))
                    .font(.title2.bold())

                Text(String(localized: "notifications_subtitle"))
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)

                // Smart reminders info card
                HStack(alignment: .top, spacing: 12) {
                    Image(systemName: "sparkles")
                        .font(.body.weight(.semibold))
                        .foregroundStyle(.primary)
                        .frame(width: 20)

                    Text(String(localized: "notifications_smart_reminders_hint"))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.leading)
                }
                .padding(14)
                .background(Color.primary.opacity(0.06))
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .padding(.horizontal, 32)
                .padding(.top, 4)
            }

            if !notificationsRequested {
                VStack(spacing: 12) {
                    Button {
                        requestNotifications()
                    } label: {
                        Label(String(localized: "notifications_enable"), systemImage: "bell.fill")
                            .font(.headline)
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(Color.primary)
                            .foregroundStyle(Color(.systemBackground))
                            .clipShape(RoundedRectangle(cornerRadius: 14))
                    }

                    Button(String(localized: "notifications_later")) {
                        AnalyticsService.shared.trackNotificationSkipped()
                        notificationsRequested = true
                    }
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .padding(.top, 8)
                }
                .padding(.horizontal, 48)
            } else {
                Text(NotificationManager.shared.isAuthorized ? String(localized: "notifications_success") : String(localized: "notifications_settings_hint"))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            Spacer()
            Spacer()
        }
    }

    // MARK: - Page 8: Paywall

    @State private var selectedPlan: PaywallPlan = .yearly
    @ObservedObject private var subscriptionService = SubscriptionService.shared
    @State private var showPaywallError = false

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

    private var paywallPage: some View {
        VStack(spacing: 0) {
            // Close button - top right
            HStack {
                Spacer()
                Button {
                    AnalyticsService.shared.trackPaywallDismissed(source: "onboarding")
                    completeOnboarding()
                } label: {
                    Image(systemName: "xmark")
                        .font(.body.weight(.medium))
                        .foregroundStyle(.secondary)
                        .frame(width: 32, height: 32)
                        .background(Color.primary.opacity(0.1))
                        .clipShape(Circle())
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 16)

            // Header
            VStack(spacing: 8) {
                Text(String(localized: "paywall_title"))
                    .font(.largeTitle.bold())
                    .foregroundStyle(.primary)
                    .multilineTextAlignment(.center)

                Text(String(localized: "paywall_subtitle"))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .padding(.top, 20)

            // Timeline
            VStack(alignment: .leading, spacing: 0) {
                TimelineRow(
                    step: "1",
                    title: String(localized: "paywall_timeline1_title"),
                    subtitle: String(localized: "paywall_timeline1_subtitle"),
                    isLast: false,
                    colorScheme: colorScheme
                )
                TimelineRow(
                    step: "2",
                    title: String(localized: "paywall_timeline2_title"),
                    subtitle: String(localized: "paywall_timeline2_subtitle"),
                    isLast: false,
                    colorScheme: colorScheme
                )
                TimelineRow(
                    step: "3",
                    title: String(localized: "paywall_timeline3_title"),
                    subtitle: String(localized: "paywall_timeline3_subtitle"),
                    isLast: true,
                    colorScheme: colorScheme
                )
            }
            .padding(.horizontal, 32)
            .padding(.top, 32)

            Spacer()

            // Plan selection cards
            HStack(spacing: 12) {
                PlanCard(
                    plan: .yearly,
                    isSelected: selectedPlan == .yearly,
                    badge: String(localized: "paywall_badge_save"),
                    colorScheme: colorScheme,
                    package: subscriptionService.annualPackage
                ) {
                    selectedPlan = .yearly
                }

                PlanCard(
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
                            completeOnboarding()
                        }
                    }
                }
            }
            .font(.caption)
            .foregroundStyle(.secondary)
            .padding(.top, 8)
            .padding(.bottom, 24)
        }
        .onAppear {
            Task {
                await subscriptionService.fetchOfferings()
            }
        }
        .alert(String(localized: "paywall_error_title"), isPresented: $showPaywallError) {
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
            showPaywallError = true
            return
        }

        let success = await subscriptionService.purchase(package)
        if success {
            AnalyticsService.shared.trackTrialStarted(plan: planName)
            completeOnboarding()
        } else {
            AnalyticsService.shared.trackPurchaseFailed(reason: "purchase_cancelled_or_failed")
        }
    }

    // MARK: - Navigation Buttons

    private var navigationButtons: some View {
        HStack {
            // Back button (hidden on welcome, motivational pages, and paywall)
            if currentPage > 0 && currentPage <= 5 {
                Button {
                    withAnimation { currentPage -= 1 }
                } label: {
                    Image(systemName: "chevron.left")
                        .font(.headline)
                        .foregroundStyle(Color.primary)
                        .frame(width: 50, height: 50)
                        .background(Color.gray.opacity(0.15))
                        .clipShape(Circle())
                }
            } else {
                Spacer().frame(width: 50)
            }

            Spacer()

            // Next button
            Button {
                withAnimation { currentPage += 1 }
            } label: {
                HStack(spacing: 8) {
                    Text(buttonTitle)
                        .font(.headline)

                    if currentPage < totalPages - 1 && currentPage != 7 {
                        Image(systemName: "chevron.right")
                    }
                }
                .frame(height: 50)
                .padding(.horizontal, 32)
                .background(canProceed ? Color.primary : Color.gray.opacity(0.3))
                .foregroundStyle(Color(.systemBackground))
                .clipShape(Capsule())
            }
            .disabled(!canProceed)
        }
    }

    private var buttonTitle: String {
        switch currentPage {
        case 0: return String(localized: "nav_lets_go")
        case 6: return String(localized: "nav_lets_do_it")
        case 7: return String(localized: "nav_almost_there")
        default: return String(localized: "nav_continue")
        }
    }

    private var canProceed: Bool {
        switch currentPage {
        case 1: return statementAnswer != nil
        case 2: return procrastinationAnswer != nil
        case 3: return goalMeaningAnswer != nil
        case 4: return holdingBackAnswer != nil
        case 5: return whyHabitsAnswer != nil
        default: return true
        }
    }

    // MARK: - Actions

    private func requestNotifications() {
        AnalyticsService.shared.trackNotificationPermissionRequested()

        Task {
            let granted = await NotificationManager.shared.requestAuthorization()
            await MainActor.run {
                notificationsRequested = true
                if granted {
                    AnalyticsService.shared.trackNotificationPermissionGranted()
                } else {
                    AnalyticsService.shared.trackNotificationPermissionDenied()
                }
            }
        }
    }

    private func completeOnboarding() {
        AnalyticsService.shared.trackOnboardingCompleted()

        let prefs = preferences.first ?? UserPreferences.createDefault()

        if preferences.isEmpty {
            modelContext.insert(prefs)
        }

        prefs.hasCompletedOnboarding = true
        prefs.notificationsEnabled = NotificationManager.shared.isAuthorized

        // Save all question answers
        if let answer = statementAnswer {
            prefs.setAnswer(answer, for: .statement)
        }
        if let answer = procrastinationAnswer {
            prefs.setAnswer(answer, for: .procrastination)
        }
        if let answer = goalMeaningAnswer {
            prefs.setAnswer(answer, for: .goalMeaning)
        }
        if let answer = holdingBackAnswer {
            prefs.setAnswer(answer, for: .holdingBack)
        }
        if let answer = whyHabitsAnswer {
            prefs.setAnswer(answer, for: .whyHabits)
        }

        do {
            try modelContext.save()
        } catch {
            print("Failed to save onboarding: \(error)")
        }
    }
}

// MARK: - Question Page

struct QuestionPage: View {
    let question: String
    var subtitle: String? = nil
    let options: [String]
    @Binding var selectedOption: String?

    var body: some View {
        VStack(spacing: 24) {
            Spacer()

            VStack(spacing: 12) {
                Text(question)
                    .font(.title3.bold())
                    .multilineTextAlignment(.center)

                if let subtitle = subtitle {
                    Text(subtitle)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
            }
            .padding(.horizontal, 24)

            VStack(spacing: 10) {
                ForEach(options, id: \.self) { option in
                    OptionButton(
                        title: option,
                        isSelected: selectedOption == option
                    ) {
                        withAnimation(.spring(duration: 0.3)) {
                            selectedOption = option
                        }
                    }
                }
            }
            .padding(.horizontal, 24)

            Spacer()
            Spacer()
        }
    }
}

// MARK: - Option Button

struct OptionButton: View {
    let title: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack {
                Text(title)
                    .font(.body)
                    .multilineTextAlignment(.leading)

                Spacer()

                ZStack {
                    Circle()
                        .stroke(isSelected ? Color.primary : Color.gray.opacity(0.3), lineWidth: 2)
                        .frame(width: 22, height: 22)

                    if isSelected {
                        Circle()
                            .fill(Color.primary)
                            .frame(width: 12, height: 12)
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .background(isSelected ? Color.primary.opacity(0.1) : Color.gray.opacity(0.06))
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(isSelected ? Color.primary : Color.clear, lineWidth: 2)
            )
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Waving Hand View

struct WavingHandView: View {
    @Binding var isWaving: Bool
    @Environment(\.colorScheme) private var colorScheme

    private var glowColor: Color {
        Color(.systemBackground)
    }

    var body: some View {
        ZStack {
            // Background glow
            Circle()
                .fill(glowColor)
                .frame(width: 250, height: 250)
                .blur(radius: 60)

            // Hand emoji
            Text("👋")
                .font(.system(size: 100))
                // Offset the emoji so its bottom-right (wrist area) is at the center
                .offset(x: -30, y: -40)
                // Rotate around the center of the container (now aligned with wrist)
                .rotationEffect(.degrees(isWaving ? 12 : 0))
                // Move back to visual center
                .offset(x: 30, y: 40)
        }
    }
}

// MARK: - Animated Habit Carousels Background

struct HabitCarouselsBackground: View {
    // Sample habits data - using emojis like in the app
    private let rows: [[OnboardingHabit]] = [
        [
            OnboardingHabit(name: "Piano", emoji: "🎹", color: "#FF6B6B", subtitle: "1h"),
            OnboardingHabit(name: "Coding", emoji: "💻", color: "#4ECDC4", subtitle: "1h"),
            OnboardingHabit(name: "Running", emoji: "🏃", color: "#FFE66D", subtitle: "20m"),
            OnboardingHabit(name: "Writing", emoji: "✍️", color: "#95E1D3", subtitle: "30m"),
            OnboardingHabit(name: "Gym", emoji: "🏋️", color: "#F38181", subtitle: "20m"),
        ],
        [
            OnboardingHabit(name: "Violin", emoji: "🎻", color: "#AA96DA", subtitle: "1h"),
            OnboardingHabit(name: "Meditation", emoji: "🧘", color: "#FCBAD3", subtitle: "0/3 this..."),
            OnboardingHabit(name: "Basketball", emoji: "🏀", color: "#FF9F43", subtitle: "0/5 this..."),
            OnboardingHabit(name: "Running", emoji: "🏃", color: "#FFE66D", subtitle: "0/1 this..."),
            OnboardingHabit(name: "Coding", emoji: "💻", color: "#4ECDC4", subtitle: "20m"),
        ],
        [
            OnboardingHabit(name: "Japanese", emoji: "🇯🇵", color: "#FF6B6B", subtitle: "0/4 this..."),
            OnboardingHabit(name: "Violin", emoji: "🎻", color: "#AA96DA", subtitle: "20m"),
            OnboardingHabit(name: "Meditation", emoji: "🧘", color: "#FCBAD3", subtitle: "1h"),
            OnboardingHabit(name: "Showers", emoji: "🚿", color: "#74B9FF", subtitle: "0/3 this..."),
            OnboardingHabit(name: "Coding", emoji: "💻", color: "#4ECDC4", subtitle: "5m"),
        ],
        [
            OnboardingHabit(name: "Spanish", emoji: "🇪🇸", color: "#FD79A8", subtitle: "0/4 this..."),
            OnboardingHabit(name: "Writing", emoji: "✍️", color: "#95E1D3", subtitle: "15m"),
            OnboardingHabit(name: "Meditation", emoji: "🧘", color: "#FCBAD3", subtitle: "0/3 this..."),
            OnboardingHabit(name: "Drawing", emoji: "🎨", color: "#A29BFE", subtitle: "0/4 this..."),
            OnboardingHabit(name: "Gym", emoji: "🏋️", color: "#F38181", subtitle: "30m"),
        ],
        [
            OnboardingHabit(name: "Piano", emoji: "🎹", color: "#FF6B6B", subtitle: "1h"),
            OnboardingHabit(name: "Running", emoji: "🏃", color: "#FFE66D", subtitle: "0/1 this..."),
            OnboardingHabit(name: "Basketball", emoji: "🏀", color: "#FF9F43", subtitle: "0/2 this..."),
            OnboardingHabit(name: "Writing", emoji: "✍️", color: "#95E1D3", subtitle: "6m"),
            OnboardingHabit(name: "Coding", emoji: "💻", color: "#4ECDC4", subtitle: "1h"),
        ],
        [
            OnboardingHabit(name: "Meditation", emoji: "🧘", color: "#FCBAD3", subtitle: "5m"),
            OnboardingHabit(name: "Violin", emoji: "🎻", color: "#AA96DA", subtitle: "0/2 this..."),
            OnboardingHabit(name: "Japanese", emoji: "🇯🇵", color: "#FF6B6B", subtitle: "30m"),
            OnboardingHabit(name: "Drawing", emoji: "🎨", color: "#A29BFE", subtitle: "1h"),
            OnboardingHabit(name: "Running", emoji: "🏃", color: "#FFE66D", subtitle: "15m"),
        ],
        [
            OnboardingHabit(name: "Reading", emoji: "📚", color: "#6C5CE7", subtitle: "45m"),
            OnboardingHabit(name: "Cooking", emoji: "👨‍🍳", color: "#FDCB6E", subtitle: "0/3 this..."),
            OnboardingHabit(name: "Stretching", emoji: "🤸", color: "#00CEC9", subtitle: "10m"),
            OnboardingHabit(name: "Guitar", emoji: "🎸", color: "#E17055", subtitle: "30m"),
            OnboardingHabit(name: "Walking", emoji: "🚶", color: "#81ECEC", subtitle: "20m"),
        ],
        [
            OnboardingHabit(name: "Journaling", emoji: "📝", color: "#74B9FF", subtitle: "15m"),
            OnboardingHabit(name: "Yoga", emoji: "🧘‍♀️", color: "#A29BFE", subtitle: "20m"),
            OnboardingHabit(name: "Swimming", emoji: "🏊", color: "#0984E3", subtitle: "0/2 this..."),
            OnboardingHabit(name: "Piano", emoji: "🎹", color: "#FF6B6B", subtitle: "45m"),
            OnboardingHabit(name: "Study", emoji: "📖", color: "#FFEAA7", subtitle: "1h"),
        ],
    ]

    var body: some View {
        GeometryReader { geo in
            VStack(spacing: 6) {
                ForEach(0..<rows.count, id: \.self) { index in
                    OnboardingCarouselRow(
                        habits: rows[index],
                        reverseDirection: index % 2 == 1,
                        speed: 90.0 + Double(index) * 3.0,
                        rowOffset: CGFloat(index % 3) * -60 // Stagger offset
                    )
                }
            }
            .rotationEffect(.degrees(-15), anchor: .center)
            .scaleEffect(1.5)
            .offset(x: 40, y: -120)
            .opacity(0.5)
        }
    }
}

// MARK: - Onboarding Habit Model

struct OnboardingHabit: Identifiable {
    let id = UUID()
    let name: String
    let emoji: String
    let color: String
    let subtitle: String
}

// MARK: - Carousel Row

struct OnboardingCarouselRow: View {
    let habits: [OnboardingHabit]
    let reverseDirection: Bool
    let speed: Double
    let rowOffset: CGFloat

    @State private var animationOffset: CGFloat = 0
    @State private var rotationAngle: Double = 0
    private let cardWidth: CGFloat = 140
    private let cardSpacing: CGFloat = 8

    private var singleSetWidth: CGFloat {
        CGFloat(habits.count) * (cardWidth + cardSpacing)
    }

    var body: some View {
        HStack(spacing: cardSpacing) {
            // Triple the cards for seamless looping
            ForEach(0..<3, id: \.self) { _ in
                ForEach(habits) { habit in
                    OnboardingHabitCard(habit: habit)
                        .frame(width: cardWidth)
                }
            }
        }
        .rotation3DEffect(
            .degrees(rotationAngle),
            axis: (x: 1, y: 0, z: 0),
            perspective: 0.5
        )
        .offset(x: animationOffset + rowOffset)
        .onAppear {
            startAnimation()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                startRotation()
            }
        }
    }

    private func startAnimation() {
        // Set initial position
        animationOffset = reverseDirection ? -singleSetWidth : 0

        // Animate continuously
        withAnimation(.linear(duration: speed).repeatForever(autoreverses: false)) {
            animationOffset = reverseDirection ? 0 : -singleSetWidth
        }
    }

    private func startRotation() {
        let targetAngle: Double = reverseDirection ? 4 : -4
        withAnimation(.easeInOut(duration: 25).repeatForever(autoreverses: true)) {
            rotationAngle = targetAngle
        }
    }
}

// MARK: - Habit Card (matches app style)

struct OnboardingHabitCard: View {
    let habit: OnboardingHabit

    private var isTimeBased: Bool {
        habit.subtitle.contains("m") || habit.subtitle.contains("h")
    }

    var body: some View {
        HStack(spacing: 8) {
            // Emoji icon with colored background
            Text(habit.emoji)
                .font(.body)
                .frame(width: 32, height: 32)
                .background(Color(hex: habit.color).opacity(0.2))
                .clipShape(RoundedRectangle(cornerRadius: 8))

            // Name and subtitle
            VStack(alignment: .leading, spacing: 2) {
                Text(habit.name)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.primary)
                    .lineLimit(1)

                HStack(spacing: 3) {
                    Image(systemName: "clock")
                        .font(.system(size: 9))
                    Text(habit.subtitle)
                        .font(.system(size: 10))
                }
                .foregroundStyle(.secondary)
            }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(Color(.secondarySystemBackground).opacity(0.95))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}

// MARK: - Welcome Feature Row

struct WelcomeFeatureRow: View {
    let icon: String
    let text: String

    var body: some View {
        HStack(spacing: 16) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundStyle(Color.primary)
                .frame(width: 28)

            Text(text)
                .font(.body)
                .foregroundStyle(.primary)

            Spacer()
        }
    }
}

// MARK: - Pro Feature Row

struct ProFeatureRow: View {
    let icon: String
    let title: String

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: "checkmark")
                .font(.caption.bold())
                .foregroundStyle(.white)
                .frame(width: 22, height: 22)
                .background(Color.primary)
                .clipShape(Circle())

            Text(title)
                .font(.body)

            Spacer()
        }
    }
}

// MARK: - Paywall Plan

enum PaywallPlan {
    case monthly
    case yearly

    var title: String {
        switch self {
        case .monthly: return String(localized: "paywall_plan_monthly")
        case .yearly: return String(localized: "paywall_plan_yearly")
        }
    }

    var price: String {
        switch self {
        case .monthly: return "$4.99/mo"
        case .yearly: return "$24.99/yr"
        }
    }

    var icon: String {
        switch self {
        case .monthly: return "sparkles"
        case .yearly: return "crown.fill"
        }
    }

    var renewalLabel: String {
        switch self {
        case .monthly: return String(localized: "paywall_billed_monthly")
        case .yearly: return String(localized: "paywall_billed_annually")
        }
    }

    var renewalPeriodKey: String {
        switch self {
        case .monthly: return String(localized: "paywall_per_month")
        case .yearly: return String(localized: "paywall_per_year")
        }
    }
}

// MARK: - Timeline Row

struct TimelineRow: View {
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

// MARK: - Plan Card

struct PlanCard: View {
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

// MARK: - Preview

#Preview {
    OnboardingView()
        .modelContainer(.preview)
}
