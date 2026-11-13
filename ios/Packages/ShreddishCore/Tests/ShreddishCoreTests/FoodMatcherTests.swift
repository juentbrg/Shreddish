import Testing
@testable import ShreddishCore

struct FoodMatcherTests {
    @Test func catalogIsBundled() {
        #expect(FoodCatalog.shared.foods.count > 3000)
        #expect(FoodCatalog.shared.food(code: 15047)?.name == "Chia, graine, séchée")
    }

    @Test(arguments: [
        ("Blanc de poulet", "Poulet blanc"),
        ("Fromage blanc 0 %", "Fromage blanc, nature, 0% MG"),
        ("Yaourt nature 0 %", "Yaourt ou lait fermenté, nature, 0% MG"),
        ("Œufs", "Oeuf cru"),
        ("Flocons d’avoine", "Flocons d'avoine"),
        ("Lentilles vertes sèches", "Lentille verte, sèche"),
        ("Lentilles en conserve égouttées", "Lentille, cuisinée, appertisée, égouttée"),
        ("Haricots rouges en boîte égouttés", "Haricot rouge, appertisé, égoutté"),
        ("Steak haché 5 %", "Boeuf, steak haché 5% MG cru"),
        ("Huile de colza", "Huile de colza"),
        ("Graines de chia", "Chia, graine, séchée"),
        ("Thon au naturel égoutté", "Thon"),
        ("Riz basmati", "Riz thaï ou basmati, cru"),
    ])
    func commonIngredientsMatch(name: String, expectedPrefix: String) {
        let best = FoodMatcher.rank(name).first?.food.name ?? ""
        #expect(best.hasPrefix(expectedPrefix), "\(name) → \(best)")
    }

    @Test func nearTiesWithSimilarMacrosAreConfident() {
        guard case let .confident(food) = FoodMatcher.match("Brocoli surgelé") else {
            Issue.record("brocoli ambigu")
            return
        }
        #expect(food.name.hasPrefix("Brocoli"))
    }

    @Test func differentMacrosAreAmbiguous() {
        guard case let .ambiguous(candidates) = FoodMatcher.match("Banane") else {
            Issue.record("banane non ambiguë")
            return
        }
        #expect(candidates.count <= 5)
        #expect(candidates.contains { $0.name.hasPrefix("Banane, chair") })
    }

    @Test func exactCiqualNameIsConfident() {
        #expect(FoodMatcher.match("Thon, au naturel, appertisé, égoutté") == .confident(FoodCatalog.shared.food(code: 26039)!))
    }

    @Test func unknownWordsAreNotFound() {
        #expect(FoodMatcher.match("Xylophone quantique") == .notFound)
    }

    @Test func gramsScaleMacros() throws {
        let chia = try #require(FoodCatalog.shared.food(code: 15047))
        #expect(abs(chia.macros(grams: 20).proteinG - chia.per100g.proteinG / 5) < 0.001)
    }
}
