//
//  ExploreHabitTemplate.swift
//  Stick
//
//  Created by Kian Jain on 05.02.26.
//

import Foundation
import SwiftUI

// MARK: - Difficulty Level

enum HabitDifficulty: String, CaseIterable, Identifiable {
    case ambitious = "Ambitious"
    case interested = "Interested"
    case side = "Side"

    var id: String { rawValue }

    var localizedName: String {
        switch self {
        case .ambitious:
            return String(localized: "difficulty_ambitious")
        case .interested:
            return String(localized: "difficulty_interested")
        case .side:
            return String(localized: "difficulty_side")
        }
    }

    var description: String {
        switch self {
        case .ambitious:
            return "Full commitment - daily practice"
        case .interested:
            return "Regular practice - few times a week"
        case .side:
            return "Casual exploration - once a week"
        }
    }

    var localizedDescription: String {
        switch self {
        case .ambitious:
            return String(localized: "difficulty_ambitious_desc")
        case .interested:
            return String(localized: "difficulty_interested_desc")
        case .side:
            return String(localized: "difficulty_side_desc")
        }
    }

    var icon: String {
        switch self {
        case .ambitious:
            return "flame.fill"
        case .interested:
            return "star.fill"
        case .side:
            return "leaf.fill"
        }
    }

    var color: Color {
        switch self {
        case .ambitious:
            return .orange
        case .interested:
            return .blue
        case .side:
            return .green
        }
    }
}

// MARK: - Explore Category

enum ExploreCategory: String, CaseIterable, Identifiable {
    case languages = "Languages"
    case instruments = "Instruments"
    case sports = "Sports"
    case hobbies = "Hobbies"
    case skills = "Skills"
    case wellness = "Wellness"

    var id: String { rawValue }

    var localizedName: String {
        switch self {
        case .languages: return String(localized: "explore_category_languages")
        case .instruments: return String(localized: "explore_category_instruments")
        case .sports: return String(localized: "explore_category_sports")
        case .hobbies: return String(localized: "explore_category_hobbies")
        case .skills: return String(localized: "explore_category_skills")
        case .wellness: return String(localized: "explore_category_wellness")
        }
    }

    var symbolName: String {
        switch self {
        case .languages: return "globe"
        case .instruments: return "music.note"
        case .sports: return "figure.run"
        case .hobbies: return "paintpalette.fill"
        case .skills: return "lightbulb.fill"
        case .wellness: return "heart.fill"
        }
    }

    var subtitle: String {
        switch self {
        case .languages:
            return "Learn to communicate globally"
        case .instruments:
            return "Master the art of music"
        case .sports:
            return "Build strength and endurance"
        case .hobbies:
            return "Explore creative pursuits"
        case .skills:
            return "Level up your abilities"
        case .wellness:
            return "Nurture mind and body"
        }
    }

    var localizedSubtitle: String {
        switch self {
        case .languages: return String(localized: "explore_subtitle_languages")
        case .instruments: return String(localized: "explore_subtitle_instruments")
        case .sports: return String(localized: "explore_subtitle_sports")
        case .hobbies: return String(localized: "explore_subtitle_hobbies")
        case .skills: return String(localized: "explore_subtitle_skills")
        case .wellness: return String(localized: "explore_subtitle_wellness")
        }
    }

    var accentColor: Color {
        switch self {
        case .languages: return Color(hex: "#5856D6")
        case .instruments: return Color(hex: "#FF2D55")
        case .sports: return Color(hex: "#FF9500")
        case .hobbies: return Color(hex: "#AF52DE")
        case .skills: return Color(hex: "#007AFF")
        case .wellness: return Color(hex: "#34C759")
        }
    }
}

// MARK: - Explore Habit Template

struct ExploreHabitTemplate: Identifiable {
    let id = UUID()
    let name: String
    let emoji: String
    let color: String
    let description: String
    let category: ExploreCategory

    /// Duration in seconds for each difficulty level
    let ambitiousDuration: TimeInterval
    let interestedDuration: TimeInterval
    let sideDuration: TimeInterval

    /// Frequency for each difficulty
    let ambitiousFrequency: HabitFrequency
    let interestedFrequency: HabitFrequency
    let sideFrequency: HabitFrequency

