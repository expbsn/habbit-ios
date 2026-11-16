//
//  HabitWidget.swift
//  StickWidgets
//
//  Home screen widget displaying habit progress
//

import WidgetKit
import SwiftUI
import AppIntents

// MARK: - Shared Data Model

struct WidgetHabit: Codable, Identifiable, Hashable {
    let id: String
    let name: String
    let color: String
    let emoji: String?
    let symbolName: String?
    let currentCount: Int
    let targetCount: Int
    let isCompleted: Bool
    let frequency: String
    let streakCount: Int

    var progress: Double {
        guard targetCount > 0 else { return isCompleted ? 1.0 : 0.0 }
        return min(1.0, Double(currentCount) / Double(targetCount))
    }
}

struct WidgetData: Codable {
    let habits: [WidgetHabit]
    let overallProgress: Double
    let completedCount: Int
    let totalCount: Int
    let motivationalPhrase: String
}

// MARK: - Daily Note Model

enum WidgetNoteMode: String {
    case none = ""
    case text
    case todo
}

struct WidgetTodoItem: Codable, Hashable {
    let title: String
    let isDone: Bool
}

struct WidgetDailyNote {
    let mode: WidgetNoteMode
    let text: String
    let todos: [WidgetTodoItem]

    var isEmpty: Bool { mode == .none }
}

// MARK: - Motivational Phrases

private let motivationalPhrases = [
    "Keep pushing, you're doing great!",
    "Small steps lead to big changes",
    "Every day is a fresh start",
    "You're building something amazing",
    "Progress, not perfection",
    "Stay consistent, stay strong",
    "One habit at a time",
    "You've got this!",
    "Make today count",
    "Your future self will thank you"
]

// MARK: - Widget Data Provider

struct HabitWidgetDataProvider {
    // IMPORTANT: Must match the App Group ID in WidgetDataService.swift
    static let appGroupID = "group.com.kianjain.Stick"
    static let habitsKey = "widgetHabits"
    static let progressKey = "widgetProgress"

    static var sharedDefaults: UserDefaults? {
        UserDefaults(suiteName: appGroupID)
    }

    static func loadHabits() -> [WidgetHabit] {
        guard let defaults = sharedDefaults,
              let data = defaults.data(forKey: habitsKey),
              let habits = try? JSONDecoder().decode([WidgetHabit].self, from: data) else {
            return []
        }
        return habits
    }

    static func loadHabit(id: String) -> WidgetHabit? {
        loadHabits().first { $0.id == id }
    }

    static func loadProgress() -> Double {
        guard let defaults = sharedDefaults else { return 0 }
        return defaults.double(forKey: progressKey)
    }

    // Daily note keys (mirror WidgetDataService.swift)
    static let noteModeKey = "widgetDailyNoteMode"
    static let noteTextKey = "widgetDailyNoteText"
    static let noteTodosKey = "widgetDailyNoteTodos"

    static func loadDailyNote() -> WidgetDailyNote {
        guard let defaults = sharedDefaults else {
            return WidgetDailyNote(mode: .none, text: "", todos: [])
        }
        let modeRaw = defaults.string(forKey: noteModeKey) ?? ""
        let mode = WidgetNoteMode(rawValue: modeRaw) ?? .none

        switch mode {
        case .text:
            let text = defaults.string(forKey: noteTextKey) ?? ""
            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty { return WidgetDailyNote(mode: .none, text: "", todos: []) }
            return WidgetDailyNote(mode: .text, text: text, todos: [])
        case .todo:
            let todos: [WidgetTodoItem]
            if let data = defaults.data(forKey: noteTodosKey),
               let decoded = try? JSONDecoder().decode([WidgetTodoItem].self, from: data) {
                todos = decoded
            } else {
                todos = []
            }
            if todos.isEmpty { return WidgetDailyNote(mode: .none, text: "", todos: []) }
            return WidgetDailyNote(mode: .todo, text: "", todos: todos)
        case .none:
            return WidgetDailyNote(mode: .none, text: "", todos: [])
        }
    }

    static func loadWidgetData() -> WidgetData {
        let habits = loadHabits()
        let completedCount = habits.filter { $0.isCompleted }.count
        let totalCount = habits.count
        // Use synced progress from main app (calculated with ProgressTracker)
        let overallProgress = loadProgress()

        let phrase = motivationalPhrases.randomElement() ?? "Keep going!"

        return WidgetData(
            habits: habits,
            overallProgress: overallProgress,
            completedCount: completedCount,
            totalCount: totalCount,
            motivationalPhrase: phrase
        )
    }
}

// MARK: - App Intent for Habit Selection

struct SelectHabitIntent: WidgetConfigurationIntent {
    static var title: LocalizedStringResource = "Select Habit"
    static var description = IntentDescription("Choose which habit to display")

    @Parameter(title: "Habit")
    var habit: HabitEntity?
}

struct HabitEntity: AppEntity {
    let id: String
    let name: String

    static var typeDisplayRepresentation: TypeDisplayRepresentation = "Habit"
    static var defaultQuery = HabitEntityQuery()

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "\(name)")
    }
}

struct HabitEntityQuery: EntityQuery {
    func entities(for identifiers: [HabitEntity.ID]) async throws -> [HabitEntity] {
        let habits = HabitWidgetDataProvider.loadHabits()
        return identifiers.compactMap { id in
            habits.first { $0.id == id }.map { HabitEntity(id: $0.id, name: $0.name) }
        }
    }

