# Project Rules - Stick (Motivational Habit Tracker)

## Core Principles

### Native-First Development
- **Always prefer native iOS components** over custom implementations
- Use SwiftUI native views, modifiers, and patterns
- Leverage system fonts, colors, and SF Symbols
- Follow Apple's Human Interface Guidelines
- Utilize built-in iOS features (haptics, animations, gestures)

### Code Quality
- Write clean, readable Swift code with clear intent
- Prefer clarity over cleverness
- Use meaningful variable and function names in English
- Keep functions focused and single-purpose
- Avoid force-unwrapping unless absolutely safe
- Use `guard` for early returns, `if let` for optional handling

### Architecture
- **SwiftUI** for all UI components
- **SwiftData** for persistence (iOS 17+)
- **MVVM pattern** where beneficial, but don't over-engineer
- Keep views lightweight - extract complex logic to ViewModels or services
- Use `@Observable` macro for state management
- Async/await for asynchronous operations

## Project Structure

### File Naming Conventions
- All files, folders, and code in **English**
- Views: `HabitListView.swift`, `OnboardingView.swift`
- ViewModels: `HabitViewModel.swift`, `AnalyticsViewModel.swift`
- Models: `Habit.swift`, `Goal.swift`, `HabitCompletion.swift`
- Services: `NotificationService.swift`, `TimerService.swift`
- Extensions: `Date+Extensions.swift`, `Color+Theme.swift`

### Folder Structure
```
Stick/
├── App/
│   ├── StickApp.swift
│   └── AppDelegate.swift (if needed)
├── Models/
│   ├── Habit.swift
│   ├── Goal.swift
│   └── ...
├── Views/
│   ├── Onboarding/
│   ├── Habits/
│   ├── Analytics/
│   └── Settings/
├── ViewModels/
├── Services/
│   ├── NotificationService.swift
│   ├── TimerService.swift
│   └── ...
├── Utilities/
│   ├── Extensions/
│   └── Helpers/
└── Resources/
    └── Assets.xcassets
```

## Design System

### Color Philosophy
- Support **Dark Mode and Light Mode** equally from day one
- Use semantic colors: `.primary`, `.secondary`, `.background`, etc.
- Custom accent color system:
  - Global app accent (user-customizable)
  - Per-habit colors (user-customizable)
  - Use `Color.accentColor` modifier appropriately
- Never hardcode colors - always use theme system

### Typography
- Use **system fonts** (San Francisco)
- Font weights: `.regular`, `.medium`, `.semibold`, `.bold`
- Dynamic Type support for accessibility
- Semantic text styles: `.title`, `.headline`, `.body`, `.caption`

### Spacing & Layout
- Use consistent spacing: 4, 8, 12, 16, 24, 32, 48
- Follow iOS padding conventions (16pt standard edge padding)
- Utilize native spacing with `.padding()`, `.spacing()`
- Keep layouts simple and familiar to iOS users

### Icons & Symbols
- **SF Symbols** for all icons
- Per-habit customization: SF Symbol OR Emoji support
- Consistent symbol rendering style (monochrome, hierarchical, palette)

## Data Management

### SwiftData Models
- Use `@Model` macro for persistent entities
- Define relationships clearly (`@Relationship`)
- Include proper deletion rules
- Use computed properties for derived data
- Keep models clean - business logic in services/ViewModels

### Data Structure Requirements
- **Habit**: frequency, schedule, duration, color, symbol/emoji, goal reference
- **Goal**: name, description, associated habits
- **HabitCompletion**: timestamp, duration (for timer-based habits)
- **UserPreferences**: onboarding state, app accent color, notification settings

### Shared Data for Widgets
- Prepare for App Groups from the start (structure data appropriately)
- Keep widget-relevant data easily queryable
- Think about widget updates when designing data flow

## Notifications

### Local Notifications Only
- Use `UNUserNotificationCenter` for all scheduling
- Support complex schedules:
  - Multiple times per day
  - Specific weekdays
  - Custom intervals (e.g., every 2 days)
  - Multiple notifications per habit
- Request permissions during onboarding
- Handle notification actions appropriately
- Update scheduled notifications when habits change

## Features Implementation

### Timer Functionality
- Active timer for duration-based habits
- Background timer support (if possible)
- Haptic feedback for timer events
- Visual progress indication
- Ability to pause/resume/complete

### Analytics & Tracking
- **Streaks**: Current streak, longest streak (overall + per habit + per day)
- **Completion Rate**: Daily, weekly, monthly, overall
- **Trends**: Line charts (weekly/monthly/overall view)
- **Calendar Heatmap**: Visual representation of completion patterns
- Use native **Charts framework** (iOS 16+)
- Efficient data queries for large datasets

### Onboarding
- Motivational questions flow ("Do you often procrastinate?", "What drives you?")
- Notification permission request
- Minimal required info - user can add name/details later
- Skip-able sections where appropriate
- Store onboarding completion state

### Customization
- **Per-Habit**: Color picker, SF Symbol selector, Emoji picker
- **Global**: App accent color selector
- Preview changes in real-time
- Persist preferences with SwiftData

## Performance & Best Practices

### Optimization
- Lazy loading for lists
- Efficient SwiftData queries with predicates
- Avoid unnecessary view updates
- Use `.task` for async operations in views
- Cache expensive calculations

### Accessibility
- VoiceOver support for all interactive elements
- Dynamic Type support
- Sufficient color contrast
- Haptic feedback for important actions
- Semantic labels for icons

### Localization Ready
- Use `LocalizedStringKey` for all user-facing text
- Even though app is English-only, structure for future localization
- Avoid hardcoded strings in views

## Testing Considerations
- Design models to be testable
- Separate business logic from views
- Use dependency injection where appropriate
- Test notification scheduling logic thoroughly

## Code Style Preferences

### Swift Conventions
- Use trailing closures when appropriate
- Prefer implicit returns for single-expression closures
- Use computed properties over simple functions
- Property order: static, instance properties, init, methods
- Group related functionality with `// MARK: -`

### Comments
- Write self-documenting code when possible
- Comment "why" not "what"
- Use `// TODO:`, `// FIXME:`, `// MARK:` appropriately
- Document complex algorithms or business logic

### Error Handling
- Use proper error handling with `throws` and `try/catch`
- Provide meaningful error messages
- Graceful degradation where possible
- Log errors appropriately (print for debugging, proper logging for production)

## Development Workflow
- Start with minimal viable features
- Iterate based on functionality
- Test on device early (especially notifications, haptics)
- Regular commits with clear messages
- Keep code modular and maintainable

## Widget Preparation
- Structure data models for easy widget consumption
- Design efficient queries for widget timeline
- Consider widget size variants early
- Plan for App Group container setup
