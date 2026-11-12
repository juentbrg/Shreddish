import Foundation
import Testing
@testable import ShreddishCore

struct AIDecodingTests {
    @Test func validWeekDecodes() throws {
        let week = try Fixture.week()
        #expect(week.days.count == 7)
        #expect(week.days[0].meals.count == 4)
        let first = week.days[0].meals[0]
        #expect(first.type == .breakfast)
        #expect(first.ingredients[0].aisle == .epicerie)
        #expect(first.prepSessionRef == nil)
        #expect(first.proteinG == 30)
    }

    @Test(arguments: ["truncated_week", "missing_field_week", "unknown_enum_week"])
    func invalidWeekIsInvalidOutput(name: String) throws {
        let data = try Fixture.data(name)
        #expect {
            _ = try AIResponseDecoder.decodeWeek(data)
        } throws: { error in
            if case AIError.invalidOutput = error { return true }
            return false
        }
    }

    @Test func infeasibleIsReportedWithoutValidation() throws {
        let data = try Fixture.data("infeasible_week")
        #expect {
            _ = try AIResponseDecoder.decodeWeek(data)
        } throws: { error in
            guard case let AIError.infeasible(reason) = error else { return false }
            return reason.contains("Budget")
        }
    }

    @Test func dayAndMealDecode() throws {
        let day = try AIResponseDecoder.decodeDay(Fixture.data("valid_day"))
        #expect(day.dayOffset == 3)
        let meal = try AIResponseDecoder.decodeMeal(Fixture.data("valid_meal"))
        #expect(meal.type == .lunch)
    }

    @Test func dashesAreRemovedFromGeneratedText() throws {
        let raw = try #require(String(data: Fixture.data("valid_meal"), encoding: .utf8))
        let original = try AIResponseDecoder.decodeMeal(Fixture.data("valid_meal"))
        let dashed = raw.replacingOccurrences(of: "\"\(original.name)\"", with: "\"\(original.name) \u{2014} 2\u{2013}3 min\"")
        let meal = try AIResponseDecoder.decodeMeal(Data(dashed.utf8))
        #expect(meal.name == "\(original.name), 2-3 min")
    }

    @Test(arguments: [
        ("Poulet — riz", "Poulet, riz"), ("Poulet—riz", "Poulet-riz"), ("2–3 min", "2-3 min"), ("sans tiret", "sans tiret"),
    ])
    func withoutDashes(input: String, expected: String) {
        #expect(TextNormalizer.withoutDashes(input) == expected)
    }

    @Test func mealEncodesSnakeCase() throws {
        let data = try AIResponseDecoder.encoder.encode(meal(prepSessionRef: 1))
        let text = try #require(String(data: data, encoding: .utf8))
        #expect(text.contains("\"prep_session_ref\":1"))
        #expect(text.contains("\"cost_eur\""))
    }
}
