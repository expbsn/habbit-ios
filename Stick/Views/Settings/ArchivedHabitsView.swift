//
//  ArchivedHabitsView.swift
//  Stick
//
//  View for managing archived habits
//

import SwiftUI
import SwiftData

struct ArchivedHabitsView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(filter: #Predicate<Habit> { !$0.isActive }, sort: \Habit.createdDate, order: .reverse)
    private var archivedHabits: [Habit]

    @State private var habitToDelete: Habit?
    @State private var showingDeleteConfirmation = false

    var body: some View {
        List {
            if archivedHabits.isEmpty {
                ContentUnavailableView(
                    String(localized: "archived_empty_title"),
                    systemImage: "archivebox",
                    description: Text(String(localized: "archived_empty_description"))
                )
                .listRowBackground(Color.clear)
            } else {
                ForEach(archivedHabits) { habit in
                    ArchivedHabitRow(habit: habit)
                        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                            Button {
                                habitToDelete = habit
                                showingDeleteConfirmation = true
                            } label: {
                                Image(systemName: "trash")
                            }
                            .tint(.red)
                        }
                        .swipeActions(edge: .leading, allowsFullSwipe: true) {
                            Button {
                                restoreHabit(habit)
                            } label: {
                                Image(systemName: "arrow.uturn.backward")
                            }
                            .tint(.green)
                        }
                }
            }
        }
        .dimThemeBackground()
        .navigationTitle(String(localized: "settings_archived_habits"))
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
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
    }

    private func restoreHabit(_ habit: Habit) {
        habit.isActive = true
        Task {
            await NotificationManager.shared.scheduleNotifications(for: habit)
        }
        do {
            try modelContext.save()
        } catch {
            print("Failed to restore habit: \(error)")
        }
    }

    private func deleteHabit(_ habit: Habit) {
        modelContext.delete(habit)
        do {
            try modelContext.save()
        } catch {
            print("Failed to delete habit: \(error)")
        }
        habitToDelete = nil
    }
}

// MARK: - Archived Habit Row

struct ArchivedHabitRow: View {
    let habit: Habit

    var body: some View {
        HStack(spacing: 12) {
            // Icon
            ZStack {
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

            // Info
            VStack(alignment: .leading, spacing: 4) {
                Text(habit.name)
                    .font(.body.weight(.medium))

                HStack(spacing: 8) {
                    Text(String(format: String(localized: "archived_completions_count"), habit.safeCompletions.count))
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    Text(habit.frequency.displayName)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()

            // Restore indicator
            Image(systemName: "arrow.uturn.backward.circle")
                .font(.title3)
                .foregroundStyle(.green)
        }
        .padding(.vertical, 4)
    }
}

#Preview {
    NavigationStack {
        ArchivedHabitsView()
    }
    .modelContainer(.preview)
}
