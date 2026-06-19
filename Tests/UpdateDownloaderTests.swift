import Foundation
import Testing
@testable import Glosso

@Suite struct UpdateDownloaderTests {
    // Finder-style collision avoidance: an existing download must never be silently
    // overwritten — the name gets a "-2", "-3", … suffix until it is free.
    @Test func uniqueNameAvoidsCollisions() throws {
        let fm = FileManager.default
        let dir = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try fm.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: dir) }

        #expect(UpdateDownloader.uniqueName(base: "Glosso.zip", in: dir) == "Glosso.zip")

        try Data().write(to: dir.appendingPathComponent("Glosso.zip"))
        #expect(UpdateDownloader.uniqueName(base: "Glosso.zip", in: dir) == "Glosso-2.zip")

        try Data().write(to: dir.appendingPathComponent("Glosso-2.zip"))
        #expect(UpdateDownloader.uniqueName(base: "Glosso.zip", in: dir) == "Glosso-3.zip")
    }
}
