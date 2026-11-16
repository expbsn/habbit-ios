//
//  StickWidgetsBundle.swift
//  StickWidgets
//
//  Created by Kian Jain on 04.02.26.
//

import WidgetKit
import SwiftUI

@main
struct StickWidgetsBundle: WidgetBundle {
    var body: some Widget {
        // Glass-style stylized medium widget (first in picker)
        GlassHabitWidget()

        // Daily note / to-do list with progress ring (medium)
        DailyNoteWidget()

        // Home screen widget for habit progress
        HabitWidget()

        // Multi-habit progress ring widget (2×2 small / 2×4 medium)
        MultiHabitWidget()

        // Lock screen step count widget
        HealthStepsWidget()

        // Timer Live Activity for Dynamic Island
        StickWidgetsLiveActivity()
    }
}
