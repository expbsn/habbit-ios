# Stick - Motivational Habit Tracker

## Project Overview

### Purpose
A minimalist, motivation-focused habit tracking app that helps users build and maintain positive habits through personalized goal setting, intelligent reminders, and comprehensive analytics.

### Target Audience
- Individuals seeking to build better habits
- Users who struggle with procrastination
- People wanting data-driven insights into their behavior patterns
- iOS users who value native, well-designed experiences

### Core Value Proposition
- **Personalized**: Onboarding flow understands user motivations
- **Flexible**: Fully customizable habit scheduling (frequency, timing, duration)
- **Motivating**: Streak tracking, visual analytics, and timely notifications
- **Native**: Built with iOS-first design principles and native components
- **Private**: All data stored locally, no accounts required

## Technical Stack

### Platform Requirements
- **Minimum iOS Version**: iOS 17.0+
- **Language**: Swift 5.9+
- **UI Framework**: SwiftUI
- **Persistence**: SwiftData
- **Notifications**: UserNotifications framework (local only)
- **Charts**: Swift Charts framework
- **Widgets**: WidgetKit (future implementation)

### Key Dependencies
- None initially - pure native iOS
- Potential future: StoreKit (if monetization needed)

### Data Storage
- **SwiftData** for all persistent data
- Local device storage only
- Future: Shared App Group container for widget support
- No cloud sync, no authentication required

## Core Features (MVP)

### 1. Personalized Onboarding
**Goal**: Understand user motivation and set up permissions

**Flow**:
1. Welcome screen with app value proposition
2. Motivational questions:
   - "Do you often procrastinate?"
   - "What drives you to build good habits?"
   - "What's your biggest challenge with consistency?"
   - (2-4 questions total, keep it brief)
3. Notification permission request with clear explanation
4. Optional: Set preferred notification times
5. Completion screen with call-to-action to create first habit

**Technical Notes**:
- Store onboarding completion flag in UserDefaults or SwiftData
- Store answers for potential future personalization
- Handle permission denial gracefully

### 2. Habit Creation & Management

**Habit Properties**:
- **Basic Info**: Name, description (optional), goal assignment
- **Schedule**: 
  - Frequency: Daily, specific weekdays, every X days, custom
  - Time(s): Multiple reminders per day supported
  - Duration: Optional (for timer-based habits)
- **Customization**: Color, SF Symbol or Emoji
- **Notifications**: Enabled/disabled, custom reminder messages

**Actions**:
- Create new habit
- Edit existing habit
- Delete habit (with confirmation)
- Archive habit (optional - keep data but stop tracking)
- Reorder habits in list

**Views Needed**:
- Habit list (main screen)
- Habit creation/edit form
- Habit detail view

### 3. Goal System

**Goal Properties**:
- Name (e.g., "Healthy Body", "Career Growth")
- Description (optional)
- Associated habits (one-to-many relationship)
- Progress calculation (based on habit completions)

**Functionality**:
- Create/edit/delete goals
- Assign habits to goals
- View goal progress overview
- Filter habits by goal

### 4. Habit Completion & Timer

**Completion Methods**:
- **Quick Complete**: Tap to mark done (for non-duration habits)
- **Timer Mode**: For duration-based habits
  - Start timer
  - Pause/resume
  - Complete when target duration reached
  - Visual progress (circular progress indicator)
  - Haptic feedback at milestones

**Completion Data**:
- Timestamp
- Actual duration (if timer used)
- Notes (optional)
- Mood/effort rating (optional future feature)

### 5. Notifications & Reminders

**Notification Types**:
- Scheduled reminders (based on habit schedule)
- Streak milestone celebrations (optional)
- Encouragement notifications (if user behind on habits)

**Scheduling Logic**:
- Create notifications for next 1-2 weeks
- Update when habits modified
- Cancel notifications for completed habits (today)
- Reschedule after device restart

