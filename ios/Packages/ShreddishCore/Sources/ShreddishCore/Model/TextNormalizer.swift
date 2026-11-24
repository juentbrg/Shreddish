import Foundation

/// Normalisation des noms d'aliments : comparaison d'exclusions et clés de liste de courses.
public enum TextNormalizer {
    /// Sans tiret cadratin ni demi-cadratin : incise « a — b » → « a, b », plage « 2–3 » → « 2-3 ».
    public static func withoutDashes(_ text: String) -> String {
        guard text.contains("\u{2014}") || text.contains("\u{2013}") else { return text }
        return text
            .replacingOccurrences(of: #"\s*[\x{2014}\x{2013}]\s+"#, with: ", ", options: .regularExpression)
            .replacingOccurrences(of: #"\s+[\x{2014}\x{2013}]\s*"#, with: ", ", options: .regularExpression)
            .replacingOccurrences(of: "\u{2014}", with: "-")
            .replacingOccurrences(of: "\u{2013}", with: "-")
    }

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

    /// Mots au singulier, ponctuation retirée : « Beurre d'arachides, » → ["beurre", "d", "arachide"].
    public static func words(_ text: String) -> [String] {
        singular(String(basic(text).map { $0.isLetter || $0.isNumber ? $0 : " " })).split(separator: " ").map(String.init)
    }

    /// Les mots de `needle` se suivent dans `text` : « lait » trouvé dans « lait demi-écrémé », pas dans
    /// « laitue » ; « ail » pas dans « volaille ».
    public static func containsWords(_ text: String, _ needle: String) -> Bool {
        let haystack = words(text)
        let target = words(needle)
        guard !target.isEmpty, haystack.count >= target.count else { return false }
        return (0...(haystack.count - target.count)).contains { Array(haystack[$0..<($0 + target.count)]) == target }
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
