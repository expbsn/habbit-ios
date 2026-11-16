//
//  ExploreView.swift
//  Stick
//
//  Created by Kian Jain on 05.02.26.
//

import SwiftUI
import SwiftData

struct ExploreView: View {
    @Environment(\.modelContext) private var modelContext
    @Query private var preferences: [UserPreferences]
    @State private var selectedTemplate: ExploreHabitTemplate?
    @State private var searchText = ""

    /// User's selected accent color
    private var accentColor: Color {
        let colorValue = preferences.first?.appAccentColor ?? UserPreferences.adaptiveAccentColor
        if colorValue == UserPreferences.adaptiveAccentColor {
            return Color.primary
        }
        return Color(hex: colorValue)
    }

    private var filteredCategories: [ExploreCategory] {
        if searchText.isEmpty {
            return ExploreCategory.allCases
        }
        return ExploreCategory.allCases.filter { category in
            let templates = ExploreHabitTemplate.templates(for: category)
            return templates.contains { $0.name.localizedCaseInsensitiveContains(searchText) }
        }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(spacing: 24) {
                    // Header
                    headerSection

                    // Categories
                    ForEach(filteredCategories) { category in
                        categorySection(category)
                    }
                }
                .padding(.bottom, 32)
            }
            .dimThemeScrollBackground()
            .navigationTitle(String(localized: "explore_title"))
            .searchable(text: $searchText, prompt: String(localized: "explore_search_habits"))
            .sheet(item: $selectedTemplate) { template in
                ExploreHabitDetailSheet(template: template)
            }
        }
    }

    // MARK: - Header Section

    private var headerSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(String(localized: "explore_discover"))
                .font(.title2)
                .fontWeight(.bold)

            Text(String(localized: "explore_discover_subtitle"))
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal)
        .padding(.top, 8)
    }

    // MARK: - Category Section

    private func categorySection(_ category: ExploreCategory) -> some View {
        let templates = filteredTemplates(for: category)

        return VStack(alignment: .leading, spacing: 12) {
            // Category Header
            HStack(spacing: 12) {
                // Category Icon (SF Symbol)
                Image(systemName: category.symbolName)
                    .font(.title2)
                    .foregroundStyle(category.accentColor)
                    .frame(width: 44, height: 44)
                    .background(category.accentColor.opacity(0.15))
                    .clipShape(RoundedRectangle(cornerRadius: 10))

                VStack(alignment: .leading, spacing: 2) {
                    Text(category.localizedName)
                        .font(.caption)
                        .fontWeight(.semibold)
                        .foregroundStyle(.secondary)

                    Text(category.localizedSubtitle)
                        .font(.headline)
                }

                Spacer()
            }
            .padding(.horizontal)

            // Habit Cards
            VStack(spacing: 0) {
                ForEach(Array(templates.enumerated()), id: \.element.id) { index, template in
                    Button {
                        selectedTemplate = template
                    } label: {
                        habitRow(template)
                    }
                    .buttonStyle(.plain)

                    if index < templates.count - 1 {
                        Divider()
                            .padding(.leading, 76)
                    }
                }
            }
            .background(Color(.secondarySystemGroupedBackground))
            .clipShape(RoundedRectangle(cornerRadius: 24))
            .padding(.horizontal)
        }
    }

    private func filteredTemplates(for category: ExploreCategory) -> [ExploreHabitTemplate] {
        let templates = ExploreHabitTemplate.templates(for: category)
        if searchText.isEmpty {
            return templates
        }
        return templates.filter { $0.name.localizedCaseInsensitiveContains(searchText) }
    }

    // MARK: - Habit Row

    private func habitRow(_ template: ExploreHabitTemplate) -> some View {
        HStack(spacing: 12) {
            // Emoji Icon
            Text(template.emoji)
                .font(.title2)
                .frame(width: 50, height: 50)
                .background(template.displayColor.opacity(0.15))
                .clipShape(RoundedRectangle(cornerRadius: 12))

            // Info
            VStack(alignment: .leading, spacing: 4) {
                Text(template.name)
                    .font(.body)
                    .fontWeight(.medium)
                    .foregroundStyle(.primary)

                Text(template.description)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer()

            // Add Button (uses user's accent color)
            Image(systemName: "plus.circle.fill")
                .font(.title2)
                .foregroundStyle(accentColor)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .contentShape(Rectangle())
    }
}

// MARK: - Preview

#Preview {
    ExploreView()
        .modelContainer(.preview)
}
