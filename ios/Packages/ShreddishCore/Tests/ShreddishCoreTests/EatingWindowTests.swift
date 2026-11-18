import Foundation
import SwiftData
import Testing
@testable import ShreddishCore

/// Jeûne intermittent (spec 015).
struct EatingWindowTests {
    let window = EatingWindow(startMinutes: 12 * 60, endMinutes: 19 * 60 + 30)

    @Test func labelAndFastingDuration() {
        #expect(window.label == "12:00-19:30")
        #expect(window.fastingMinutes == 16 * 60 + 30)
    }

    @Test func windowKeepsAMinimumSpan() {
        let narrow = EatingWindow(startMinutes: 18 * 60, endMinutes: 19 * 60)
        #expect(narrow.endMinutes - narrow.startMinutes == EatingWindow.minimumMinutes)
    }

    @Test func timesInsideWindowAreKept() {
        let meals = [meal(.lunch, time: "12:30"), meal(.snack, time: "16:00"), meal(.dinner, time: "19:15")]
        #expect(window.fit(meals) == meals)
    }

    @Test func timesOutsideWindowAreSpreadInOrder() {
        let meals = [
            meal(.dinner, time: "20:00"), meal(.breakfast, time: "08:00"), meal(.lunch, time: "12:30"),
            meal(.snack, time: "16:00"),
        ]
        let times = window.fit(meals).map(\.time)
        #expect(times == ["19:30", "12:00", "14:30", "17:00"])
    }

    @Test func replacedMealIsClampedIntoWindow() {
        #expect(window.fit(time: "08:00") == "12:00")
        #expect(window.fit(time: "21:00") == "19:30")
        #expect(window.fit(time: "15:00") == "15:00")
    }

    @Test func dayValidationFitsMealTimes() {
        var constraints = constraints(mealsPerDay: 2)
        constraints.eatingWindow = window
        let day = DayPlanDTO(dayOffset: 0, meals: [meal(.breakfast, time: "08:00"), meal(.dinner, time: "20:30")])
        let result = AIOutputValidator.validate(day: day, constraints: constraints, expectedOffset: 0)
        #expect(result.sanitized?.meals.map(\.time) == ["12:00", "19:30"])
        #expect(result.corrected.contains(.mealTimesFitted(dayOffset: 0)))
    }

    @MainActor @Test func preferencesSendTheWindow() throws {
        let preferences = Preferences()
        #expect(preferences.promptPreferences.eatingWindow == nil)
        preferences.eatingWindow = window
        #expect(preferences.promptPreferences.eatingWindow == "12:00-19:30")
        #expect(preferences.constraints(targets: referenceTargets).eatingWindow == window)
        let input = PromptBuilder.weekInput(
            targets: referenceTargets, goal: .cut, preferences: preferences.promptPreferences
        )
        #expect(input.contains("\"eating_window\":\"12:00-19:30\""))
    }
}
