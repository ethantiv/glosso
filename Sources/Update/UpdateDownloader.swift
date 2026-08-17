import AppKit
import Foundation

enum UpdateDownloader {
    static func download(_ asset: URL, session: URLSession = .shared) async {
        // A bare return here was indistinguishable from success — the user waited for a download that never came.
        guard let downloads = try? FileManager.default.url(
            for: .downloadsDirectory, in: .userDomainMask, appropriateFor: nil, create: false
        ) else { return reportFailure() }
        guard let (temp, response) = try? await session.download(from: asset),
              (response as? HTTPURLResponse).map({ (200..<300).contains($0.statusCode) }) ?? false
        else { return reportFailure() }

        let base = asset.lastPathComponent.isEmpty ? "Glosso.zip" : asset.lastPathComponent
        let destination = downloads.appendingPathComponent(uniqueName(base: base, in: downloads))
        guard (try? FileManager.default.moveItem(at: temp, to: destination)) != nil else { return reportFailure() }

        await MainActor.run { NSWorkspace.shared.activateFileViewerSelecting([destination]) }
    }

    private static func reportFailure() {
        SystemUserNotifier.post(loc("Nie udało się pobrać aktualizacji. Sprawdź połączenie i spróbuj ponownie.",
                                    "Couldn't download the update. Check your connection and try again."))
    }

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
