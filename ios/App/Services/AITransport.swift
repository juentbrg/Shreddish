import Foundation

/// Envoi HTTP vers l'API IA. Deux usages : URLSession (app) et stub (UI tests, tests app).
protocol AITransport: Sendable {
    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse)
}

struct URLSessionTransport: AITransport {
    private let session: URLSession

    init(timeout: TimeInterval = 90) {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = timeout
        configuration.timeoutIntervalForResource = timeout
        configuration.urlCache = nil
        session = URLSession(configuration: configuration)
    }

    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw URLError(.badServerResponse) }
        return (data, http)
    }

    /// Réponse en flux (server-sent events) : chaque ligne `data:` transmise dès réception (spec 017).
    /// Statut HTTP en erreur : corps complet renvoyé pour lire le message d'erreur.
    func streamLines(_ request: URLRequest, onLine: (String) -> Void) async throws -> (Data?, HTTPURLResponse) {
        let (bytes, response) = try await session.bytes(for: request)
        guard let http = response as? HTTPURLResponse else { throw URLError(.badServerResponse) }
        guard (200..<300).contains(http.statusCode) else {
            var body = Data()
            for try await byte in bytes { body.append(byte) }
            return (body, http)
        }
        for try await line in bytes.lines where line.hasPrefix("data:") {
            onLine(String(line.dropFirst(5)).trimmingCharacters(in: .whitespaces))
        }
        return (nil, http)
    }
}