    func suggestedEntities() async throws -> [HabitEntity] {
        HabitWidgetDataProvider.loadHabits().map { HabitEntity(id: $0.id, name: $0.name) }
    }

    func defaultResult() async -> HabitEntity? {
        HabitWidgetDataProvider.loadHabits().first.map { HabitEntity(id: $0.id, name: $0.name) }
    }
}

// MARK: - Timeline Provider

struct HabitWidgetProvider: AppIntentTimelineProvider {
    typealias Entry = HabitWidgetEntry
    typealias Intent = SelectHabitIntent

    func placeholder(in context: Context) -> HabitWidgetEntry {
        HabitWidgetEntry(
            date: Date(),
            habit: WidgetHabit(
                id: "placeholder",
                name: "Meditation",
                color: "#5E5CE6",
                emoji: "🧘",
                symbolName: nil,
                currentCount: 1,
                targetCount: 1,
                isCompleted: true,
                frequency: "Daily",
                streakCount: 12
            ),
            widgetData: WidgetData(
                habits: [],
                overallProgress: 0.89,
                completedCount: 8,
                totalCount: 9,
                motivationalPhrase: "Keep pushing, you're doing great!"
            )
        )
    }

    func snapshot(for configuration: SelectHabitIntent, in context: Context) async -> HabitWidgetEntry {
        let habit = configuration.habit.flatMap { HabitWidgetDataProvider.loadHabit(id: $0.id) }
        let widgetData = HabitWidgetDataProvider.loadWidgetData()
        return HabitWidgetEntry(date: Date(), habit: habit, widgetData: widgetData)
    }

    func timeline(for configuration: SelectHabitIntent, in context: Context) async -> Timeline<HabitWidgetEntry> {
        let habit = configuration.habit.flatMap { HabitWidgetDataProvider.loadHabit(id: $0.id) }
        let widgetData = HabitWidgetDataProvider.loadWidgetData()
        let now = Date()
        let calendar = Calendar.current

        var entries: [HabitWidgetEntry] = []

        // Current entry
        entries.append(HabitWidgetEntry(date: now, habit: habit, widgetData: widgetData))

        // Pre-generate an entry at midnight that shows a clean slate (0% / no habits)
        // so the widget doesn't show yesterday's 100% into the new day
        if let tomorrow = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: now)) {
            let midnightData = WidgetData(
                habits: [],
                overallProgress: 0,
                completedCount: 0,
                totalCount: widgetData.totalCount,
                motivationalPhrase: motivationalPhrases.randomElement() ?? "Fresh start!"
            )
            entries.append(HabitWidgetEntry(date: tomorrow, habit: nil, widgetData: midnightData))
        }

        // Ask WidgetKit to reload 15 minutes after midnight so the app's
        // background refresh has had time to write fresh data to UserDefaults
        let reloadAfter = calendar.date(
            byAdding: .minute, value: 15,
            to: calendar.startOfDay(for: calendar.date(byAdding: .day, value: 1, to: now) ?? now)
        ) ?? calendar.date(byAdding: .minute, value: 30, to: now)!

        return Timeline(entries: entries, policy: .after(reloadAfter))
    }
}

// MARK: - Timeline Entry

struct HabitWidgetEntry: TimelineEntry {
    let date: Date
    let habit: WidgetHabit?
    let widgetData: WidgetData
}

// MARK: - Widget Views

struct HabitWidgetEntryView: View {
    var entry: HabitWidgetEntry
    @Environment(\.widgetFamily) var family
    @Environment(\.colorScheme) var colorScheme

    var body: some View {
        switch family {
        case .systemSmall:
            SmallHabitWidgetView(habit: entry.habit, colorScheme: colorScheme)
        case .systemMedium:
            MediumHabitWidgetView(entry: entry, colorScheme: colorScheme)
        case .accessoryCircular:
            CircularLockScreenWidget(entry: entry)
        case .accessoryInline:
            InlineLockScreenWidget(entry: entry)
        case .accessoryRectangular:
            RectangularLockScreenWidget(entry: entry)
        default:
            SmallHabitWidgetView(habit: entry.habit, colorScheme: colorScheme)
        }
    }
}

// MARK: - Small Widget (Single Habit)

struct SmallHabitWidgetView: View {
    let habit: WidgetHabit?
    let colorScheme: ColorScheme

    private var progressTrackColor: Color {
        colorScheme == .dark ? Color.white.opacity(0.15) : Color.black.opacity(0.08)
    }

    var body: some View {
        if let habit = habit {
            VStack(spacing: 12) {
                Spacer()

                // Progress circle with icon inside
                ZStack {
                    // Background track
                    Circle()
                        .stroke(progressTrackColor, lineWidth: 12)

                    // Progress arc
                    Circle()
                        .trim(from: 0, to: habit.progress)
                        .stroke(
                            Color(hex: habit.color),
                            style: StrokeStyle(lineWidth: 12, lineCap: .round)
                        )
                        .rotationEffect(.degrees(-90))

                    // Icon/emoji in center
                    if let emoji = habit.emoji, !emoji.isEmpty {
                        Text(emoji)
                            .font(.system(size: 40))
                    } else if let symbol = habit.symbolName, !symbol.isEmpty {
                        Image(systemName: symbol)
                            .font(.system(size: 32, weight: .medium))
                            .foregroundStyle(Color(hex: habit.color))
                    } else {
                        Image(systemName: "checkmark.circle")
                            .font(.system(size: 32, weight: .medium))
                            .foregroundStyle(Color(hex: habit.color))
                    }
                }
                .frame(width: 100, height: 100)

                // Habit name
                Text(habit.name)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(1)

                Spacer()
            }
            .frame(maxWidth: .infinity)
            .containerBackground(.fill.tertiary, for: .widget)
        } else {
            PlaceholderWidgetView(colorScheme: colorScheme)
        }
    }
}

