import Foundation

enum PullProgressParser {
    struct Result: Equatable {
        var progress: PullProgress
        var error: String?
        var success: Bool
    }

    private struct Line: Decodable {
        let status: String?
        let completed: Int64?
        let total: Int64?
        let error: String?
    }

    static func parse(line: String) -> Result? {
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let data = trimmed.data(using: .utf8) else { return nil }
        guard let decoded = try? JSONDecoder().decode(Line.self, from: data) else { return nil }
        let status = decoded.status ?? ""
        return Result(
            progress: PullProgress(status: status, completed: decoded.completed ?? 0, total: decoded.total ?? 0),
            error: decoded.error,
            success: status == "success"
        )
    }
}
