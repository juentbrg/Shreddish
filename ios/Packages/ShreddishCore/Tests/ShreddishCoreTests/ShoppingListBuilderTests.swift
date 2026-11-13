import Testing
@testable import ShreddishCore

struct ShoppingListBuilderTests {
    @Test(arguments: [
        ("  Tomates   Cerises ", "tomate cerise"),
        ("Œufs", "oeuf"),
        ("Pâtes complètes", "pate complete"),
        ("riz", "riz"),
        ("Noix", "noix"),
        ("Choux", "chou"),
        ("Brocolis surgelés", "brocoli surgele"),
    ])
    func normalize(input: String, expected: String) {
        #expect(ShoppingListBuilder.normalize(input) == expected)
    }

    @Test(arguments: [
        ("Yaourt nature", Aisle.fruitsLegumes, Aisle.cremerie),
        ("Œufs", .epicerie, .cremerie),
        ("Thon en boîte au naturel", .viandePoisson, .epicerie),
        ("Brocolis surgelés", .fruitsLegumes, .surgeles),
        ("Lait de coco", .cremerie, .epicerie),
        ("Beurre de cacahuète", .cremerie, .epicerie),
        ("Cuisses de poulet", .autre, .viandePoisson),
        ("Steak haché 5 %", .epicerie, .viandePoisson),
        ("Bananes", .fruitsLegumes, .fruitsLegumes),
        ("Pommes de terre", .epicerie, .epicerie),
    ])
    func aisleIsCorrectedFromName(name: String, aiAisle: Aisle, expected: Aisle) {
        #expect(AisleClassifier.corrected(name: name, aisle: aiAisle) == expected)
    }

    @Test func shoppingLineUsesCorrectedAisle() {
        let lines = ShoppingListBuilder.build(from: [ingredient("Yaourt nature", 500, aisle: .fruitsLegumes, cost: 1)])
        #expect(lines.first?.aisle == .cremerie)
    }

    @Test func mergesSameNameAndUnit() {
        let lines = ShoppingListBuilder.build(from: [
            ingredient("Riz basmati", 90, aisle: .epicerie, cost: 0.25),
            ingredient("riz Basmati", 80, aisle: .epicerie, cost: 0.20),
            ingredient("Blanc de poulet", 150, aisle: .viandePoisson, cost: 2.1),
        ])
        #expect(lines.count == 2)
        let rice = lines.first { $0.key.hasPrefix("riz basmati") }
        #expect(rice?.totalQuantity == 170)
        #expect(abs((rice?.costEur ?? 0) - 0.45) < 0.0001)
        #expect(rice?.name == "Riz basmati")
    }

    @Test func differentUnitsStaySeparate() {
        let lines = ShoppingListBuilder.build(from: [
            ingredient("Oeufs", 2, "piece", aisle: .cremerie),
            ingredient("Oeufs", 100, "g", aisle: .cremerie),
        ])
        #expect(lines.count == 2)
    }

    @Test func sortedByAisleThenName() {
        let lines = ShoppingListBuilder.build(from: [
            ingredient("Riz", 90, aisle: .epicerie),
            ingredient("Pommes", 2, "piece", aisle: .fruitsLegumes),
            ingredient("Bananes", 2, "piece", aisle: .fruitsLegumes),
            ingredient("Poulet", 150, aisle: .viandePoisson),
        ])
        #expect(lines.map(\.name) == ["Bananes", "Pommes", "Poulet", "Riz"])
    }

    @Test func weekFixtureAggregatesSevenDays() throws {
        let week = try Fixture.week()
        let lines = ShoppingListBuilder.build(from: week.days)
        let oats = lines.first { $0.key.hasPrefix("flocon d'avoine") }
        #expect(oats?.totalQuantity == 560) // 80 g × 7
        #expect(abs(ShoppingListBuilder.totalCost(lines) - 57.4) < 0.001) // 8,20 € × 7
    }

    @Test func invalidUnitsAreSkipped() {
        let lines = ShoppingListBuilder.build(from: [ingredient("Sel", 1, "pincée")])
        #expect(lines.isEmpty)
    }

    @Test func ownedSupplementsAreNotBought() {
        let lines = ShoppingListBuilder.build(
            from: [ingredient("Whey protéine", 30), ingredient("Riz", 80), ingredient("Créatine", 5)],
            owned: ["whey", "Créatine"]
        )
        #expect(lines.map(\.name) == ["Riz"])
    }
}
