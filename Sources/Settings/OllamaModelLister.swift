import Foundation

enum ModelListingError: Error, Equatable {
    case unreachable
}

/// Lists installed Ollama models via `GET /api/tags`. The tags URL is derived
/// from the generate endpoint so both stay pinned to the same host.
final class OllamaModelLister: ModelListing {
    private let session: URLSession
    private let tagsURL: URL

    init(session: URLSession = .shared, generateEndpoint: URL = LLMConfig.default.endpoint) {
        self.session = session
        // .../api/generate -> .../api/tags
        self.tagsURL = generateEndpoint.deletingLastPathComponent().appendingPathComponent("tags")
    }

    func availableModels() async throws -> [String] {
        // Bypass the URL cache so "Odśwież" reflects models pulled/removed since
        // the last fetch instead of replaying a cached /api/tags body.
        let request = URLRequest(url: tagsURL, cachePolicy: .reloadIgnoringLocalCacheData)
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            throw ModelListingError.unreachable
        }
        return try JSONDecoder().decode(TagsResponse.self, from: data).models.map(\.name)
    }
}

private struct TagsResponse: Decodable {
    struct Model: Decodable { let name: String }
    let models: [Model]
}
