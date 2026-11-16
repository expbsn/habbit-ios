//
//  DailyNotesEditorView.swift
//  Stick
//
//  Editor sheet for creating/editing daily notes.
//  Supports switching between free text and a todo list.
//

import SwiftUI
import SwiftData

struct DailyNotesEditorView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    let date: Date
    let existingNote: DailyNote?

    @State private var content: String
    @State private var mode: DailyNoteMode
    @State private var todos: [DailyTodoItem]
    @State private var newTodoTitle: String = ""
    @FocusState private var isTextEditorFocused: Bool
    @FocusState private var isNewTodoFocused: Bool

    private var isToday: Bool {
        Calendar.current.isDateInToday(date)
    }

    private var isReadOnly: Bool {
        !isToday
    }

    private var dateTitle: String {
        if isToday {
            return String(localized: "daily_note_today")
        } else {
            return date.formatted(.dateTime.weekday(.wide).month(.abbreviated).day())
        }
    }

    init(date: Date, existingNote: DailyNote?) {
        self.date = date
        self.existingNote = existingNote
        self._content = State(initialValue: existingNote?.content ?? "")
        self._mode = State(initialValue: existingNote?.mode ?? .text)
        self._todos = State(initialValue: existingNote?.todos ?? [])
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                if isReadOnly {
                    // Read-only banner for past dates
                    HStack {
                        Image(systemName: "lock.fill")
                            .font(.caption)
                        Text(String(localized: "daily_note_read_only"))
                            .font(.caption)
                    }
                    .foregroundStyle(.secondary)
                    .padding(.vertical, 8)
                    .frame(maxWidth: .infinity)
                    #if canImport(UIKit)
                    .background(Color(uiColor: .systemGroupedBackground))
                    #else
                    .background(Color(nsColor: .windowBackgroundColor))
                    #endif
                }

                // Mode switcher (Text / To-Do)
                Picker(String(localized: "daily_note_mode"), selection: $mode) {
                    Text(String(localized: "daily_note_mode_text")).tag(DailyNoteMode.text)
                    Text(String(localized: "daily_note_mode_todo")).tag(DailyNoteMode.todo)
                }
                .pickerStyle(.segmented)
                .disabled(isReadOnly)
                .padding(.horizontal)
                .padding(.top, 12)
                .padding(.bottom, 4)

                switch mode {
                case .text:
                    textEditor
                case .todo:
                    todoEditor
                }
            }
            .navigationTitle(dateTitle)
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(String(localized: "settings_cancel")) {
                        dismiss()
                    }
                }

                if !isReadOnly {
                    ToolbarItem(placement: .confirmationAction) {
                        Button(String(localized: "settings_save")) {
                            saveNote()
                            dismiss()
                        }
                        .fontWeight(.semibold)
                    }
                }
            }
            .onAppear {
                // Auto-focus for today's text notes
                if isToday && mode == .text {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                        isTextEditorFocused = true
                    }
                }
            }
        }
    }

    // MARK: - Text Editor

    private var textEditor: some View {
        TextEditor(text: $content)
            .focused($isTextEditorFocused)
            .disabled(isReadOnly)
            .scrollContentBackground(.hidden)
            .padding()
            .overlay(alignment: .topLeading) {
                // Only show placeholder for today (editable)
                if content.isEmpty && !isReadOnly {
                    Text(String(localized: "daily_note_placeholder"))
                        .foregroundStyle(.tertiary)
                        .padding(.horizontal, 20)
                        .padding(.vertical, 28)
                        .allowsHitTesting(false)
                }
            }
    }

    // MARK: - Todo Editor

    private var todoEditor: some View {
        List {
            ForEach($todos) { $item in
                HStack(spacing: 12) {
                    Button {
                        item.isDone.toggle()
                    } label: {
                        Image(systemName: item.isDone ? "checkmark.circle.fill" : "circle")
                            .font(.title3)
                            .foregroundStyle(item.isDone ? Color.accentColor : Color.secondary)
                    }
                    .buttonStyle(.plain)
                    .disabled(isReadOnly)

                    if isReadOnly {
                        Text(item.title)
                            .strikethrough(item.isDone)
                            .foregroundStyle(item.isDone ? .secondary : .primary)
                    } else {
                        TextField(String(localized: "daily_note_todo_item"), text: $item.title)
                            .strikethrough(item.isDone)
                            .foregroundStyle(item.isDone ? .secondary : .primary)
                    }
                }
            }
            .onDelete(perform: deleteHandler)

            if !isReadOnly {
                HStack(spacing: 12) {
                    Image(systemName: "plus.circle")
                        .font(.title3)
                        .foregroundStyle(.secondary)

                    TextField(String(localized: "daily_note_todo_add"), text: $newTodoTitle)
                        .focused($isNewTodoFocused)
                        .submitLabel(.done)
                        .onSubmit(addTodo)
                }
            }

            if todos.isEmpty && isReadOnly {
                Text(String(localized: "daily_note_empty"))
                    .foregroundStyle(.secondary)
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
    }

    /// Delete handler is disabled (nil) in read-only mode.
    private var deleteHandler: ((IndexSet) -> Void)? {
        guard !isReadOnly else { return nil }
        return deleteTodos
    }

    private func addTodo() {
        let trimmed = newTodoTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        todos.append(DailyTodoItem(title: trimmed))
        newTodoTitle = ""
        // Keep focus so the user can add several items in a row.
        isNewTodoFocused = true
    }

    private func deleteTodos(at offsets: IndexSet) {
        todos.remove(atOffsets: offsets)
    }

    // MARK: - Saving

    private func saveNote() {
        // Fold a pending unsaved todo entry into the list.
        let pending = newTodoTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        if mode == .todo && !pending.isEmpty {
            todos.append(DailyTodoItem(title: pending))
            newTodoTitle = ""
        }

        // Drop empty todo rows before persisting.
        let cleanedTodos = todos.filter {
            !$0.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }

        let trimmedContent = content.trimmingCharacters(in: .whitespacesAndNewlines)
        let hasAnyContent = (mode == .text && !trimmedContent.isEmpty)
            || (mode == .todo && !cleanedTodos.isEmpty)

        if let existingNote = existingNote {
            if !hasAnyContent {
                // Delete empty note
                modelContext.delete(existingNote)
                syncWidget(nil)
            } else {
                // Update existing note
                existingNote.content = content
                existingNote.mode = mode
                existingNote.todos = cleanedTodos
                existingNote.lastModifiedDate = Date()
                syncWidget(existingNote)
            }
        } else if hasAnyContent {
            // Create new note only if there's content
            let newNote = DailyNote(date: date, content: content)
            newNote.mode = mode
            newNote.todos = cleanedTodos
            modelContext.insert(newNote)
            syncWidget(newNote)
        }

        do {
            try modelContext.save()
        } catch {
            print("Failed to save daily note: \(error)")
        }
    }

    /// Push the just-edited note to the widget (only relevant for today).
    private func syncWidget(_ note: DailyNote?) {
        guard isToday else { return }
        WidgetDataService.shared.syncDailyNote(note)
    }
}

#Preview("Today - Empty") {
    DailyNotesEditorView(date: Date(), existingNote: nil)
}

#Preview("Today - With Content") {
    DailyNotesEditorView(
        date: Date(),
        existingNote: DailyNote(date: Date(), content: "This is my note for today!")
    )
}

#Preview("Past Date") {
    DailyNotesEditorView(
        date: Calendar.current.date(byAdding: .day, value: -3, to: Date())!,
        existingNote: DailyNote(date: Date(), content: "This is a note from the past.")
    )
}
