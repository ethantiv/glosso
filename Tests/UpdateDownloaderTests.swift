import Foundation
import Testing
@testable import Glosso

@Suite struct UpdateDownloaderTests {
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