    /// Weekly repetitions for flexible weekly habits
    let ambitiousWeeklyReps: Int?
    let interestedWeeklyReps: Int?
    let sideWeeklyReps: Int?

    var displayColor: Color {
        Color(hex: color)
    }

    func duration(for difficulty: HabitDifficulty) -> TimeInterval {
        switch difficulty {
        case .ambitious: return ambitiousDuration
        case .interested: return interestedDuration
        case .side: return sideDuration
        }
    }

    func frequency(for difficulty: HabitDifficulty) -> HabitFrequency {
        switch difficulty {
        case .ambitious: return ambitiousFrequency
        case .interested: return interestedFrequency
        case .side: return sideFrequency
        }
    }

    func weeklyReps(for difficulty: HabitDifficulty) -> Int? {
        switch difficulty {
        case .ambitious: return ambitiousWeeklyReps
        case .interested: return interestedWeeklyReps
        case .side: return sideWeeklyReps
        }
    }

    func frequencyDescription(for difficulty: HabitDifficulty) -> String {
        let freq = frequency(for: difficulty)
        let duration = duration(for: difficulty)
        let durationText = duration > 0 ? "\(Int(duration / 60)) min" : "Quick"

        switch freq {
        case .daily:
            return "\(durationText) daily"
        case .weekly:
            if let reps = weeklyReps(for: difficulty) {
                return "\(durationText), \(reps)x/week"
            }
            return "\(durationText) weekly"
        case .monthly:
            return "\(durationText) monthly"
        case .customInterval:
            return durationText
        }
    }
}

// MARK: - Template Data