// MARK: - Medium Widget (Overview)

struct MediumHabitWidgetView: View {
    let entry: HabitWidgetEntry
    let colorScheme: ColorScheme

    private var iconBackgroundColor: Color {
        colorScheme == .dark ? Color.white.opacity(0.15) : Color.black.opacity(0.08)
    }

    private var progressBackgroundColor: Color {
        colorScheme == .dark ? Color.white.opacity(0.2) : Color.black.opacity(0.1)
    }

    // Get incomplete habits to display
    private var incompleteHabits: [WidgetHabit] {
        Array(entry.widgetData.habits.filter { !$0.isCompleted }.prefix(2))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Top section
            HStack(alignment: .center, spacing: 16) {
                // Large percentage
                Text("\(Int(entry.widgetData.overallProgress * 100))%")
                    .font(.system(size: 64, weight: .bold, design: .rounded))
                    .foregroundStyle(.primary)
                    .minimumScaleFactor(0.5)

                Spacer()

                // Incomplete habit icons
                HStack(spacing: 8) {
                    ForEach(incompleteHabits) { habit in
                        ZStack {
                            RoundedRectangle(cornerRadius: 12)
                                .fill(iconBackgroundColor)

                            if let emoji = habit.emoji, !emoji.isEmpty {
                                Text(emoji)
                                    .font(.system(size: 24))
                            } else if let symbol = habit.symbolName, !symbol.isEmpty {
                                Image(systemName: symbol)
                                    .font(.system(size: 20, weight: .medium))
                                    .foregroundStyle(Color(hex: habit.color))
                            } else {
                                Image(systemName: "circle")
                                    .font(.system(size: 20, weight: .medium))
                                    .foregroundStyle(Color(hex: habit.color))
                            }
                        }
                        .frame(width: 52, height: 52)
                    }

                    // Placeholder boxes if less than 2 incomplete
                    ForEach(0..<(2 - incompleteHabits.count), id: \.self) { _ in
                        ZStack {
                            RoundedRectangle(cornerRadius: 12)
                                .fill(iconBackgroundColor)

                            Image(systemName: "checkmark")
                                .font(.system(size: 20, weight: .medium))
                                .foregroundStyle(.green)
                        }
                        .frame(width: 52, height: 52)
                    }
                }
            }

            Spacer()

            // Motivational phrase
            Text(entry.widgetData.motivationalPhrase)
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(.primary)
                .lineLimit(1)

            Spacer().frame(height: 8)

            // Progress bar
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(progressBackgroundColor)
                        .frame(height: 14)

                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color.primary)
                        .frame(width: geometry.size.width * entry.widgetData.overallProgress, height: 14)
                }
            }
            .frame(height: 14)
        }
        .padding(8)
        .containerBackground(.fill.tertiary, for: .widget)
    }
}

// MARK: - Placeholder View

struct PlaceholderWidgetView: View {
    let colorScheme: ColorScheme

    private var trackColor: Color {
        colorScheme == .dark ? Color.white.opacity(0.15) : Color.black.opacity(0.08)
    }

    var body: some View {
        VStack(spacing: 12) {
            Spacer()

            ZStack {
                Circle()
                    .stroke(trackColor, lineWidth: 8)

                Image(systemName: "target")
                    .font(.system(size: 36))
                    .foregroundStyle(.secondary)
            }
            .frame(width: 100, height: 100)

            Text("Select a Habit")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(.secondary)

            Spacer()
        }
        .frame(maxWidth: .infinity)
        .containerBackground(.fill.tertiary, for: .widget)
    }
}

// MARK: - Widget Definition

struct HabitWidget: Widget {
    let kind: String = "HabitWidget"

    var body: some WidgetConfiguration {
        AppIntentConfiguration(
            kind: kind,
            intent: SelectHabitIntent.self,
            provider: HabitWidgetProvider()
        ) { entry in
            HabitWidgetEntryView(entry: entry)
        }
        .configurationDisplayName("Habit Progress")
        .description("Track your habit progress at a glance.")
        .supportedFamilies([
            .systemSmall,
            .systemMedium,
            .accessoryCircular,
            .accessoryInline,
            .accessoryRectangular
        ])
    }
}

// MARK: - Circular Lock Screen Widget

struct CircularLockScreenWidget: View {
    let entry: HabitWidgetEntry

    var body: some View {
        Gauge(value: entry.widgetData.overallProgress) {
        } currentValueLabel: {
            Text("\(Int(entry.widgetData.overallProgress * 100))%")
                .font(.system(size: 12, weight: .semibold, design: .rounded))
        }
        .gaugeStyle(.accessoryCircular)
        .containerBackground(.clear, for: .widget)
    }
}

// MARK: - Inline Lock Screen Widget

struct InlineLockScreenWidget: View {
    let entry: HabitWidgetEntry

