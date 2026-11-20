import Foundation

/// Régime alimentaire (spec 017, FR-1703), cumulable. Envoyé à l'IA et vérifié localement.
public enum Diet: String, Codable, Sendable, CaseIterable {
    case vegetarian, vegan, pescatarian, halal, kosher, glutenFree = "gluten_free", lactoseFree = "lactose_free"

    static let meat = [
        "viande", "poulet", "dinde", "boeuf", "steak", "porc", "jambon", "lardon", "bacon", "saucisse",
        "saucisson", "chorizo", "veau", "agneau", "mouton", "canard", "lapin", "merguez", "pancetta", "gelatine",
        "rillette", "pate de campagne", "foie",
    ]
    static let seafood = [
        "poisson", "thon", "saumon", "cabillaud", "colin", "lieu", "merlu", "sardine", "maquereau", "truite",
        "crevette", "moule", "anchois", "surimi", "calamar", "seiche", "crabe", "homard", "hareng", "dorade", "bar",
    ]
    static let dairy = [
        "lait", "fromage", "yaourt", "yogourt", "skyr", "beurre", "creme", "mozzarella", "emmental", "parmesan",
        "ricotta", "feta", "comte", "cheddar", "mascarpone", "petit suisse", "whey", "caseine", "lactoserum",
    ]
    static let gluten = [
        "ble", "pate", "pates", "spaghetti", "penne", "tagliatelle", "pain", "semoule", "boulgour", "couscous",
        "farine", "seigle", "orge", "epeautre", "avoine", "tortilla", "wrap", "chapelure", "biscotte", "gnocchi",
    ]
    static let pork = ["porc", "jambon", "lardon", "bacon", "chorizo", "saucisson", "pancetta", "gelatine", "rillette"]
    static let alcohol = ["vin", "biere", "rhum", "cognac", "alcool"]
    static let shellfish = ["crevette", "moule", "homard", "crabe", "calamar", "seiche", "huitre"]

    /// Mots interdits, comparés mot à mot sur les noms normalisés.
    var forbidden: [String] {
        switch self {
        case .vegetarian: Self.meat + Self.seafood
        case .vegan: Self.meat + Self.seafood + Self.dairy + ["oeuf", "miel"]
        case .pescatarian: Self.meat
        case .halal: Self.pork + Self.alcohol
        case .kosher: Self.pork + Self.shellfish
        case .glutenFree: Self.gluten
        case .lactoseFree: Self.dairy.filter { $0 != "whey" }
        }
    }

    /// Mentions retirées avant la recherche des mots interdits (« lait de coco », « pain sans gluten »).
    var allowedMentions: [String] {
        switch self {
        case .glutenFree: ["patate", "pate d'arachide"]
        case .lactoseFree, .vegan: [
            "lait de coco", "lait d'amande", "lait de soja", "lait d'avoine", "lait de riz",
            "creme de coco", "creme de soja", "beurre de cacahuete", "beurre d'amande", "yaourt au soja", "yaourt de soja",
        ]
        case .vegetarian, .pescatarian, .halal, .kosher: []
        }
    }

    /// Qualificatifs qui rendent tout le nom acceptable (« pain sans gluten », « steak végétal »).
    var exemptingQualifiers: [String] {
        switch self {
        case .glutenFree: ["sans gluten"]
        case .lactoseFree: ["sans lactose", "vegetal", "vegetale"]
        case .vegan, .vegetarian, .pescatarian: ["vegetal", "vegetale", "vegan", "sans viande"]
        case .halal, .kosher: []
        }
    }

    /// Premier ingrédient (ou nom du plat) interdit par l'un des régimes.
    public static func violation(in meal: MealDTO, diets: [Diet]) -> (diet: Diet, food: String)? {
        let names = [meal.name] + meal.ingredients.map(\.name)
        for diet in diets {
            for name in names where diet.forbids(name) { return (diet, name) }
        }
        return nil
    }

    /// Mentions autorisées retirées d'abord (« poulet au lait de coco » reste interdit en végétarien).
    func forbids(_ name: String) -> Bool {
        var text = " " + TextNormalizer.singular(name)
            .replacingOccurrences(of: #"[^a-z0-9' ]"#, with: " ", options: .regularExpression) + " "
        if exemptingQualifiers.contains(where: { text.contains(" " + TextNormalizer.singular($0) + " ") }) { return false }
        for mention in allowedMentions {
            text = text.replacingOccurrences(of: TextNormalizer.singular(mention), with: " ")
        }
        return forbidden.contains { word in text.contains(" " + TextNormalizer.singular(word) + " ") }
    }
}
