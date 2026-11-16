//
//  ExploreHabitDetailSheet.swift
//  Stick
//
//  Created by Kian Jain on 05.02.26.
//

import SwiftUI
import SwiftData

struct ExploreHabitDetailSheet: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme

    let template: ExploreHabitTemplate

    @State private var selectedDifficulty: HabitDifficulty = .interested
    @State private var showingSuccess = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    // Header with emoji and info
                    headerSection

                    // Difficulty Selection
                    difficultySection

                    // Selected Plan Details
                    planDetailsSection

                    // Add Button
                    addButton
                }
                .padding()
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle(String(localized: "explore_add_habit"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(String(localized: "settings_cancel")) {
                        dismiss()
                    }
                }
            }
            .overlay {
                if showingSuccess {
                    successOverlay
                }
            }
        }
    }

    // MARK: - Header Section

    private var headerSection: some View {
        VStack(spacing: 16) {
            // Large emoji icon
            Text(template.emoji)
                .font(.system(size: 64))
                .frame(width: 100, height: 100)
                .background(template.displayColor.opacity(0.15))
                .clipShape(RoundedRectangle(cornerRadius: 24))

            VStack(spacing: 8) {
                Text(template.name)
                    .font(.title2)
                    .fontWeight(.bold)

                Text(template.description)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
        }
        .padding(.top, 8)
    }

    // MARK: - Difficulty Section

    private var difficultySection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(String(localized: "explore_choose_commitment"))
                .font(.headline)

            VStack(spacing: 8) {
                ForEach(HabitDifficulty.allCases) { difficulty in
                    difficultyCard(difficulty)
                }
            }
        }
    }

    private func difficultyCard(_ difficulty: HabitDifficulty) -> some View {
        let isSelected = selectedDifficulty == difficulty

        return Button {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                selectedDifficulty = difficulty
            }
        } label: {
            HStack(spacing: 12) {
                // Icon
                Image(systemName: difficulty.icon)
                    .font(.title3)
                    .foregroundStyle(difficulty.color)
                    .frame(width: 36, height: 36)
                    .background(difficulty.color.opacity(0.15))
                    .clipShape(Circle())

                // Text
                VStack(alignment: .leading, spacing: 2) {
                    Text(difficulty.localizedName)
                        .font(.body)
                        .fontWeight(.semibold)
                        .foregroundStyle(.primary)

                    Text(template.frequencyDescription(for: difficulty))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                // Selection indicator
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.title2)
                    .foregroundStyle(isSelected ? difficulty.color : Color(.tertiaryLabel))
            }
            .padding()
            .background(Color(.secondarySystemGroupedBackground))
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(isSelected ? difficulty.color : Color.clear, lineWidth: 2)
            )
        }
        .buttonStyle(.plain)
    }

    // MARK: - Plan Details Section

    private var planDetailsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(String(localized: "explore_your_plan"))
                .font(.headline)

            VStack(spacing: 0) {
                planDetailRow(
                    icon: "clock.fill",
                    title: String(localized: "explore_duration"),
                    value: formatDuration(template.duration(for: selectedDifficulty))
                )

                Divider().padding(.leading, 52)

                planDetailRow(
                    icon: "calendar",
                    title: String(localized: "explore_frequency"),
                    value: formatFrequency()
                )

                if let reps = template.weeklyReps(for: selectedDifficulty) {
                    Divider().padding(.leading, 52)

                    planDetailRow(
                        icon: "repeat",
                        title: String(localized: "explore_times_per_week"),
                        value: "\(reps)x"
                    )
                }
            }
            .background(Color(.secondarySystemGroupedBackground))
            .clipShape(RoundedRectangle(cornerRadius: 12))
        }
    }

    private func planDetailRow(icon: String, title: String, value: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.body)
                .foregroundStyle(template.displayColor)
                .frame(width: 28)

            Text(title)
                .foregroundStyle(.secondary)

            Spacer()

            Text(value)
                .fontWeight(.medium)
        }
        .padding()
    }

    private func formatDuration(_ seconds: TimeInterval) -> String {
        if seconds < 60 {
            return "\(Int(seconds)) sec"
        } else if seconds < 3600 {
            let minutes = Int(seconds / 60)
            return "\(minutes) min"
        } else {
            let hours = Int(seconds / 3600)
            let minutes = Int((seconds.truncatingRemainder(dividingBy: 3600)) / 60)
            if minutes > 0 {
                return "\(hours)h \(minutes)m"
            }
            return "\(hours)h"
        }
    }

    private func formatFrequency() -> String {
        let freq = template.frequency(for: selectedDifficulty)
        switch freq {
        case .daily:
            return String(localized: "explore_every_day")
        case .weekly:
            if template.weeklyReps(for: selectedDifficulty) != nil {
                return String(localized: "explore_flexible_weekly")
            }
            return String(localized: "frequency_weekly")
        case .monthly:
            return String(localized: "frequency_monthly")
        case .customInterval:
            return String(localized: "explore_custom")
        }
    }

    // MARK: - Add Button

    private var addButton: some View {
        Button {
            addHabit()
        } label: {
            Label(String(localized: "explore_add_to_habits"), systemImage: "plus.circle.fill")
                .font(.headline)
                .frame(maxWidth: .infinity)
                .padding()
                .background(template.displayColor)
                .foregroundStyle(.white)
                .clipShape(RoundedRectangle(cornerRadius: 14))
        }
        .padding(.top, 8)
    }

    // MARK: - Success Overlay

    private var successOverlay: some View {
        ZStack {
            // Adaptive dimming overlay
            (colorScheme == .dark ? Color.black : Color.black)
                .opacity(colorScheme == .dark ? 0.5 : 0.3)
                .ignoresSafeArea()

            VStack(spacing: 16) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 64))
                    .foregroundStyle(template.displayColor)

                Text(String(localized: "explore_habit_added"))
                    .font(.title2)
                    .fontWeight(.bold)
                    .foregroundStyle(.primary)

                Text(String(format: String(localized: "explore_habit_added_msg"), template.name))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .padding(32)
            .background(
                RoundedRectangle(cornerRadius: 24)
                    .fill(Color(.systemBackground))
                    .shadow(color: .black.opacity(0.15), radius: 20, y: 10)
            )
        }
        .transition(.opacity)
    }

    // MARK: - Add Habit Action

    private func addHabit() {
        let frequency = template.frequency(for: selectedDifficulty)
        let duration = template.duration(for: selectedDifficulty)
        let weeklyReps = template.weeklyReps(for: selectedDifficulty)

        let habit = Habit(
            name: template.name,
            description: template.description,
            color: template.color,
            emoji: template.emoji,
            frequency: frequency,
            duration: duration > 0 ? duration : nil,
            weeklyRepetitions: weeklyReps,
            notificationsEnabled: true
        )

        modelContext.insert(habit)

        // Show success animation
        withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
            showingSuccess = true
        }

        // Dismiss after delay
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
            dismiss()
        }
    }
}

// MARK: - Preview

#Preview {
    ExploreHabitDetailSheet(
        template: ExploreHabitTemplate.allTemplates.first!
    )
    .modelContainer(.preview)
}
