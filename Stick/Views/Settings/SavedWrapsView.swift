//
//  SavedWrapsView.swift
//  Stick
//
//  List of past weekly wraps accessible from Settings.
//

import SwiftUI
import SwiftData

struct SavedWrapsView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \WeeklyWrap.weekStartDate, order: .reverse) private var wraps: [WeeklyWrap]

    @State private var selectedWrap: WeeklyWrap?

    var body: some View {
        List {
            if wraps.isEmpty {
                emptyState
            } else {
                ForEach(wraps) { wrap in
                    wrapRow(wrap)
                        .contentShape(Rectangle())
                        .onTapGesture {
                            selectedWrap = wrap
                        }
                }
                .onDelete(perform: deleteWraps)
            }
        }
        .listStyle(.insetGrouped)
        .dimThemeBackground()
        .navigationTitle(String(localized: "settings_weekly_wraps"))
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .fullScreenCover(item: $selectedWrap) { wrap in
            WeeklyWrapStoryView(wrap: wrap) {
                selectedWrap = nil
            }
        }
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: "gift")
                .font(.system(size: 48))
                .foregroundStyle(.secondary)

            Text(String(localized: "weekly_wraps_empty_title"))
                .font(.headline)

            Text(String(localized: "weekly_wraps_empty_description"))
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 48)
        .listRowBackground(Color.clear)
    }

    // MARK: - Wrap Row

    private func wrapRow(_ wrap: WeeklyWrap) -> some View {
        HStack(spacing: 16) {
            // Completion rate circle
            ZStack {
                Circle()
                    .stroke(Color.gray.opacity(0.2), lineWidth: 4)

                Circle()
                    .trim(from: 0, to: wrap.completionRate)
                    .stroke(
                        wrap.completionRate >= 0.8 ? Color.green : Color.orange,
                        style: StrokeStyle(lineWidth: 4, lineCap: .round)
                    )
                    .rotationEffect(.degrees(-90))

                Text("\(wrap.completionRatePercent)%")
                    .font(.caption2.weight(.semibold))
            }
            .frame(width: 44, height: 44)

            // Date and stats
            VStack(alignment: .leading, spacing: 4) {
                Text(wrap.dateRangeString)
                    .font(.body.weight(.medium))

                HStack(spacing: 12) {
                    HStack(spacing: 4) {
                        Image(systemName: "checkmark.circle")
                        Text("\(wrap.totalCompletions)")
                    }
                    HStack(spacing: 4) {
                        Image(systemName: "star.fill")
                        Text("\(wrap.perfectDays)")
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }

            Spacer()

            // View indicator
            if !wrap.isViewed {
                Circle()
                    .fill(Color.blue)
                    .frame(width: 8, height: 8)
            }

            Image(systemName: "chevron.right")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 8)
    }

    // MARK: - Delete

    private func deleteWraps(at offsets: IndexSet) {
        for index in offsets {
            modelContext.delete(wraps[index])
        }
        try? modelContext.save()
    }
}

#Preview {
    NavigationStack {
        SavedWrapsView()
    }
    .modelContainer(.preview)
}