    var body: some View {
        let data = entry.widgetData
        Group {
            if data.totalCount == 0 {
                Text("No habits")
            } else if data.completedCount == data.totalCount {
                Label("\(data.completedCount)/\(data.totalCount) habits", systemImage: "checkmark.circle.fill")
            } else {
                Text("\(data.completedCount)/\(data.totalCount) habits")
            }
        }
        .containerBackground(.clear, for: .widget)
    }
}

// MARK: - Rectangular Lock Screen Widget

struct RectangularLockScreenWidget: View {
    let entry: HabitWidgetEntry

    var body: some View {
        let data = entry.widgetData
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text("Habits")
                    .font(.headline)
                Spacer()
                Text("\(data.completedCount)/\(data.totalCount)")
                    .font(.caption)
            }
            ProgressView(value: data.overallProgress)
            Text("\(Int(data.overallProgress * 100))% complete")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .containerBackground(.clear, for: .widget)
    }
}

// MARK: - Glass Widget View

struct GlassHabitWidgetView: View {
    let entry: HabitWidgetEntry
    @Environment(\.colorScheme) var colorScheme

    private var dayLabel: String {
        "\(Calendar.current.component(.day, from: entry.date))"
    }

    private var monthLabel: String {
        let fmt = DateFormatter()
        fmt.dateFormat = "MMM"
        return fmt.string(from: entry.date).uppercased()
    }

    private var weekLabel: String {
        "W \(Calendar.current.component(.weekOfYear, from: entry.date))"
    }

    private var topStreak: Int {
        entry.widgetData.habits.map { $0.streakCount }.max() ?? 0
    }

    var body: some View {
        ZStack {
            // Corner labels
            VStack(spacing: 0) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("habbit")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(.primary.opacity(0.55))
                        Text(monthLabel)
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(.primary.opacity(0.4))
                    }
                    Spacer()
                    VStack(alignment: .trailing, spacing: 2) {
                        Text(weekLabel)
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(.primary.opacity(0.55))
                        Text("D \(dayLabel)")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(.primary.opacity(0.4))
                    }
                }
                Spacer()
                HStack(alignment: .bottom) {
                    Text("🔥 \(topStreak)")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.primary.opacity(0.55))
                    Spacer()
                    Text("\(entry.widgetData.completedCount) / \(entry.widgetData.totalCount)")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.primary.opacity(0.55))
                }
            }
            .padding(14)

            // Central progress ring
            ZStack {
                Circle()
                    .stroke(.primary.opacity(0.2), lineWidth: 10)
                Circle()
                    .trim(from: 0, to: entry.widgetData.overallProgress)
                    .stroke(.primary, style: StrokeStyle(lineWidth: 10, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                VStack(spacing: 2) {
                    Text("\(Int(entry.widgetData.overallProgress * 100))%")
                        .font(.system(size: 22, weight: .bold, design: .rounded))
                        .foregroundStyle(.primary)
                    Text("today")
                        .font(.system(size: 9, weight: .medium))
                        .foregroundStyle(.primary.opacity(0.5))
                }
            }
            .frame(width: 110, height: 110)
        }
        .containerBackground(for: .widget) {
            colorScheme == .dark ? Color.black : Color.white
        }
    }
}

// MARK: - Glass Widget Definition

struct GlassHabitWidget: Widget {
    let kind: String = "GlassHabitWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: GlassWidgetProvider()) { entry in
            GlassHabitWidgetView(entry: entry)
        }
        .configurationDisplayName("Stylized Widget")
        .description("A sleek, minimal view of your daily habit progress.")
        .supportedFamilies([.systemMedium])
    }
}

struct GlassWidgetProvider: TimelineProvider {
    func placeholder(in context: Context) -> HabitWidgetEntry {
        HabitWidgetEntry(
            date: Date(),
            habit: nil,
            widgetData: WidgetData(
                habits: [],
                overallProgress: 0.72,
                completedCount: 5,
                totalCount: 7,
                motivationalPhrase: ""
            )
        )
    }

    func getSnapshot(in context: Context, completion: @escaping (HabitWidgetEntry) -> Void) {
        completion(HabitWidgetEntry(date: Date(), habit: nil, widgetData: HabitWidgetDataProvider.loadWidgetData()))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<HabitWidgetEntry>) -> Void) {
        let now = Date()
        let calendar = Calendar.current
        let widgetData = HabitWidgetDataProvider.loadWidgetData()

        var entries: [HabitWidgetEntry] = []
        entries.append(HabitWidgetEntry(date: now, habit: nil, widgetData: widgetData))

        // Midnight entry: clean slate until background refresh writes fresh data
        if let tomorrow = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: now)) {
            let midnightData = WidgetData(
                habits: [],
                overallProgress: 0,
                completedCount: 0,
                totalCount: widgetData.totalCount,
                motivationalPhrase: motivationalPhrases.randomElement() ?? "Fresh start!"
            )
            entries.append(HabitWidgetEntry(date: tomorrow, habit: nil, widgetData: midnightData))
        }

        let reloadAfter = calendar.date(
            byAdding: .minute, value: 15,
            to: calendar.startOfDay(for: calendar.date(byAdding: .day, value: 1, to: now) ?? now)
        ) ?? calendar.date(byAdding: .minute, value: 30, to: now)!

        completion(Timeline(entries: entries, policy: .after(reloadAfter)))
    }
}

// MARK: - Daily Note Widget (medium)

struct DailyNoteEntry: TimelineEntry {
    let date: Date
    let widgetData: WidgetData
    let note: WidgetDailyNote
}