**Notification Actions**:
- "Complete" - marks habit done
- "Start Timer" - opens app to timer view
- "Skip" - dismisses without action
- "View" - opens app to habit detail

### 6. Analytics & Insights

#### Metrics Tracked

**Streak Tracking**:
- Current streak (consecutive completions)
- Longest streak (all-time record)
- Per-habit streaks
- Per-weekday streaks (e.g., "Best Monday performer")

**Completion Rate**:
- Daily completion percentage
- Weekly completion percentage
- Monthly completion percentage
- Overall completion rate
- Per-habit completion rate

**Trend Analysis**:
- Completion trends over time
- Best/worst days
- Time-of-day patterns
- Goal progress trends

#### Visualizations

**Line Charts** (using Swift Charts):
- Weekly view: Last 7 days completion rate
- Monthly view: Last 30 days completion rate
- Overall view: All-time trend (scrollable)
- Per-habit trends
- Per-goal trends

**Calendar Heatmap**:
- Month view showing completion density
- Color intensity based on completion rate
- Tap day to see details
- Streak visualization
- Similar to GitHub contribution graph

**Statistics Cards**:
- Total completions
- Current streak
- Longest streak
- Completion percentage
- Habits created
- Days active

### 7. Settings & Customization

**App Settings**:
- Global accent color picker
- Notification settings (global enable/disable)
- Default notification time
- Haptic feedback toggle
- App icon selection (future)

**User Profile** (Optional):
- Name
- Profile picture (optional)
- Motivation quote

**Data Management**:
- Export data (future)
- Reset all data (with confirmation)
- Clear completed habits

## Data Models (Core Schema)

### Habit
```swift
@Model
class Habit {
    var id: UUID
    var name: String
    var description: String?
    var color: String // Hex color
    var symbolName: String? // SF Symbol name
    var emoji: String? // Alternative to symbol
    var createdDate: Date
    var isActive: Bool
    
    // Scheduling
    var frequency: HabitFrequency // enum
    var scheduledDays: [Int]? // Weekday indices
    var scheduledTimes: [Date] // Time components
    var customInterval: Int? // For "every X days"
    var duration: TimeInterval? // Target duration if timer-based
    
    // Relationships
    var goal: Goal?
    var completions: [HabitCompletion]
    
    // Notifications
    var notificationsEnabled: Bool
    var reminderMessage: String?
}
```

### Goal
```swift
@Model
class Goal {
    var id: UUID
    var name: String
    var description: String?
    var createdDate: Date
    var habits: [Habit]
}
```

### HabitCompletion
```swift
@Model
class HabitCompletion {
    var id: UUID
    var habit: Habit
    var completionDate: Date
    var actualDuration: TimeInterval? // If timer used
    var notes: String?
}
```

### UserPreferences
```swift
@Model
class UserPreferences {
    var hasCompletedOnboarding: Bool
    var appAccentColor: String // Hex color
    var notificationsEnabled: Bool
    var hapticsEnabled: Bool
    var onboardingAnswers: [String: String]? // Question-answer pairs
}
```

## User Interface Structure

### Navigation Architecture
- **Tab Bar** (main navigation):
  - Habits (home)
  - Analytics
  - Settings

### Main Screens

1. **Habits Screen** (Home)
   - Today's habits list
   - Quick actions (complete, start timer)
   - Filter by goal
   - Add habit button
   - Streak indicators

2. **Analytics Screen**
   - Summary cards at top
   - Chart selection (week/month/overall)
   - Calendar heatmap
   - Detailed breakdowns
   - Goal progress

3. **Settings Screen**
   - User profile section
   - App customization
   - Notification settings
   - Data management
   - About/Help

### Modal Presentations

- Habit creation/edit form
- Goal creation/edit form
- Timer interface (full screen)
- Color picker
- Symbol/Emoji picker

## Widget Support (Future Phase)

