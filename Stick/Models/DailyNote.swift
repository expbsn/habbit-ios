//
//  DailyNote.swift
//  Stick
//
//  Model for storing daily notes/todos per day.
//

import Foundation
import SwiftData

/// Whether a daily note is a free-text note or a checklist of todos.
enum DailyNoteMode: String, Codable {
    case text
    case todo
}

/// A single checklist item within a daily note (stored as JSON on `DailyNote`).
struct DailyTodoItem: Codable, Identifiable, Hashable {
    var id: UUID = UUID()
    var title: String
    var isDone: Bool = false

    init(id: UUID = UUID(), title: String, isDone: Bool = false) {
        self.id = id
        self.title = title
        self.isDone = isDone
    }
}

@Model
final class DailyNote {
    var id: UUID = UUID()
    var date: Date = Date()          // Start of day
    var content: String = ""         // Free-text content
    /// Raw value of `DailyNoteMode`. Stored as String for CloudKit compatibility.
    var modeRaw: String = DailyNoteMode.text.rawValue
    /// JSON-encoded `[DailyTodoItem]`. Optional for CloudKit compatibility.
    var todoData: Data? = nil
    var createdDate: Date = Date()
    var lastModifiedDate: Date = Date()

    /// Text vs. todo-list mode.
    var mode: DailyNoteMode {
        get { DailyNoteMode(rawValue: modeRaw) ?? .text }
        set { modeRaw = newValue.rawValue }
    }

    /// Decoded checklist items.
    var todos: [DailyTodoItem] {
        get {
            guard let todoData else { return [] }
            return (try? JSONDecoder().decode([DailyTodoItem].self, from: todoData)) ?? []
        }
        set {
            todoData = try? JSONEncoder().encode(newValue)
        }
    }

    /// Whether this note has any content for its current mode.
    var hasContent: Bool {
        switch mode {
        case .text:
            return !content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        case .todo:
            return !todos.isEmpty
        }
    }

    init(date: Date, content: String = "") {
        self.id = UUID()
        self.date = Calendar.current.startOfDay(for: date)
        self.content = content
        self.modeRaw = DailyNoteMode.text.rawValue
        self.todoData = nil
        self.createdDate = Date()
        self.lastModifiedDate = Date()
    }
}