struct DailyNoteWidgetProvider: TimelineProvider {
    func placeholder(in context: Context) -> DailyNoteEntry {
        DailyNoteEntry(
            date: Date(),
            widgetData: WidgetData(
                habits: [],
                overallProgress: 0.6,
                completedCount: 3,
                totalCount: 5,
                motivationalPhrase: ""
            ),
            note: WidgetDailyNote(
                mode: .todo,
                text: "",
                todos: [
                    WidgetTodoItem(title: "Drink water", isDone: true),
                    WidgetTodoItem(title: "Call the dentist", isDone: false),
                    WidgetTodoItem(title: "Finish report", isDone: false)
                ]
            )
        )
    }

    func getSnapshot(in context: Context, completion: @escaping (DailyNoteEntry) -> Void) {
        completion(DailyNoteEntry(
            date: Date(),
            widgetData: HabitWidgetDataProvider.loadWidgetData(),
            note: HabitWidgetDataProvider.loadDailyNote()
        ))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<DailyNoteEntry>) -> Void) {
        let now = Date()
        let calendar = Calendar.current
        let widgetData = HabitWidgetDataProvider.loadWidgetData()
        let note = HabitWidgetDataProvider.loadDailyNote()

        var entries: [DailyNoteEntry] = [DailyNoteEntry(date: now, widgetData: widgetData, note: note)]

        // Midnight entry: clean slate until background refresh writes fresh data
        if let tomorrow = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: now)) {
            let midnightData = WidgetData(
                habits: [],
                overallProgress: 0,
                completedCount: 0,
                totalCount: widgetData.totalCount,
                motivationalPhrase: ""
            )
            entries.append(DailyNoteEntry(
                date: tomorrow,
                widgetData: midnightData,
                note: WidgetDailyNote(mode: .none, text: "", todos: [])
            ))
        }

        let reloadAfter = calendar.date(
            byAdding: .minute, value: 15,
            to: calendar.startOfDay(for: calendar.date(byAdding: .day, value: 1, to: now) ?? now)
        ) ?? calendar.date(byAdding: .minute, value: 30, to: now)!

        completion(Timeline(entries: entries, policy: .after(reloadAfter)))
    }
}

struct DailyNoteWidgetView: View {
    let entry: DailyNoteEntry
    @Environment(\.colorScheme) var colorScheme

    private var trackColor: Color {
        colorScheme == .dark ? Color.white.opacity(0.2) : Color.black.opacity(0.1)
    }

    // Incomplete habits fallback (like the progress widget)
    private var incompleteHabits: [WidgetHabit] {
        entry.widgetData.habits.filter { !$0.isCompleted }
    }

    var body: some View {
        HStack(spacing: 16) {
            // Left: daily progress ring
            progressRing
                .frame(width: 92, height: 92)

            // Right: note / todos / fallback habits
            VStack(alignment: .leading, spacing: 5) {
                rightContent
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .padding(16)
        .containerBackground(for: .widget) {
            colorScheme == .dark ? Color.black : Color.white
        }
    }

    // MARK: Ring

    private var progressRing: some View {
        ZStack {
            Circle()
                .stroke(trackColor, lineWidth: 9)
            Circle()
                .trim(from: 0, to: entry.widgetData.overallProgress)
                .stroke(.primary, style: StrokeStyle(lineWidth: 9, lineCap: .round))
                .rotationEffect(.degrees(-90))
            VStack(spacing: 1) {
                Text("\(Int(entry.widgetData.overallProgress * 100))%")
                    .font(.system(size: 20, weight: .bold, design: .rounded))
                    .foregroundStyle(.primary)
                    .minimumScaleFactor(0.6)
                Text("today")
                    .font(.system(size: 9, weight: .medium))
                    .foregroundStyle(.primary.opacity(0.5))
            }
        }
    }

    // MARK: Right content

    @ViewBuilder
    private var rightContent: some View {
        switch entry.note.mode {
        case .text:
            Text(entry.note.text)
                .font(.system(size: 14, weight: .regular))
                .foregroundStyle(.primary.opacity(0.85))
                .lineLimit(7)
                .multilineTextAlignment(.leading)
            Spacer(minLength: 0)

        case .todo:
            ForEach(Array(entry.note.todos.prefix(6).enumerated()), id: \.offset) { _, item in
                todoRow(title: item.title, isDone: item.isDone)
            }
            if entry.note.todos.count > 6 {
                Text("+\(entry.note.todos.count - 6) more")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.primary.opacity(0.5))
            }
            Spacer(minLength: 0)

        case .none:
            fallbackHabits
        }
    }

    // Fallback: remaining habits for today
    @ViewBuilder
    private var fallbackHabits: some View {
        if incompleteHabits.isEmpty && entry.widgetData.totalCount > 0 {
            noteHeader(icon: "checkmark.seal.fill", title: "All done")
            Text("Every habit for today is complete. Nice work!")
                .font(.system(size: 12, weight: .regular))
                .foregroundStyle(.primary.opacity(0.7))
                .lineLimit(3)
            Spacer(minLength: 0)
        } else if incompleteHabits.isEmpty {
            noteHeader(icon: "note.text", title: "Today")
            Text("No note yet. Add habits or a daily note to see them here.")
                .font(.system(size: 12, weight: .regular))
                .foregroundStyle(.primary.opacity(0.6))
                .lineLimit(3)
            Spacer(minLength: 0)
        } else {
            noteHeader(icon: "list.bullet", title: "To do today")
            VStack(alignment: .leading, spacing: 6) {
                ForEach(Array(incompleteHabits.prefix(5).enumerated()), id: \.offset) { _, habit in
                    habitRow(habit)
                }
                if incompleteHabits.count > 5 {
                    Text("+\(incompleteHabits.count - 5) more")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.primary.opacity(0.5))
                }
            }
            Spacer(minLength: 0)
        }
    }

