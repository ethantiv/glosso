import Foundation

/// Polls the public GitHub Releases API for a build newer than the running one.
/// Deliberately minimal (no Sparkle/appcast): it returns the `.zip` asset's direct
/// download URL so the app can fetch it straight into ~/Downloads, and the user
/// installs manually. Stable code signing keeps the Accessibility grant across that
/// manual replace, so this is all the update path needs.
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

    /// The latest release if it is newer than `currentVersion`, else nil. Every
    /// failure — offline, non-200, malformed JSON, or a release with no `.zip`
    /// asset — resolves to nil: an update check must never raise an error in the
    /// user's face, and with no asset there is nothing to download.
    func availableUpdate(currentVersion: String) async -> (version: String, asset: URL)? {
        guard let release = try? await fetchLatest(),
              Self.isNewer(release.version, than: currentVersion) else { return nil }
        return release
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

    /// Numeric compare after dropping a leading "v" so 1.10 sorts above 1.9 — a
    /// plain string compare would order them backwards.
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
