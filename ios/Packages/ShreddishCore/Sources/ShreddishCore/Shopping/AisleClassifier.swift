import Foundation

/// Rayon déduit du nom de l'ingrédient quand un mot-clé ne laisse pas de doute ; corrige le rayon
/// choisi par l'IA (ex. « yaourt nature » rangé en fruits et légumes).
public enum AisleClassifier {
    /// Rayon corrigé, ou celui de l'IA si aucun mot-clé ne tranche.
    public static func corrected(name: String, aisle: Aisle) -> Aisle {
        inferred(name) ?? aisle
    }

    /// Rayon certain d'après le nom ; `nil` si ambigu.
    public static func inferred(_ name: String) -> Aisle? {
        let words = " " + TextNormalizer.singular(name).replacingOccurrences(of: "'", with: " ") + " "
        func has(_ keywords: [String]) -> Bool { keywords.contains { words.contains(" \($0) ") } }
        if has(frozen) { return .surgeles }
        if has(pantry) { return .epicerie }
        if has(dairy) { return .cremerie }
        if has(meatFish) { return .viandePoisson }
        if has(bakery) { return .boulangerie }
        return nil
    }

    private static let frozen = ["surgele", "surgelee", "congele", "congelee"]
    /// Conserves, produits secs et œufs (non réfrigérés en France), même avec un mot-clé d'un autre rayon (« thon en boîte »).
    private static let pantry = [
        "boite", "conserve", "au naturel", "lait de coco", "lait d amande", "lait de soja", "lait d avoine",
        "beurre de cacahuete", "beurre d arachide", "creme de coco", "bouillon", "sauce", "oeuf",
    ]
    private static let dairy = [
        "yaourt", "yogourt", "yoghourt", "fromage", "skyr", "lait", "beurre", "creme fraiche", "creme",
        "mozzarella", "feta", "emmental", "comte", "parmesan", "ricotta", "cottage", "faisselle",
        "petit suisse", "kefir",
    ]
    private static let meatFish = [
        "poulet", "dinde", "boeuf", "porc", "veau", "agneau", "jambon", "lardon", "steak", "viande",
        "hache", "hachee", "saumon", "cabillaud", "colin", "merlu", "lieu", "truite", "crevette", "filet de poisson",
        "poisson",
    ]
    private static let bakery = ["pain", "baguette", "brioche"]
}