    // MARK: Row builders

    private func noteHeader(icon: String, title: String) -> some View {
        HStack(spacing: 5) {
            Image(systemName: icon)
                .font(.system(size: 11, weight: .semibold))
            Text(title)
                .font(.system(size: 12, weight: .semibold))
        }
        .foregroundStyle(.primary.opacity(0.55))
        .padding(.bottom, 2)
    }

    private func todoRow(title: String, isDone: Bool) -> some View {
        HStack(spacing: 7) {
            Image(systemName: isDone ? "checkmark.circle.fill" : "circle")
                .font(.system(size: 13))
                .foregroundStyle(isDone ? Color.green : Color.primary.opacity(0.4))
            Text(title)
                .font(.system(size: 13, weight: .regular))
                .strikethrough(isDone)
                .foregroundStyle(Color.primary.opacity(isDone ? 0.45 : 0.85))
                .lineLimit(1)
        }
    }

    private func habitRow(_ habit: WidgetHabit) -> some View {
        HStack(spacing: 7) {
            if let emoji = habit.emoji, !emoji.isEmpty {
                Text(emoji)
                    .font(.system(size: 13))
            } else if let symbol = habit.symbolName, !symbol.isEmpty {
                Image(systemName: symbol)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Color(hex: habit.color))
            } else {
                Image(systemName: "circle")
                    .font(.system(size: 12))
                    .foregroundStyle(Color(hex: habit.color))
            }
            Text(habit.name)
                .font(.system(size: 13, weight: .regular))
                .foregroundStyle(.primary.opacity(0.85))
                .lineLimit(1)
        }
    }
}

struct DailyNoteWidget: Widget {
    let kind: String = "DailyNoteWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: DailyNoteWidgetProvider()) { entry in
            DailyNoteWidgetView(entry: entry)
        }
        .configurationDisplayName("Daily Note")
        .description("Your daily note or to-do list next to today's progress ring.")
        .supportedFamilies([.systemMedium])
    }
}

// MARK: - Multi Habit Widget (2×2 small / 2×4 medium — single entry in picker)

/// Shared ring cell — no name label, adapts to passed size.
private struct MultiHabitRingCell: View {
    let habit: WidgetHabit?
    let trackColor: Color
    let ringSize: CGFloat

    private var lineWidth: CGFloat { max(5, ringSize * 0.10) }

    var body: some View {
        ZStack {
            if let habit {
                Circle()
                    .stroke(trackColor, lineWidth: lineWidth)
                Circle()
                    .trim(from: 0, to: habit.progress)
                    .stroke(
                        habit.isCompleted ? Color.green : Color(hex: habit.color),
                        style: StrokeStyle(lineWidth: lineWidth, lineCap: .round)
                    )
                    .rotationEffect(.degrees(-90))
                Group {
                    if let emoji = habit.emoji, !emoji.isEmpty {
                        Text(emoji)
                            .font(.system(size: ringSize * 0.34))
                    } else if let symbol = habit.symbolName, !symbol.isEmpty {
                        Image(systemName: symbol)
                            .font(.system(size: ringSize * 0.27, weight: .medium))
                            .foregroundStyle(Color(hex: habit.color))
                    } else {
                        Image(systemName: "checkmark")
                            .font(.system(size: ringSize * 0.23, weight: .semibold))
                            .foregroundStyle(Color(hex: habit.color))
                    }
                }
            } else {
                Circle()
                    .stroke(trackColor, style: StrokeStyle(lineWidth: 3, dash: [4, 4]))
            }
        }
        .frame(width: ringSize, height: ringSize)
        .frame(maxWidth: .infinity)
    }
}

struct SelectMultiHabitsIntent: WidgetConfigurationIntent {
    static var title: LocalizedStringResource = "Select Habits"
    static var description = IntentDescription("Choose up to 8 habits to display")

    @Parameter(title: "Habit 1") var habit1: HabitEntity?
    @Parameter(title: "Habit 2") var habit2: HabitEntity?
    @Parameter(title: "Habit 3") var habit3: HabitEntity?
    @Parameter(title: "Habit 4") var habit4: HabitEntity?
    @Parameter(title: "Habit 5") var habit5: HabitEntity?
    @Parameter(title: "Habit 6") var habit6: HabitEntity?
    @Parameter(title: "Habit 7") var habit7: HabitEntity?
    @Parameter(title: "Habit 8") var habit8: HabitEntity?
}

struct MultiHabitEntry: TimelineEntry {
    let date: Date
    let habits: [WidgetHabit?] // always 8 elements; small uses first 4
}

struct MultiHabitProvider: AppIntentTimelineProvider {
    typealias Entry = MultiHabitEntry
    typealias Intent = SelectMultiHabitsIntent

