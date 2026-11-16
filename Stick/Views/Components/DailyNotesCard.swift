//
//  DailyNotesCard.swift
//  Stick
//
//  Card for displaying and accessing daily notes on the habits page.
//

import SwiftUI

struct DailyNotesCard: View {
    let note: DailyNote?
    let isToday: Bool
    let onTap: () -> Void

    private var hasContent: Bool {
        note?.hasContent ?? false
    }

    private var isTodoMode: Bool {
        note?.mode == .todo
    }

    /// Whether every todo in a todo-mode note is completed.
    private var allTodosDone: Bool {
        guard let note, note.mode == .todo, !note.todos.isEmpty else { return false }
        return note.todos.allSatisfy { $0.isDone }
    }

    /// SF Symbol for the note indicator (text / empty states).
    private var symbolName: String {
        guard hasContent else { return "square.and.pencil" }
        return "long.text.page.and.pencil"
    }

    private var previewText: String {
        if let note, note.hasContent {
            if note.mode == .todo {
                let done = note.todos.filter { $0.isDone }.count
                let total = note.todos.count
                let firstOpen = note.todos.first { !$0.isDone }?.title
                    ?? note.todos.first?.title ?? ""
                let countPart = String(format: String(localized: "daily_note_todo_count"), done, total)
                let trimmed = String(firstOpen.prefix(40)) + (firstOpen.count > 40 ? "…" : "")
                return trimmed.isEmpty ? countPart : "\(countPart) · \(trimmed)"
            } else {
                // Show first line or truncated content
                let firstLine = note.content.components(separatedBy: .newlines).first ?? note.content
                return String(firstLine.prefix(50)) + (firstLine.count > 50 ? "..." : "")
            }
        }
        return isToday
            ? String(localized: "daily_note_placeholder")
            : String(localized: "daily_note_empty")
    }

    var body: some View {
        HStack(spacing: 12) {
            // Grey circle with emoji / checklist indicator
            ZStack {
                Circle()
                    .fill(Color.gray.opacity(0.2))
                    .frame(width: 44, height: 44)

                if isTodoMode && hasContent {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.title2)
                        .foregroundStyle(allTodosDone ? Color.green : Color.secondary)
                } else {
                    Image(systemName: symbolName)
                        .font(.title3)
                        .foregroundStyle(.secondary)
                }
            }

            // Text content
            VStack(alignment: .leading, spacing: 2) {
                Text(hasContent
                    ? String(localized: "daily_note_title")
                    : String(localized: "daily_note_add"))
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)

                Text(previewText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer()

            // Chevron indicator
            Image(systemName: "chevron.right")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.tertiary)
        }
        .padding(16)
        #if canImport(UIKit)
        .background(Color(uiColor: .secondarySystemGroupedBackground))
        #else
        .background(Color(nsColor: .controlBackgroundColor))
        #endif
        .clipShape(RoundedRectangle(cornerRadius: 24))
        .contentShape(RoundedRectangle(cornerRadius: 24))
        .onTapGesture {
            onTap()
        }
    }
}

#Preview("Empty Today") {
    DailyNotesCard(note: nil, isToday: true, onTap: {})
        .padding()
}

#Preview("With Content") {
    DailyNotesCard(
        note: {
            let note = DailyNote(date: Date(), content: "Remember to call mom about the weekend plans and pick up groceries.")
            return note
        }(),
        isToday: true,
        onTap: {}
    )
    .padding()
}
