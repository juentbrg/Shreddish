import Foundation
import Security

/// Clé API OpenAI (spec 009) : fournie au build par `Config/Secrets.xcconfig`, jamais saisie dans l'app.
protocol APIKeyStore: Sendable {
    func read() -> String?
}

/// Clé du build : `OPENAI_API_KEY` copiée dans l'Info.plist (`ShreddishOpenAIKey`).
struct BundledKeyStore: APIKeyStore {
    private let key: String?

    init(bundle: Bundle = .main) {
        let raw = (bundle.object(forInfoDictionaryKey: "ShreddishOpenAIKey") as? String)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        key = raw.isEmpty || raw.hasPrefix("$(") ? nil : raw
    }

    func read() -> String? { key }
}

/// Clé saisie dans l'app avant la spec 009 : effacée du trousseau au lancement.
enum LegacyKeychain {
    static func deleteStoredKey() {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: "app.shreddish.openai",
            kSecAttrAccount as String: "api-key",
        ]
        SecItemDelete(query as CFDictionary)
    }
}

/// Clé fixe : UI tests et tests app.
struct InMemoryKeyStore: APIKeyStore {
    let key: String?

    func read() -> String? { key }
}
