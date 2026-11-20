import Foundation

/// Plats lus au fil de la réponse de l'IA (spec 017, FR-1717) : la semaine apparaît pendant la génération.
public enum LiveMeals {
    /// Noms des repas déjà écrits dans un JSON partiel : valeur de « name » d'un objet placé directement
    /// dans un tableau « meals », quel que soit l'ordre des clés (les ingrédients ont aussi un « name »).
    public static func names(in partialJSON: String) -> [String] {
        var scanner = Scanner()
        for char in partialJSON { scanner.consume(char) }
        return scanner.names
    }

    /// Lecture caractère par caractère : pile des conteneurs, dernière clé, chaîne en cours.
    private struct Scanner {
        enum Container: Equatable {
            case object
            case array(key: String?)
        }

        var names: [String] = []
        private var stack: [Container] = []
        private var lastKey: String?
        private var expectingValue = false
        private var string: String?
        private var escaped = false

        mutating func consume(_ char: Character) {
            if string != nil {
                consumeInString(char)
            } else {
                consumeStructure(char)
            }
        }

        private mutating func consumeInString(_ char: Character) {
            if escaped {
                string?.append(char)
                escaped = false
            } else if char == "\\" {
                escaped = true
            } else if char == "\"" {
                finishString()
            } else {
                string?.append(char)
            }
        }

        private mutating func finishString() {
            let value = string ?? ""
            string = nil
            guard expectingValue else {
                lastKey = value
                return
            }
            if lastKey == "name", stack.suffix(2) == [.array(key: "meals"), .object] { names.append(value) }
            expectingValue = false
        }

        private mutating func consumeStructure(_ char: Character) {
            switch char {
            case "\"": string = ""
            case ":": expectingValue = true
            case ",": expectingValue = false
            case "{": push(.object)
            case "[": push(.array(key: lastKey))
            case "}", "]":
                if !stack.isEmpty { stack.removeLast() }
                expectingValue = false
            default: break
            }
        }

        private mutating func push(_ container: Container) {
            stack.append(container)
            expectingValue = false
        }
    }
}
