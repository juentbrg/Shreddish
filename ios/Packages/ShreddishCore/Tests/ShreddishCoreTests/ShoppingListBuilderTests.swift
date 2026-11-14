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
        ("Œufs", .cremerie, .epicerie),
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
            ingredient("Tofu", 2, "piece", aisle: .cremerie),
            ingredient("Tofu", 100, "g", aisle: .cremerie),
        ])
        #expect(lines.count == 2)
    }

    @Test func gramsAndMillilitersMerge() {
        let lines = ShoppingListBuilder.build(from: [
            ingredient("Huile de colza", 10, "g", cost: 0.02), ingredient("Huile de colza", 15, "ml", cost: 0.03),
            ingredient("huile de colza", 5, "g", cost: 0.01),
        ])
        #expect(lines.count == 1)
        #expect(lines.first?.totalQuantity == 30)
        #expect(lines.first?.unit == .ml)
        #expect(abs((lines.first?.costEur ?? 0) - 0.06) < 0.0001)
    }

    @Test func eggsAreOneLineInPieces() {
        var raw = ingredient("Oeuf entier cru", 120, aisle: .cremerie, cost: 0.5)
        raw.foodCode = 22000
        var boiled = ingredient("Oeufs durs", 2, "piece", aisle: .cremerie, cost: 0.5)
        boiled.foodCode = 22010
        var whole = ingredient("Oeuf entier", 4, "piece", aisle: .cremerie, cost: 1)
        whole.foodCode = 22000
        // « Oeufs » sans code (plan antérieur à la spec 010) : rattaché par son nom.
        let lines = ShoppingListBuilder.build(from: [
            raw, boiled, ingredient("Oeufs", 3, "piece", aisle: .cremerie, cost: 0.75), whole,
        ])
        #expect(lines.count == 1)
        #expect(lines.first?.name == "Œufs")
        #expect(lines.first?.unit == .piece)
        #expect(lines.first?.totalQuantity == 11)
        #expect(lines.first?.aisle == .epicerie)
        #expect(abs((lines.first?.costEur ?? 0) - 2.75) < 0.0001)
    }

    @Test func fruitsInGramsAreCountedInPieces() {
        var avocado = ingredient("Avocat", 180, aisle: .epicerie, cost: 1.2)
        avocado.foodCode = 13004
        var banana = ingredient("Banane", 120, aisle: .fruitsLegumes, cost: 0.3)
        banana.foodCode = 13005
        var apple = ingredient("Pomme", 300, aisle: .fruitsLegumes, cost: 0.6)
        apple.foodCode = 13039
        let lines = ShoppingListBuilder.build(from: [
            avocado, banana, ingredient("Bananes", 2, "piece", aisle: .fruitsLegumes, cost: 0.5),
            apple, ingredient("Pommes", 1, "piece", aisle: .fruitsLegumes, cost: 0.3),
        ])
        let byName = Dictionary(uniqueKeysWithValues: lines.map { ($0.name, $0) })
        #expect(lines.count == 3)
        #expect(byName["Avocats"]?.totalQuantity == 2) // 180 g mangés ÷ 0,7 ÷ 200 g = 1,3
        #expect(byName["Avocats"]?.aisle == .fruitsLegumes)
        #expect(byName["Bananes"]?.totalQuantity == 3) // 2 + 120 ÷ 0,65 ÷ 180 = 3,03
        #expect(byName["Pommes"]?.totalQuantity == 3) // 1 + 300 ÷ 0,9 ÷ 160 = 3,08
        #expect(lines.allSatisfy { $0.unit == .piece })
    }

    @Test func cookedRiceIsBoughtDry() {
        var cooked = ingredient("Riz basmati cuit", 250, aisle: .epicerie, cost: 0.4)
        cooked.foodCode = 9104
        var raw = ingredient("Riz thaï cru", 80, aisle: .epicerie, cost: 0.3)
        raw.foodCode = 9100
        let lines = ShoppingListBuilder.build(from: [cooked, raw])
        #expect(lines.count == 1)
        #expect(lines.first?.name == "Riz")
        #expect(lines.first?.totalQuantity == 180) // 250 g cuits × 0,4 + 80 g crus
    }

    @Test func pommeDeTerreIsNotAnApple() {
        let lines = ShoppingListBuilder.build(from: [ingredient("Pommes de terre", 400, aisle: .fruitsLegumes)])
        #expect(lines.first?.unit == .g)
        #expect(lines.first?.totalQuantity == 400)
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
