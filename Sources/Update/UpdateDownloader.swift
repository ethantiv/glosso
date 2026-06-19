import AppKit
import Foundation

/// Fetches a release `.zip` straight into ~/Downloads and reveals it in Finder.
/// A URLSession download carries no quarantine flag (the browser, not us, applies
/// it), so the user who updates through Glosso skips the Gatekeeper "Open Anyway"
/// dance. Stops short of installing — the manual drag-over keeps the TCC grant.
enum UpdateDownloader {
    static func download(_ asset: URL, session: URLSession = .shared) async {
        guard let downloads = try? FileManager.default.url(
            for: .downloadsDirectory, in: .userDomainMask, appropriateFor: nil, create: false
        ) else { return }
        guard let (temp, _) = try? await session.download(from: asset) else { return }

        let base = asset.lastPathComponent.isEmpty ? "Glosso.zip" : asset.lastPathComponent
        let destination = downloads.appendingPathComponent(uniqueName(base: base, in: downloads))
        guard (try? FileManager.default.moveItem(at: temp, to: destination)) != nil else { return }

        await MainActor.run { NSWorkspace.shared.activateFileViewerSelecting([destination]) }
    }

    /// Finder-style collision avoidance: "Glosso.zip" → "Glosso-2.zip" → … so a
    /// previous download is never silently overwritten.
    static func uniqueName(base: String, in directory: URL, fileManager: FileManager = .default) -> String {
        guard fileManager.fileExists(atPath: directory.appendingPathComponent(base).path) else { return base }
        let ext = (base as NSString).pathExtension
        let stem = (base as NSString).deletingPathExtension
        var n = 2
        while true {
            let candidate = ext.isEmpty ? "\(stem)-\(n)" : "\(stem)-\(n).\(ext)"
            if !fileManager.fileExists(atPath: directory.appendingPathComponent(candidate).path) {
                return candidate
            }
            n += 1
        }
    }
}
