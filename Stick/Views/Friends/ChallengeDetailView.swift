//
//  ChallengeDetailView.swift
//  Stick
//
//  Detail view showing challenge progress for both participants.
//

import SwiftUI
import SwiftData

struct ChallengeDetailView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Environment(\.colorScheme) private var colorScheme
    @Query private var preferences: [UserPreferences]
    @Query private var myProfile: [MyCloudProfile]

    @StateObject private var cloudKitService = CloudKitService.shared
    @StateObject private var challengeSyncService = ChallengeSyncService.shared

    @Query(filter: #Predicate<Habit> { $0.isActive }) private var activeHabits: [Habit]

    let challenge: SharedChallenge

    @State private var isMarkingComplete = false
    @State private var isTodayCompleted = false
    @State private var friendCompletionDates: [Date] = []
    @State private var showingRemoveConfirmation = false
    @State private var todayHealthKitValue: Double = 0
    @State private var friendHKValue: Double? = nil

    private var accentColor: Color {
        let colorValue = preferences.first?.appAccentColor ?? UserPreferences.adaptiveAccentColor
        if colorValue == UserPreferences.adaptiveAccentColor {
            return Color.primary
        }
        return Color(hex: colorValue)
    }

    private var buttonBackground: Color {
        let colorValue = preferences.first?.appAccentColor ?? UserPreferences.adaptiveAccentColor
        if colorValue == UserPreferences.adaptiveAccentColor {
            return colorScheme == .dark ? Color(.systemGray2) : Color(.label)
        }
        return Color(hex: colorValue)
    }

    private var buttonForegroundColor: Color {
        let colorValue = preferences.first?.appAccentColor ?? UserPreferences.adaptiveAccentColor
        if colorValue == UserPreferences.adaptiveAccentColor {
            return colorScheme == .dark ? .white : Color(.systemBackground)
        }
        return .white
    }

    private var currentUserID: String {
        cloudKitService.currentUserID ?? ""
    }

    private var friendName: String {
        challenge.friendDisplayName(for: currentUserID)
    }

    private var friendEmoji: String {
        challenge.friendAvatarEmoji(for: currentUserID)
    }

    private var myAvatarEmoji: String {
        myProfile.first?.avatarEmoji ?? "🙂"
    }

    private var habitColor: Color {
        Color(hex: challenge.habitColor)
    }

    /// True when the challenge is HealthKit-based but the user has no active habit linked to that type.
    private var isMissingHealthKitLink: Bool {
        guard let hkType = challenge.healthKitType, !hkType.isEmpty else { return false }
        return !activeHabits.contains { $0.healthKitType == hkType }
    }

    /// Today's HealthKit fraction (0–1) for the current user.
    private var myHKFraction: Double? {
        guard let hkTypeString = challenge.healthKitType,
              let hkType = HealthKitDataType(rawValue: hkTypeString) else { return nil }
        let target = challenge.healthKitTarget ?? hkType.defaultTarget
        guard target > 0 else { return nil }
        return min(1.0, todayHealthKitValue / target)
    }

    /// Today's HealthKit fraction for the friend — uses their uploaded snapshot.
    /// Falls back to binary (1.0/0.0) if no snapshot available yet.
    private var friendHKFraction: Double? {
        guard let hkTypeString = challenge.healthKitType,
              let hkType = HealthKitDataType(rawValue: hkTypeString) else { return nil }
        if let value = friendHKValue {
            let target = challenge.healthKitTarget ?? hkType.defaultTarget
            guard target > 0 else { return nil }
            return min(1.0, value / target)
        }
        // No snapshot yet — fall back to binary completion status
        return isFriendCompletedToday() ? 1.0 : 0.0
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    headerSection

                    todayCirclesSection

                    if isMissingHealthKitLink {
                        missingHealthKitLinkBanner
                    }

                    if challenge.healthKitType != nil {
                        healthKitProgressSection
                    }

                    overallStatsSection

                    if challenge.canMarkTodayComplete && !isTodayCompleted && challenge.healthKitType == nil {
                        markCompleteButton
                    }
                }
                .padding()
            }
            .dimThemeScrollBackground()
            .navigationTitle(challenge.habitName)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(String(localized: "timer_done")) {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        showingRemoveConfirmation = true
                    } label: {
                        Image(systemName: "trash")
                            .foregroundStyle(.red)
                    }
                }
            }
            .alert(
                String(localized: "challenges_remove_confirm_title"),
                isPresented: $showingRemoveConfirmation
            ) {
                Button(String(localized: "challenges_remove"), role: .destructive) {
                    Task {
                        await challengeSyncService.removeChallenge(challenge, context: modelContext)
                        dismiss()
                    }
                }
                Button(String(localized: "settings_cancel"), role: .cancel) {}
            } message: {
                Text(String(localized: "challenges_remove_confirm_message"))
            }
            .onAppear {
                loadCompletionData()
                Task { await loadHealthKitProgress() }
            }
            .onChange(of: challenge.friendCompletedDays) {
                loadCompletionData()
            }
            .onChange(of: challenge.myCompletedDays) {
                loadCompletionData()
            }
            .onReceive(NotificationCenter.default.publisher(for: .cloudKitDataChanged)) { notification in
                let subscriptionID = notification.userInfo?["subscriptionID"] as? String ?? ""
                guard subscriptionID.contains("challenge-") || subscriptionID.isEmpty else { return }
                Task {
                    await challengeSyncService.syncChallengesNow(context: modelContext)
                    loadCompletionData()
                }
            }
        }
    }

    // MARK: - Header

    private var headerSection: some View {
        VStack(spacing: 16) {
            Text(challenge.habitEmoji)
                .font(.system(size: 60))

            VStack(spacing: 8) {
                Text(challenge.progressDisplay)
                    .font(.headline)

                GeometryReader { geometry in
                    ZStack(alignment: .leading) {
                        Capsule()
                            .fill(Color(.systemGray5))
                            .frame(height: 8)
                        Capsule()
                            .fill(habitColor)
                            .frame(width: geometry.size.width * challenge.durationProgress, height: 8)
                    }
                }
                .frame(height: 8)

                Text("\(Int(challenge.durationProgress * 100))%")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal)
        }
        .padding(.bottom, 4)
    }

    // MARK: - Today's Circles

    private var todayCirclesSection: some View {
        HStack(spacing: 0) {
            personCircle(
                emoji: myAvatarEmoji,
                name: String(localized: "friends_you"),
                isCompleted: isTodayCompleted,
                hkFraction: myHKFraction,
                color: accentColor
            )

            Divider()
                .frame(height: 80)

            personCircle(
                emoji: friendEmoji.isEmpty ? "🙂" : friendEmoji,
                name: friendName,
                isCompleted: isFriendCompletedToday(),
                hkFraction: friendHKFraction,
                color: habitColor
            )
        }
        .padding(.vertical, 20)
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }

    @ViewBuilder
    private func personCircle(
        emoji: String,
        name: String,
        isCompleted: Bool,
        hkFraction: Double?,
        color: Color
    ) -> some View {
        VStack(spacing: 10) {
            ZStack {
                // Track ring
                Circle()
                    .stroke(Color(.systemGray5), lineWidth: 5)
                    .frame(width: 88, height: 88)

                if let fraction = hkFraction {
                    // HK partial progress arc
                    Circle()
                        .trim(from: 0, to: fraction)
                        .stroke(
                            fraction >= 1.0 ? Color.green : color,
                            style: StrokeStyle(lineWidth: 5, lineCap: .round)
                        )
                        .rotationEffect(.degrees(-90))
                        .frame(width: 88, height: 88)
                        .animation(.easeOut(duration: 0.4), value: fraction)
                } else if isCompleted {
                    // Full ring when done
                    Circle()
                        .stroke(color, lineWidth: 5)
                        .frame(width: 88, height: 88)
                    Circle()
                        .fill(color.opacity(0.12))
                        .frame(width: 78, height: 78)
                }

                Text(emoji)
                    .font(.system(size: 34))
            }

            Text(name)
                .font(.subheadline.weight(.medium))
                .lineLimit(1)

            if let fraction = hkFraction {
                Text("\(Int(fraction * 100))%")
                    .font(.caption)
                    .foregroundStyle(fraction >= 1.0 ? .green : .secondary)
            } else {
                Text(isCompleted
                     ? String(localized: "challenges_completed")
                     : String(localized: "challenges_not_done"))
                    .font(.caption)
                    .foregroundStyle(isCompleted ? .green : .secondary)
            }
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Missing HealthKit Link Banner

    private var missingHealthKitLinkBanner: some View {
        let hkTypeName: String = {
            guard let raw = challenge.healthKitType,
                  let type = HealthKitDataType(rawValue: raw) else { return "Apple Health" }
            return type.localizedName
        }()

        return HStack(alignment: .top, spacing: 12) {
            Image(systemName: "heart.text.square.fill")
                .font(.title3)
                .foregroundStyle(.red)

            VStack(alignment: .leading, spacing: 4) {
                Text(String(localized: "challenges_hk_missing_title"))
                    .font(.subheadline.weight(.semibold))

                Text(String(format: String(localized: "challenges_hk_missing_body"), hkTypeName))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.red.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(Color.red.opacity(0.2), lineWidth: 1)
        )
    }

    // MARK: - Apple Health Progress

    @ViewBuilder
    private var healthKitProgressSection: some View {
        if let hkTypeString = challenge.healthKitType,
           let hkType = HealthKitDataType(rawValue: hkTypeString) {
            let target = challenge.healthKitTarget ?? hkType.defaultTarget
            let fraction = target > 0 ? min(1.0, todayHealthKitValue / target) : 0
            let isHit = todayHealthKitValue >= target

            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Image(systemName: hkType.systemImage)
                        .foregroundStyle(.red)
                    Text("Apple Health · Today")
                        .font(.subheadline.weight(.medium))
                    Spacer()
                    if isHit {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                    }
                }

                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text(hkType.formatTarget(todayHealthKitValue))
                        .font(.title2.bold())
                    Text("/ \(hkType.formatTarget(target)) \(hkType.unit)")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text("\(Int(fraction * 100))%")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(isHit ? .green : .secondary)
                }

                GeometryReader { geometry in
                    ZStack(alignment: .leading) {
                        Capsule()
                            .fill(Color(.systemGray5))
                            .frame(height: 10)
                        Capsule()
                            .fill(isHit ? Color.green : habitColor)
                            .frame(width: max(fraction > 0 ? 10 : 0, geometry.size.width * fraction), height: 10)
                    }
                }
                .frame(height: 10)
            }
            .padding()
            .background(Color(.secondarySystemGroupedBackground))
            .clipShape(RoundedRectangle(cornerRadius: 16))
        }
    }

    // MARK: - Overall Stats

    private var overallStatsSection: some View {
        let myDays = challenge.myCompletedDays(for: currentUserID)
        let friendDays = challenge.friendCompletedDays(for: currentUserID)
        let total = challenge.targetDays
        let myRate = challenge.completionRate(for: currentUserID)
        let friendRate: Double = challenge.elapsedDays > 0
            ? min(1.0, Double(friendDays) / Double(challenge.elapsedDays)) : 0

        return VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("Overall")
                    .font(.subheadline.weight(.medium))
                Spacer()
                if let start = challenge.startDate, let end = challenge.endDate {
                    Text("\(start.formatted(.dateTime.month(.abbreviated).day())) – \(end.formatted(.dateTime.month(.abbreviated).day()))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            progressBar(
                label: String(localized: "friends_you"),
                days: myDays,
                total: total,
                rate: myRate,
                color: accentColor
            )

            progressBar(
                label: friendName,
                days: friendDays,
                total: total,
                rate: friendRate,
                color: habitColor
            )
        }
        .padding()
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }

    @ViewBuilder
    private func progressBar(label: String, days: Int, total: Int, rate: Double, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(label)
                    .font(.subheadline.weight(.medium))
                Spacer()
                Text("\(days)/\(total)")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Text("·")
                    .foregroundStyle(.secondary)
                Text("\(Int(rate * 100))%")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(color)
            }

            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(Color(.systemGray5))
                        .frame(height: 10)

                    let fraction = total > 0 ? min(1.0, Double(days) / Double(total)) : 0
                    Capsule()
                        .fill(color)
                        .frame(width: max(fraction > 0 ? 10 : 0, geometry.size.width * fraction), height: 10)
                }
            }
            .frame(height: 10)
        }
    }

    // MARK: - Mark Complete Button

    private var markCompleteButton: some View {
        Button {
            markTodayComplete()
        } label: {
            HStack {
                if isMarkingComplete {
                    ProgressView()
                        .tint(buttonForegroundColor)
                } else {
                    Image(systemName: "checkmark")
                    Text(String(localized: "challenges_mark_complete"))
                }
            }
            .frame(maxWidth: .infinity)
            .padding()
            .background(buttonBackground)
            .foregroundStyle(buttonForegroundColor)
            .clipShape(RoundedRectangle(cornerRadius: 12))
        }
        .disabled(isMarkingComplete)
    }

    // MARK: - Helpers

    private func loadCompletionData() {
        isTodayCompleted = challengeSyncService.isCompletedToday(challenge, context: modelContext)

        if challenge.isCreator(userID: currentUserID) {
            friendCompletionDates = challengeSyncService.getCompletions(
                for: challenge,
                userID: challenge.participantUserID,
                context: modelContext
            )
        } else {
            friendCompletionDates = challengeSyncService.getCompletions(
                for: challenge,
                userID: challenge.creatorUserID,
                context: modelContext
            )
        }
    }

    private func markTodayComplete() {
        isMarkingComplete = true

        Task {
            do {
                try await challengeSyncService.markTodayComplete(challenge, context: modelContext)
                isTodayCompleted = true
            } catch {
                print("Failed to mark complete: \(error)")
            }
            isMarkingComplete = false
        }
    }

    private func loadHealthKitProgress() async {
        guard let hkTypeString = challenge.healthKitType,
              let hkType = HealthKitDataType(rawValue: hkTypeString) else { return }

        // Fetch friend's snapshot (independent of local HK auth)
        let friendID = challenge.friendUserID(for: currentUserID)
        friendHKValue = await cloudKitService.fetchFriendHKSnapshot(
            challengeID: challenge.challengeID,
            friendUserID: friendID
        )

        guard HealthKitManager.shared.isAuthorized else { return }
        let value = await HealthKitManager.shared.fetchValue(for: hkType, date: Date())
        todayHealthKitValue = value

        // Upload our snapshot so friend can see it
        try? await cloudKitService.saveHKSnapshot(challengeID: challenge.challengeID, value: value)

        // Auto-complete if target reached and not yet marked
        guard !isTodayCompleted, challenge.canMarkTodayComplete else { return }
        let target = challenge.healthKitTarget ?? hkType.defaultTarget
        if value >= target {
            try? await challengeSyncService.markTodayComplete(challenge, context: modelContext)
            isTodayCompleted = true
        }
    }

    private func isFriendCompletedToday() -> Bool {
        let today = Calendar.current.startOfDay(for: Date())
        return friendCompletionDates.contains { Calendar.current.startOfDay(for: $0) == today }
    }
}

#Preview {
    ChallengeDetailView(
        challenge: {
            let c = SharedChallenge(
                creatorUserID: "user1",
                participantUserID: "user2",
                habitName: "Morning Meditation",
                habitEmoji: "🧘",
                habitColor: "#5856D6",
                targetDays: 30
            )
            c.statusRaw = "active"
            c.startDate = Calendar.current.date(byAdding: .day, value: -12, to: Date())
            c.endDate = Calendar.current.date(byAdding: .day, value: 18, to: Date())
            c.myCompletedDays = 10
            c.friendCompletedDays = 11
            c.participantDisplayName = "Sarah"
            c.participantAvatarEmoji = "😊"
            return c
        }()
    )
    .modelContainer(.preview)
}