### Widget Types
- **Small**: Today's completion percentage + streak
- **Medium**: Today's habit list with completion status
- **Large**: Weekly completion chart + top habits

### Technical Preparation
- Structure data for efficient widget queries
- Use App Groups for shared data container
- Design widget timeline provider
- Plan for widget configuration options

## Notification Strategy

### Permission Timing
- Request during onboarding with clear explanation
- Explain benefits: "Never miss a habit with timely reminders"
- Handle denial: Offer in-app reminders as fallback

### Scheduling Logic
- Generate notifications for next 7-14 days
- Update schedule when:
  - New habit created
  - Habit edited
  - Habit completed (cancel today's reminder)
  - App returns from background (refresh if needed)

### Notification Content
- **Title**: Habit name
- **Body**: Custom reminder message or default
- **Badge**: Number of pending habits today
- **Actions**: Complete, Start Timer, Skip

## Performance Considerations

### Data Queries
- Use predicates for efficient filtering
- Index by date for quick lookups
- Limit analytics queries to relevant time ranges
- Cache frequently accessed data

### UI Responsiveness
- Lazy loading for long lists
- Pagination for analytics history
- Smooth animations (< 16ms frame time)
- Background processing for notification scheduling

## Development Phases

### Phase 1: Core MVP (Start Here)
1. Basic app structure + navigation
2. SwiftData setup + models
3. Habit creation + list view
4. Simple completion tracking
5. Basic notifications

### Phase 2: Enhanced Tracking
1. Timer functionality
2. Goal system
3. Streak calculation
4. Calendar heatmap
5. Detailed analytics

### Phase 3: Polish & Customization
1. Color/symbol customization
2. Onboarding flow
3. Settings screen
4. Haptics + animations
5. Dark mode refinement

### Phase 4: Advanced Features
1. Widget support
2. Advanced analytics
3. Data export
4. App shortcuts
5. Siri integration (optional)

## Testing Strategy

### Manual Testing Focus
- Notification scheduling accuracy
- Timer functionality in background
- Dark/Light mode appearance
- SwiftData persistence
- Edge cases (timezone changes, date boundaries)

### Test Scenarios
- Create habit for specific weekdays
- Complete habit multiple days in a row (streak)
- Use timer for various durations
- Change habit schedule (update notifications)
- Delete habit (clean up notifications)
- Cross midnight boundary while app open

## Success Metrics

### User Engagement
- Daily active users
- Average habits per user
- Completion rate
- Streak retention (how many maintain 7+ day streaks)

### Technical Performance
- App launch time < 1 second
- SwiftData query time < 100ms
- Notification delivery reliability
- Memory usage < 100MB typical

## Future Enhancements (Post-MVP)

- **Social**: Share achievements (optional)
- **Gamification**: Badges, levels, challenges
- **Insights**: AI-powered habit suggestions
- **Export**: CSV, PDF reports
- **Backup**: iCloud sync (optional)
- **Apple Health**: Integration for health-related habits
- **Shortcuts**: Siri integration
- **Apple Watch**: Companion app
- **Themes**: Additional color schemes
- **Habit Templates**: Pre-built habit suggestions

## Design Philosophy

### Minimalist Approach
- Clean, uncluttered interfaces
- Focus on content over chrome
- Generous whitespace
- Clear visual hierarchy

### Native Feel
- Use system components whenever possible
- Follow iOS design patterns
- Respect user's system settings (text size, dark mode)
- Native animations and transitions

### Accessibility First
- VoiceOver support from day one
- Dynamic Type support
- High contrast mode compatibility
- Sufficient tap targets (44x44pt minimum)

## Notes for Claude Code

- Build incrementally, starting with core data models
- Test notification scheduling thoroughly on device
- Consider edge cases (habit due at midnight, timezone changes)
- Keep views simple and composable
- Extract reusable components early
- Comment complex scheduling logic
- Prepare for widget support in data structure design