    private func resolve(_ intent: SelectMultiHabitsIntent) -> [WidgetHabit?] {
        let all = HabitWidgetDataProvider.loadHabits()
        func find(_ e: HabitEntity?) -> WidgetHabit? {
            guard let id = e?.id else { return nil }
            return all.first { $0.id == id }
        }
        return [
            find(intent.habit1), find(intent.habit2), find(intent.habit3), find(intent.habit4),
            find(intent.habit5), find(intent.habit6), find(intent.habit7), find(intent.habit8)
        ]
    }

    func placeholder(in context: Context) -> MultiHabitEntry {
        let p = WidgetHabit(id: "p", name: "Habit", color: "#5E5CE6", emoji: "🧘",
                            symbolName: nil, currentCount: 1, targetCount: 1,
                            isCompleted: false, frequency: "Daily", streakCount: 0)
        return MultiHabitEntry(date: Date(), habits: Array(repeating: p, count: 8))
    }

    func snapshot(for configuration: SelectMultiHabitsIntent, in context: Context) async -> MultiHabitEntry {
        MultiHabitEntry(date: Date(), habits: resolve(configuration))
    }

    func timeline(for configuration: SelectMultiHabitsIntent, in context: Context) async -> Timeline<MultiHabitEntry> {
        let now = Date()
        let calendar = Calendar.current
        var entries = [MultiHabitEntry(date: now, habits: resolve(configuration))]
        if let tomorrow = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: now)) {
            entries.append(MultiHabitEntry(date: tomorrow, habits: Array(repeating: nil, count: 8)))
        }
        let reloadAfter = calendar.date(byAdding: .minute, value: 15,
            to: calendar.startOfDay(for: calendar.date(byAdding: .day, value: 1, to: now) ?? now))
            ?? calendar.date(byAdding: .minute, value: 30, to: now)!
        return Timeline(entries: entries, policy: .after(reloadAfter))
    }
}

struct MultiHabitWidgetView: View {
    let entry: MultiHabitEntry
    @Environment(\.widgetFamily) var family
    @Environment(\.colorScheme) var colorScheme

    private var trackColor: Color {
        colorScheme == .dark ? Color.white.opacity(0.15) : Color.black.opacity(0.08)
    }

    var body: some View {
        switch family {
        case .systemSmall:
            // 2×2 grid using first 4 habits
            VStack(spacing: 8) {
                HStack(spacing: 0) {
                    MultiHabitRingCell(habit: entry.habits[0], trackColor: trackColor, ringSize: 52)
                    MultiHabitRingCell(habit: entry.habits[1], trackColor: trackColor, ringSize: 52)
                }
                HStack(spacing: 0) {
                    MultiHabitRingCell(habit: entry.habits[2], trackColor: trackColor, ringSize: 52)
                    MultiHabitRingCell(habit: entry.habits[3], trackColor: trackColor, ringSize: 52)
                }
            }
            .padding(8)
            .containerBackground(.fill.tertiary, for: .widget)
        default:
            // 2×4 grid using all 8 habits
            VStack(spacing: 8) {
                HStack(spacing: 0) {
                    ForEach(0..<4, id: \.self) { col in
                        MultiHabitRingCell(habit: entry.habits[col], trackColor: trackColor, ringSize: 50)
                    }
                }
                HStack(spacing: 0) {
                    ForEach(0..<4, id: \.self) { col in
                        MultiHabitRingCell(habit: entry.habits[4 + col], trackColor: trackColor, ringSize: 50)
                    }
                }
            }
            .padding(8)
            .containerBackground(.fill.tertiary, for: .widget)
        }
    }
}

struct MultiHabitWidget: Widget {
    let kind: String = "MultiHabitWidget"

    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: kind, intent: SelectMultiHabitsIntent.self,
                               provider: MultiHabitProvider()) { entry in
            MultiHabitWidgetView(entry: entry)
        }
        .configurationDisplayName("Multi Habit Widget")
        .description("Track multiple habits at a glance with progress rings.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

// MARK: - Health Steps Widget

struct HealthStepsEntry: TimelineEntry {
    let date: Date
    let steps: Int
    let goal: Int

    var progress: Double {
        guard goal > 0 else { return 0 }
        return min(1.0, Double(steps) / Double(goal))
    }

    var formattedSteps: String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        return formatter.string(from: NSNumber(value: steps)) ?? "\(steps)"
    }
}

struct HealthStepsProvider: TimelineProvider {
    static let appGroupID = "group.com.kianjain.Stick"
    static let stepsCountKey = "widgetStepsCount"
    static let stepsGoalKey = "widgetStepsGoal"

    private static var sharedDefaults: UserDefaults? {
        UserDefaults(suiteName: appGroupID)
    }

    static func loadEntry(date: Date = Date()) -> HealthStepsEntry {
        let steps = sharedDefaults?.integer(forKey: stepsCountKey) ?? 0
        let goal = sharedDefaults?.integer(forKey: stepsGoalKey).nonZero ?? 10_000
        return HealthStepsEntry(date: date, steps: steps, goal: goal)
    }

    func placeholder(in context: Context) -> HealthStepsEntry {
        HealthStepsEntry(date: Date(), steps: 7_342, goal: 10_000)
    }