extension ExploreHabitTemplate {
    static let allTemplates: [ExploreHabitTemplate] = [
        // MARK: Languages
        ExploreHabitTemplate(
            name: "Spanish",
            emoji: "🇪🇸",
            color: "#FF3B30",
            description: "Learn one of the most spoken languages worldwide",
            category: .languages,
            ambitiousDuration: 1800, interestedDuration: 900, sideDuration: 600,
            ambitiousFrequency: .daily, interestedFrequency: .weekly, sideFrequency: .weekly,
            ambitiousWeeklyReps: nil, interestedWeeklyReps: 4, sideWeeklyReps: 1
        ),
        ExploreHabitTemplate(
            name: "French",
            emoji: "🇫🇷",
            color: "#007AFF",
            description: "Master the language of love and diplomacy",
            category: .languages,
            ambitiousDuration: 1800, interestedDuration: 900, sideDuration: 600,
            ambitiousFrequency: .daily, interestedFrequency: .weekly, sideFrequency: .weekly,
            ambitiousWeeklyReps: nil, interestedWeeklyReps: 4, sideWeeklyReps: 1
        ),
        ExploreHabitTemplate(
            name: "Japanese",
            emoji: "🇯🇵",
            color: "#FF2D55",
            description: "Dive into Japanese language and culture",
            category: .languages,
            ambitiousDuration: 2700, interestedDuration: 1200, sideDuration: 600,
            ambitiousFrequency: .daily, interestedFrequency: .weekly, sideFrequency: .weekly,
            ambitiousWeeklyReps: nil, interestedWeeklyReps: 4, sideWeeklyReps: 1
        ),
        ExploreHabitTemplate(
            name: "German",
            emoji: "🇩🇪",
            color: "#FFCC00",
            description: "Learn the language of engineering and philosophy",
            category: .languages,
            ambitiousDuration: 1800, interestedDuration: 900, sideDuration: 600,
            ambitiousFrequency: .daily, interestedFrequency: .weekly, sideFrequency: .weekly,
            ambitiousWeeklyReps: nil, interestedWeeklyReps: 4, sideWeeklyReps: 1
        ),
        ExploreHabitTemplate(
            name: "Mandarin",
            emoji: "🇨🇳",
            color: "#FF3B30",
            description: "Learn the world's most spoken native language",
            category: .languages,
            ambitiousDuration: 2700, interestedDuration: 1200, sideDuration: 600,
            ambitiousFrequency: .daily, interestedFrequency: .weekly, sideFrequency: .weekly,
            ambitiousWeeklyReps: nil, interestedWeeklyReps: 4, sideWeeklyReps: 1
        ),
        ExploreHabitTemplate(
            name: "Korean",
            emoji: "🇰🇷",
            color: "#5856D6",
            description: "Explore K-culture through its language",
            category: .languages,
            ambitiousDuration: 2700, interestedDuration: 1200, sideDuration: 600,
            ambitiousFrequency: .daily, interestedFrequency: .weekly, sideFrequency: .weekly,
            ambitiousWeeklyReps: nil, interestedWeeklyReps: 4, sideWeeklyReps: 1
        ),

        // MARK: Instruments
        ExploreHabitTemplate(
            name: "Piano",
            emoji: "🎹",
            color: "#5856D6",
            description: "Master the king of instruments",
            category: .instruments,
            ambitiousDuration: 3600, interestedDuration: 1800, sideDuration: 900,
            ambitiousFrequency: .daily, interestedFrequency: .weekly, sideFrequency: .weekly,
            ambitiousWeeklyReps: nil, interestedWeeklyReps: 4, sideWeeklyReps: 2
        ),
        ExploreHabitTemplate(
            name: "Guitar",
            emoji: "🎸",
            color: "#FF9500",
            description: "Strum your way to musical expression",
            category: .instruments,
            ambitiousDuration: 2700, interestedDuration: 1800, sideDuration: 900,
            ambitiousFrequency: .daily, interestedFrequency: .weekly, sideFrequency: .weekly,
            ambitiousWeeklyReps: nil, interestedWeeklyReps: 4, sideWeeklyReps: 2
        ),
        ExploreHabitTemplate(
            name: "Drums",
            emoji: "🥁",
            color: "#FF3B30",
            description: "Feel the rhythm and keep the beat",
            category: .instruments,
            ambitiousDuration: 2700, interestedDuration: 1800, sideDuration: 900,
            ambitiousFrequency: .daily, interestedFrequency: .weekly, sideFrequency: .weekly,
            ambitiousWeeklyReps: nil, interestedWeeklyReps: 3, sideWeeklyReps: 1
        ),
        ExploreHabitTemplate(
            name: "Violin",
            emoji: "🎻",
            color: "#AF52DE",
            description: "Create beautiful melodies with strings",
            category: .instruments,
            ambitiousDuration: 3600, interestedDuration: 1800, sideDuration: 900,
            ambitiousFrequency: .daily, interestedFrequency: .weekly, sideFrequency: .weekly,
            ambitiousWeeklyReps: nil, interestedWeeklyReps: 4, sideWeeklyReps: 2
        ),
        ExploreHabitTemplate(
            name: "Singing",
            emoji: "🎤",
            color: "#FF2D55",
            description: "Train your voice as an instrument",
            category: .instruments,
            ambitiousDuration: 1800, interestedDuration: 1200, sideDuration: 600,
            ambitiousFrequency: .daily, interestedFrequency: .weekly, sideFrequency: .weekly,
            ambitiousWeeklyReps: nil, interestedWeeklyReps: 4, sideWeeklyReps: 2
        ),
        ExploreHabitTemplate(
            name: "DJ/Production",
            emoji: "🎧",
            color: "#007AFF",
            description: "Create and mix electronic music",
            category: .instruments,
            ambitiousDuration: 3600, interestedDuration: 1800, sideDuration: 900,
            ambitiousFrequency: .daily, interestedFrequency: .weekly, sideFrequency: .weekly,
            ambitiousWeeklyReps: nil, interestedWeeklyReps: 3, sideWeeklyReps: 1
        ),

        // MARK: Sports
        ExploreHabitTemplate(
            name: "Running",
            emoji: "🏃",
            color: "#FF9500",
            description: "Build endurance and cardio fitness",
            category: .sports,
            ambitiousDuration: 2700, interestedDuration: 1800, sideDuration: 1200,
            ambitiousFrequency: .daily, interestedFrequency: .weekly, sideFrequency: .weekly,
            ambitiousWeeklyReps: nil, interestedWeeklyReps: 3, sideWeeklyReps: 1
        ),
        ExploreHabitTemplate(
            name: "Swimming",
            emoji: "🏊",
            color: "#007AFF",
            description: "Full-body workout with zero impact",
            category: .sports,
            ambitiousDuration: 2700, interestedDuration: 1800, sideDuration: 1200,
            ambitiousFrequency: .weekly, interestedFrequency: .weekly, sideFrequency: .weekly,
            ambitiousWeeklyReps: 5, interestedWeeklyReps: 3, sideWeeklyReps: 1
        ),
        ExploreHabitTemplate(
            name: "Basketball",
            emoji: "🏀",
            color: "#FF3B30",
            description: "Improve agility and teamwork",
            category: .sports,
            ambitiousDuration: 3600, interestedDuration: 2700, sideDuration: 1800,
            ambitiousFrequency: .weekly, interestedFrequency: .weekly, sideFrequency: .weekly,
            ambitiousWeeklyReps: 5, interestedWeeklyReps: 3, sideWeeklyReps: 1
        ),
        ExploreHabitTemplate(
            name: "Soccer",
            emoji: "⚽",
            color: "#34C759",
            description: "The beautiful game for fitness and fun",
            category: .sports,
            ambitiousDuration: 3600, interestedDuration: 2700, sideDuration: 1800,
            ambitiousFrequency: .weekly, interestedFrequency: .weekly, sideFrequency: .weekly,
            ambitiousWeeklyReps: 4, interestedWeeklyReps: 2, sideWeeklyReps: 1
        ),
        ExploreHabitTemplate(
            name: "Tennis",
            emoji: "🎾",
            color: "#FFCC00",
            description: "Sharpen reflexes and coordination",
            category: .sports,
            ambitiousDuration: 3600, interestedDuration: 2700, sideDuration: 1800,
            ambitiousFrequency: .weekly, interestedFrequency: .weekly, sideFrequency: .weekly,
            ambitiousWeeklyReps: 4, interestedWeeklyReps: 2, sideWeeklyReps: 1
        ),
        ExploreHabitTemplate(
            name: "Gym/Weights",
            emoji: "🏋️",
            color: "#5856D6",
            description: "Build strength and muscle",
            category: .sports,
            ambitiousDuration: 3600, interestedDuration: 2700, sideDuration: 1800,
            ambitiousFrequency: .weekly, interestedFrequency: .weekly, sideFrequency: .weekly,
            ambitiousWeeklyReps: 6, interestedWeeklyReps: 3, sideWeeklyReps: 2
        ),
        ExploreHabitTemplate(
            name: "Cycling",
            emoji: "🚴",
            color: "#FF9500",
            description: "Explore outdoors while staying fit",
            category: .sports,
            ambitiousDuration: 3600, interestedDuration: 2700, sideDuration: 1800,
            ambitiousFrequency: .weekly, interestedFrequency: .weekly, sideFrequency: .weekly,
            ambitiousWeeklyReps: 5, interestedWeeklyReps: 3, sideWeeklyReps: 1
        ),
        ExploreHabitTemplate(
            name: "Martial Arts",
            emoji: "🥋",
            color: "#FF3B30",
            description: "Discipline, strength, and self-defense",
            category: .sports,
            ambitiousDuration: 3600, interestedDuration: 2700, sideDuration: 1800,
            ambitiousFrequency: .weekly, interestedFrequency: .weekly, sideFrequency: .weekly,
            ambitiousWeeklyReps: 5, interestedWeeklyReps: 3, sideWeeklyReps: 1
        ),

        // MARK: Hobbies
        ExploreHabitTemplate(
            name: "Drawing",
            emoji: "✏️",
            color: "#FF9500",
            description: "Express yourself through visual art",
            category: .hobbies,
            ambitiousDuration: 1800, interestedDuration: 1200, sideDuration: 600,
            ambitiousFrequency: .daily, interestedFrequency: .weekly, sideFrequency: .weekly,
            ambitiousWeeklyReps: nil, interestedWeeklyReps: 4, sideWeeklyReps: 1
        ),
        ExploreHabitTemplate(
            name: "Photography",
            emoji: "📸",
            color: "#5856D6",
            description: "Capture moments and tell stories",
            category: .hobbies,
            ambitiousDuration: 1800, interestedDuration: 1200, sideDuration: 600,
            ambitiousFrequency: .daily, interestedFrequency: .weekly, sideFrequency: .weekly,
            ambitiousWeeklyReps: nil, interestedWeeklyReps: 3, sideWeeklyReps: 1
        ),
        ExploreHabitTemplate(
            name: "Writing",
            emoji: "✍️",
            color: "#007AFF",
            description: "Craft stories, journals, or blogs",
            category: .hobbies,
            ambitiousDuration: 1800, interestedDuration: 1200, sideDuration: 600,
            ambitiousFrequency: .daily, interestedFrequency: .weekly, sideFrequency: .weekly,
            ambitiousWeeklyReps: nil, interestedWeeklyReps: 4, sideWeeklyReps: 2
        ),
        ExploreHabitTemplate(
            name: "Reading",
            emoji: "📚",
            color: "#34C759",
            description: "Expand your mind through books",
            category: .hobbies,
            ambitiousDuration: 1800, interestedDuration: 1200, sideDuration: 600,
            ambitiousFrequency: .daily, interestedFrequency: .daily, sideFrequency: .weekly,
            ambitiousWeeklyReps: nil, interestedWeeklyReps: nil, sideWeeklyReps: 3
        ),
        ExploreHabitTemplate(
            name: "Cooking",
            emoji: "👨‍🍳",
            color: "#FF3B30",
            description: "Master the culinary arts",
            category: .hobbies,
            ambitiousDuration: 2700, interestedDuration: 1800, sideDuration: 1200,
            ambitiousFrequency: .daily, interestedFrequency: .weekly, sideFrequency: .weekly,
            ambitiousWeeklyReps: nil, interestedWeeklyReps: 3, sideWeeklyReps: 1
        ),
        ExploreHabitTemplate(
            name: "Gardening",
            emoji: "🌱",
            color: "#34C759",
            description: "Grow plants and connect with nature",
            category: .hobbies,
            ambitiousDuration: 1800, interestedDuration: 1200, sideDuration: 600,
            ambitiousFrequency: .daily, interestedFrequency: .weekly, sideFrequency: .weekly,
            ambitiousWeeklyReps: nil, interestedWeeklyReps: 3, sideWeeklyReps: 1
        ),
        ExploreHabitTemplate(
            name: "Chess",
            emoji: "♟️",
            color: "#000000",
            description: "Sharpen strategic thinking",
            category: .hobbies,
            ambitiousDuration: 1800, interestedDuration: 1200, sideDuration: 600,
            ambitiousFrequency: .daily, interestedFrequency: .weekly, sideFrequency: .weekly,
            ambitiousWeeklyReps: nil, interestedWeeklyReps: 4, sideWeeklyReps: 2
        ),

        // MARK: Skills
        ExploreHabitTemplate(
            name: "Coding",
            emoji: "💻",
            color: "#007AFF",
            description: "Build apps and automate tasks",
            category: .skills,
            ambitiousDuration: 3600, interestedDuration: 1800, sideDuration: 900,
            ambitiousFrequency: .daily, interestedFrequency: .weekly, sideFrequency: .weekly,
            ambitiousWeeklyReps: nil, interestedWeeklyReps: 4, sideWeeklyReps: 2
        ),
        ExploreHabitTemplate(
            name: "Design",
            emoji: "🎨",
            color: "#AF52DE",
            description: "Create beautiful digital experiences",
            category: .skills,
            ambitiousDuration: 2700, interestedDuration: 1800, sideDuration: 900,
            ambitiousFrequency: .daily, interestedFrequency: .weekly, sideFrequency: .weekly,
            ambitiousWeeklyReps: nil, interestedWeeklyReps: 4, sideWeeklyReps: 2
        ),
        ExploreHabitTemplate(
            name: "Public Speaking",
            emoji: "🎙️",
            color: "#FF9500",
            description: "Communicate with confidence",
            category: .skills,
            ambitiousDuration: 1200, interestedDuration: 900, sideDuration: 600,
            ambitiousFrequency: .daily, interestedFrequency: .weekly, sideFrequency: .weekly,
            ambitiousWeeklyReps: nil, interestedWeeklyReps: 3, sideWeeklyReps: 1
        ),
        ExploreHabitTemplate(
            name: "Video Editing",
            emoji: "🎬",
            color: "#FF2D55",
            description: "Tell stories through video",
            category: .skills,
            ambitiousDuration: 3600, interestedDuration: 1800, sideDuration: 900,
            ambitiousFrequency: .daily, interestedFrequency: .weekly, sideFrequency: .weekly,
            ambitiousWeeklyReps: nil, interestedWeeklyReps: 3, sideWeeklyReps: 1
        ),
        ExploreHabitTemplate(
            name: "3D Modeling",
            emoji: "🧊",
            color: "#5856D6",
            description: "Create digital 3D art and objects",
            category: .skills,
            ambitiousDuration: 3600, interestedDuration: 1800, sideDuration: 900,
            ambitiousFrequency: .daily, interestedFrequency: .weekly, sideFrequency: .weekly,
            ambitiousWeeklyReps: nil, interestedWeeklyReps: 3, sideWeeklyReps: 1
        ),

        // MARK: Wellness
        ExploreHabitTemplate(
            name: "Meditation",
            emoji: "🧘",
            color: "#5856D6",
            description: "Find inner peace and clarity",
            category: .wellness,
            ambitiousDuration: 1200, interestedDuration: 600, sideDuration: 300,
            ambitiousFrequency: .daily, interestedFrequency: .daily, sideFrequency: .weekly,
            ambitiousWeeklyReps: nil, interestedWeeklyReps: nil, sideWeeklyReps: 3
        ),
        ExploreHabitTemplate(
            name: "Yoga",
            emoji: "🧘‍♀️",
            color: "#34C759",
            description: "Flexibility, strength, and mindfulness",
            category: .wellness,
            ambitiousDuration: 2700, interestedDuration: 1800, sideDuration: 900,
            ambitiousFrequency: .daily, interestedFrequency: .weekly, sideFrequency: .weekly,
            ambitiousWeeklyReps: nil, interestedWeeklyReps: 4, sideWeeklyReps: 2
        ),
        ExploreHabitTemplate(
            name: "Journaling",
            emoji: "📔",
            color: "#FF9500",
            description: "Reflect and process your thoughts",
            category: .wellness,
            ambitiousDuration: 900, interestedDuration: 600, sideDuration: 300,
            ambitiousFrequency: .daily, interestedFrequency: .daily, sideFrequency: .weekly,
            ambitiousWeeklyReps: nil, interestedWeeklyReps: nil, sideWeeklyReps: 3
        ),
        ExploreHabitTemplate(
            name: "Stretching",
            emoji: "🤸",
            color: "#FF2D55",
            description: "Improve flexibility and prevent injury",
            category: .wellness,
            ambitiousDuration: 900, interestedDuration: 600, sideDuration: 300,
            ambitiousFrequency: .daily, interestedFrequency: .daily, sideFrequency: .weekly,
            ambitiousWeeklyReps: nil, interestedWeeklyReps: nil, sideWeeklyReps: 4
        ),
        ExploreHabitTemplate(
            name: "Cold Showers",
            emoji: "🚿",
            color: "#007AFF",
            description: "Boost energy and mental toughness",
            category: .wellness,
            ambitiousDuration: 180, interestedDuration: 120, sideDuration: 60,
            ambitiousFrequency: .daily, interestedFrequency: .daily, sideFrequency: .weekly,
            ambitiousWeeklyReps: nil, interestedWeeklyReps: nil, sideWeeklyReps: 3
        ),
        ExploreHabitTemplate(
            name: "Breathwork",
            emoji: "🌬️",
            color: "#34C759",
            description: "Harness the power of breath",
            category: .wellness,
            ambitiousDuration: 600, interestedDuration: 300, sideDuration: 180,
            ambitiousFrequency: .daily, interestedFrequency: .daily, sideFrequency: .weekly,
            ambitiousWeeklyReps: nil, interestedWeeklyReps: nil, sideWeeklyReps: 3
        ),
    ]

    static func templates(for category: ExploreCategory) -> [ExploreHabitTemplate] {
        allTemplates.filter { $0.category == category }
    }
}
