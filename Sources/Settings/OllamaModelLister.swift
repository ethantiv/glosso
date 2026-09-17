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

    /// Models resident in memory right now (`/api/ps`), with the moment Ollama plans to unload each.
    func loadedModels() async throws -> [LoadedModel] {
        let psURL = try await endpointProvider().deletingLastPathComponent().appendingPathComponent("ps")
        let request = URLRequest(url: psURL, cachePolicy: .reloadIgnoringLocalCacheData)
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            throw ModelListingError.unreachable
        }
        return try JSONDecoder().decode(PSResponse.self, from: data).models.map {
            LoadedModel(name: $0.name, expiresAt: $0.expires_at.flatMap(Self.parseDate))
        }
    }

    /// Ollama stamps 5–6 fractional digits, which ISO8601DateFormatter rejects — the seconds are precision enough.
    nonisolated static func parseDate(_ raw: String) -> Date? {
        ISO8601DateFormatter().date(from: raw.replacing(/\.\d+/, with: ""))
    }
}

struct LoadedModel: Equatable, Sendable {
    let name: String
    let expiresAt: Date?
}

private struct PSResponse: Decodable {
    struct Model: Decodable { let name: String; let expires_at: String? }
    let models: [Model]
}

private struct TagsResponse: Decodable {
    struct Model: Decodable { let name: String }
    let models: [Model]
}
