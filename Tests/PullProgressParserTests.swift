import Testing
@testable import Glosso

@Suite struct PullProgressParserTests {
    @Test func parsesPerLayerProgress() {
        let result = PullProgressParser.parse(line: #"{"status":"pulling abc","completed":100,"total":200}"#)
        #expect(result?.progress == PullProgress(status: "pulling abc", completed: 100, total: 200))
        #expect(result?.success == false)
        #expect(result?.error == nil)
    }

    @Test func detectsTerminalSuccess() {
        let result = PullProgressParser.parse(line: #"{"status":"success"}"#)
        #expect(result?.success == true)
        // Layers without byte counts default to 0, not nil — the UI just shows no bar.
        #expect(result?.progress == PullProgress(status: "success", completed: 0, total: 0))
    }

    @Test func surfacesServerError() {
        let result = PullProgressParser.parse(line: #"{"error":"file does not exist"}"#)
        #expect(result?.error == "file does not exist")
    }

    @Test func ignoresBlankAndNonJSON() {
        #expect(PullProgressParser.parse(line: "   ") == nil)
        #expect(PullProgressParser.parse(line: "not json at all") == nil)
    }
}
