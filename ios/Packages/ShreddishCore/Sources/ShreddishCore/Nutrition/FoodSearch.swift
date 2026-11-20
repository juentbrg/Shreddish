import Foundation

/// Recherche dans la table Ciqual (spec 017) : éditeur de repas et journal rapide.
public enum FoodSearch {
    /// Aliments les plus proches du texte saisi, meilleur d'abord.
    public static func search(_ query: String, in catalog: FoodCatalog = .shared, limit: Int = 30) -> [Food] {
        guard query.trimmingCharacters(in: .whitespaces).count >= 2 else { return [] }
        return FoodMatcher.rank(query, in: catalog).prefix(limit).map(\.food)
    }
}
