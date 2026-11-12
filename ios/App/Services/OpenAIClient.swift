import Foundation
import ShreddishCore

enum AIConfig {
    static let baseURL = URL(string: "https://api.openai.com/v1")!
    /// Modèle par défaut ; modifiable dans Préférences (research R4).
    static let defaultModel = Preferences.defaultAIModel
}

/// Client OpenAI Responses API, sortie JSON stricte (contracts/ai-requests.md).
/// La clé n'est jamais loggée ; aucun log de requête ni de réponse.
struct OpenAIClient: Sendable {
    let transport: any AITransport

    /// Envoie une requête de génération et renvoie le texte JSON produit par le modèle.
    func generate(
        kind: ResponseSchemas.Kind, instructions: String, input: String, model: String, apiKey: String
    ) async throws(AIError) -> Data {
        var body: [String: Any] = [
            "model": model,
            "instructions": instructions,
            "input": input,
            // Pas de conservation côté OpenAI au-delà de la réponse (constitution III).
            "store": false,
            "text": [
                "format": [
                    "type": "json_schema",
                    "name": kind.rawValue,
                    "strict": true,
                    "schema": ResponseSchemas.schema(kind),
                ] as [String: Any],
            ],
        ]
        if model.hasPrefix("gpt-5") || model.hasPrefix("gpt-6") {
            // Raisonnement court : génération plus rapide (SC-003).
            body["reasoning"] = ["effort": "low"]
        }
        guard let payload = try? JSONSerialization.data(withJSONObject: body) else {
            throw .unexpected("Requête non encodable")
        }
        var request = URLRequest(url: AIConfig.baseURL.appending(path: "responses"))
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = payload

        let data = try await send(request)
        return try Self.outputText(from: data)
    }

    /// Test de clé (FR-019) : `GET /v1/models`.
    func testKey(_ apiKey: String) async throws(AIError) {
        var request = URLRequest(url: AIConfig.baseURL.appending(path: "models"))
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        _ = try await send(request)
    }

    private func send(_ request: URLRequest) async throws(AIError) -> Data {
        let data: Data
        let response: HTTPURLResponse
        do {
            (data, response) = try await transport.send(request)
        } catch let error as URLError {
            throw Self.map(error)
        } catch is CancellationError {
            throw .cancelled
        } catch {
            throw .unexpected(error.localizedDescription)
        }
        switch response.statusCode {
        case 200..<300: return data
        case 401, 403: throw .invalidKey
        case 429: throw .rateLimited
        case 500...: throw .server(status: response.statusCode)
        default: throw .unexpected(Self.apiErrorMessage(data) ?? "HTTP \(response.statusCode)")
        }
    }

    static func map(_ error: URLError) -> AIError {
        switch error.code {
        case .timedOut: .timeout
        case .notConnectedToInternet, .networkConnectionLost, .cannotFindHost, .cannotConnectToHost,
             .dataNotAllowed, .internationalRoamingOff:
            .offline
        case .cancelled: .cancelled
        default: .unexpected(error.localizedDescription)
        }
    }

    /// Extrait `output[].content[].text` du premier message ; refus ou statut incomplet → `.incomplete`.
    static func outputText(from data: Data) throws(AIError) -> Data {
        guard let root = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else {
            throw .invalidOutput("Réponse API illisible")
        }
        if let status = root["status"] as? String, status == "incomplete" || status == "failed" {
            throw .incomplete
        }
        let output = root["output"] as? [[String: Any]] ?? []
        for item in output where item["type"] as? String == "message" {
            for content in item["content"] as? [[String: Any]] ?? [] {
                switch content["type"] as? String {
                case "output_text":
                    if let text = content["text"] as? String { return Data(text.utf8) }
                case "refusal":
                    throw .incomplete
                default:
                    continue
                }
            }
        }
        throw .invalidOutput("Aucun texte dans la réponse")
    }

    private static func apiErrorMessage(_ data: Data) -> String? {
        let root = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
        return (root?["error"] as? [String: Any])?["message"] as? String
    }
}
