import Foundation

/// Normalisation des noms d'aliments : comparaison d'exclusions et clés de liste de courses.
public enum TextNormalizer {
    /// Minuscules, sans accents ni ligatures, trim, espaces multiples réduits.
    public static func basic(_ text: String) -> String {
        text
            .replacingOccurrences(of: "œ", with: "oe")
            .replacingOccurrences(of: "Œ", with: "oe")
            .replacingOccurrences(of: "æ", with: "ae")
            .replacingOccurrences(of: "Æ", with: "ae")
            .replacingOccurrences(of: "’", with: "'")
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "fr_FR"))
            .lowercased()
            .split(whereSeparator: \.isWhitespace)
            .joined(separator: " ")
    }

    /// `basic` puis singulier simple par mot de plus de 3 lettres : « ux » → « u », « s » final retiré
    /// (sauf « ss »). Pas de grammaire complète : il suffit que deux formes d'un même aliment
    /// donnent la même clé (research R11).
    public static func singular(_ text: String) -> String {
        basic(text)
            .split(separator: " ")
            .map { word -> String in
                let word = String(word)
                guard word.count > 3 else { return word }
                if word.hasSuffix("ux") { return String(word.dropLast()) }
                if word.hasSuffix("s"), !word.hasSuffix("ss") { return String(word.dropLast()) }
                return word
            }
            .joined(separator: " ")
    }
}
