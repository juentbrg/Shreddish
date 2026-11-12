import Foundation
import Security

/// Stockage de la clé API OpenAI (FR-019, constitution III).
protocol APIKeyStore: Sendable {
    func read() -> String?
    func save(_ key: String) throws
    func delete()
}

enum KeychainError: Error {
    case unexpectedStatus(OSStatus)
}

/// Keychain iOS, `WhenUnlockedThisDeviceOnly` : jamais sauvegardée dans iCloud (research R3).
struct KeychainStore: APIKeyStore {
    private let service = "app.shreddish.openai"
    private let account = "api-key"

    private var baseQuery: [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
    }

    func read() -> String? {
        var query = baseQuery
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
              let data = item as? Data, let key = String(data: data, encoding: .utf8), !key.isEmpty else {
            return nil
        }
        return key
    }

    func save(_ key: String) throws {
        let data = Data(key.utf8)
        let update: [String: Any] = [
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly,
        ]
        let status = SecItemUpdate(baseQuery as CFDictionary, update as CFDictionary)
        if status == errSecItemNotFound {
            var query = baseQuery
            query.merge(update) { $1 }
            let addStatus = SecItemAdd(query as CFDictionary, nil)
            guard addStatus == errSecSuccess else { throw KeychainError.unexpectedStatus(addStatus) }
        } else if status != errSecSuccess {
            throw KeychainError.unexpectedStatus(status)
        }
    }

    func delete() {
        SecItemDelete(baseQuery as CFDictionary)
    }

    /// Debug seulement (research R13) : Keychain vide → clé de dev de `Config/Secrets.xcconfig`.
    func seedDevelopmentKeyIfNeeded() {
        #if DEBUG
        guard read() == nil,
              let key = Bundle.main.object(forInfoDictionaryKey: "ShreddishOpenAIDevKey") as? String else { return }
        let trimmed = key.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !trimmed.hasPrefix("$(") else { return }
        try? save(trimmed)
        #endif
    }
}

/// Clé en mémoire : UI tests et tests app, jamais le Keychain réel.
final class InMemoryKeyStore: APIKeyStore, @unchecked Sendable {
    private let lock = NSLock()
    private var key: String?

    init(key: String? = nil) {
        self.key = key
    }

    func read() -> String? { lock.withLock { key } }
    func save(_ key: String) throws { lock.withLock { self.key = key } }
    func delete() { lock.withLock { key = nil } }
}

extension String {
    /// Clé masquée pour affichage : seuls les 4 derniers caractères visibles.
    var maskedKey: String {
        count > 4 ? "••••••••" + suffix(4) : "••••"
    }
}
