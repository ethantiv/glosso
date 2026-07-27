import Foundation

enum ModelListingError: Error, Equatable {
    case unreachable
}

final class OllamaModelLister: ModelListing {
    private let session: URLSession
    private let endpointProvider: @Sendable () async throws -> URL

    init(session: URLSession = .shared, endpointProvider: @escaping @Sendable () async throws -> URL = { LLMConfig.default.endpoint }) {
        self.session = session
        self.endpointProvider = endpointProvider
    }

    func availableModels() async throws -> [String] {
        let tagsURL = try await endpointProvider().deletingLastPathComponent().appendingPathComponent("tags")
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
