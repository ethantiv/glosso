import Foundation

struct GitHubUpdateChecker: Sendable {
    private let session: URLSession
    private let releasesURL: URL

    init(
        session: URLSession = .shared,
        releasesURL: URL = URL(string: "https://api.github.com/repos/ethantiv/glosso/releases/latest")!
    ) {
        self.session = session
        self.releasesURL = releasesURL
    }

    /// nil means "up to date"; a throw means the check itself failed — the manual path must not report the two alike.
    func check(currentVersion: String) async throws -> (version: String, asset: URL)? {
        let release = try await fetchLatest()
        return Self.isNewer(release.version, than: currentVersion) ? release : nil
    }

    private func fetchLatest() async throws -> (version: String, asset: URL) {
        var request = URLRequest(url: releasesURL, cachePolicy: .reloadIgnoringLocalCacheData)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            throw UpdateCheckError.unreachable
        }
        let release = try JSONDecoder().decode(Release.self, from: data)
        guard let zip = release.assets.first(where: { $0.name.hasSuffix(".zip") }),
              let asset = URL(string: zip.downloadURL) else { throw UpdateCheckError.unreachable }
        return (version: Self.normalize(release.tagName), asset: asset)
    }

    static func isNewer(_ candidate: String, than current: String) -> Bool {
        normalize(current).compare(normalize(candidate), options: .numeric) == .orderedAscending
    }

    private static func normalize(_ tag: String) -> String {
        tag.hasPrefix("v") ? String(tag.dropFirst()) : tag
    }
}

private enum UpdateCheckError: Error { case unreachable }

private struct Release: Decodable {
    let tagName: String
    let assets: [Asset]
    enum CodingKeys: String, CodingKey {
        case tagName = "tag_name"
        case assets
    }

    struct Asset: Decodable {
        let name: String
        let downloadURL: String
        enum CodingKeys: String, CodingKey {
            case name
            case downloadURL = "browser_download_url"
        }
    }
}