    func getSnapshot(in context: Context, completion: @escaping (HealthStepsEntry) -> Void) {
        completion(HealthStepsProvider.loadEntry())
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<HealthStepsEntry>) -> Void) {
        let now = Date()
        let calendar = Calendar.current
        let entry = HealthStepsProvider.loadEntry(date: now)

        // Midnight reset entry
        var entries = [entry]
        if let tomorrow = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: now)) {
            entries.append(HealthStepsEntry(date: tomorrow, steps: 0, goal: entry.goal))
        }

        let reloadAfter = calendar.date(
            byAdding: .minute, value: 15,
            to: calendar.startOfDay(for: calendar.date(byAdding: .day, value: 1, to: now) ?? now)
        ) ?? calendar.date(byAdding: .minute, value: 30, to: now)!

        completion(Timeline(entries: entries, policy: .after(reloadAfter)))
    }
}

private extension Int {
    var nonZero: Int? { self == 0 ? nil : self }
}

struct HealthStepsWidgetView: View {
    let entry: HealthStepsEntry
    @Environment(\.widgetFamily) var family

    var body: some View {
        switch family {
        case .accessoryCircular:
            Gauge(value: entry.progress) {
                Image(systemName: "figure.walk")
            } currentValueLabel: {
                Text(stepsShort)
                    .font(.system(size: 10, weight: .semibold, design: .rounded))
            }
            .gaugeStyle(.accessoryCircular)
            .containerBackground(.clear, for: .widget)

        case .accessoryInline:
            Label("\(entry.formattedSteps) steps", systemImage: "figure.walk")
                .containerBackground(.clear, for: .widget)

        default: // .accessoryRectangular
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 4) {
                    Image(systemName: "figure.walk")
                        .font(.caption2)
                    Text("Steps")
                        .font(.caption2.weight(.semibold))
                    Spacer()
                    Text("\(entry.formattedSteps) / \(goalFormatted)")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }

                ProgressView(value: entry.progress)
                    .tint(.primary)

                Text("\(Int(entry.progress * 100))% of daily goal")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            .containerBackground(.clear, for: .widget)
        }
    }

    private var stepsShort: String {
        if entry.steps >= 1000 {
            return String(format: "%.1fk", Double(entry.steps) / 1000)
        }
        return "\(entry.steps)"
    }

    private var goalFormatted: String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        return formatter.string(from: NSNumber(value: entry.goal)) ?? "\(entry.goal)"
    }
}

struct HealthStepsWidget: Widget {
    let kind: String = "HealthStepsWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: HealthStepsProvider()) { entry in
            HealthStepsWidgetView(entry: entry)
        }
        .configurationDisplayName("Steps")
        .description("Track your daily step count on the lock screen.")
        .supportedFamilies([
            .accessoryRectangular,
            .accessoryCircular,
            .accessoryInline
        ])
    }
}

// MARK: - Previews

#Preview("Small - With Habit", as: .systemSmall) {
    HabitWidget()
} timeline: {
    HabitWidgetEntry(
        date: Date(),
        habit: WidgetHabit(
            id: "1",
            name: "Meditation",
            color: "#5E5CE6",
            emoji: "🧘",
            symbolName: nil,
            currentCount: 1,
            targetCount: 1,
            isCompleted: true,
            frequency: "Daily",
            streakCount: 12
        ),
        widgetData: WidgetData(
            habits: [],
            overallProgress: 0.75,
            completedCount: 3,
            totalCount: 4,
            motivationalPhrase: "Keep going!"
        )
    )
}

#Preview("Small - Partial Progress", as: .systemSmall) {
    HabitWidget()
} timeline: {
    HabitWidgetEntry(
        date: Date(),
        habit: WidgetHabit(
            id: "1",
            name: "Exercise",
            color: "#FF9500",
            emoji: "🏋️",
            symbolName: nil,
            currentCount: 2,
            targetCount: 3,
            isCompleted: false,
            frequency: "Daily",
            streakCount: 5
        ),
        widgetData: WidgetData(
            habits: [],
            overallProgress: 0.5,
            completedCount: 2,
            totalCount: 4,
            motivationalPhrase: "Keep going!"
        )
    )
}

#Preview("Medium - Overview", as: .systemMedium) {
    HabitWidget()
} timeline: {
    HabitWidgetEntry(
        date: Date(),
        habit: nil,
        widgetData: WidgetData(
            habits: [
                WidgetHabit(id: "1", name: "Meditation", color: "#5E5CE6", emoji: "🧘", symbolName: nil, currentCount: 0, targetCount: 1, isCompleted: false, frequency: "Daily", streakCount: 0),
                WidgetHabit(id: "2", name: "Exercise", color: "#FF9500", emoji: "🏋️", symbolName: nil, currentCount: 0, targetCount: 1, isCompleted: false, frequency: "Daily", streakCount: 0),
                WidgetHabit(id: "3", name: "Read", color: "#34C759", emoji: "📚", symbolName: nil, currentCount: 1, targetCount: 1, isCompleted: true, frequency: "Daily", streakCount: 5),
                WidgetHabit(id: "4", name: "Water", color: "#007AFF", emoji: "💧", symbolName: nil, currentCount: 1, targetCount: 1, isCompleted: true, frequency: "Daily", streakCount: 3)
            ],
            overallProgress: 0.50,
            completedCount: 2,
            totalCount: 4,
            motivationalPhrase: "Keep pushing, you're doing great!"
        )
    )
}

#Preview("Small - No Habit", as: .systemSmall) {
    HabitWidget()
} timeline: {
    HabitWidgetEntry(
        date: Date(),
        habit: nil,
        widgetData: WidgetData(
            habits: [],
            overallProgress: 0,
            completedCount: 0,
            totalCount: 0,
            motivationalPhrase: "Start your journey!"
        )
    )
}
