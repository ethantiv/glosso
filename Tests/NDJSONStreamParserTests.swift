import Testing
@testable import TranslatorMenuBar

@Suite struct NDJSONStreamParserTests {
    @Test func parsesTokenLine() throws {
        let chunk = try #require(NDJSONStreamParser.parse(line: #"{"model":"m","response":"Hel","done":false}"#))
        #expect(chunk.response == "Hel")
        #expect(chunk.done == false)
        #expect(chunk.doneReason == nil)
    }

    @Test func parsesDoneLine() throws {
        let chunk = try #require(NDJSONStreamParser.parse(line: #"{"response":"","done":true,"done_reason":"stop"}"#))
        #expect(chunk.response == "")
        #expect(chunk.done == true)
        #expect(chunk.doneReason == "stop")
    }

    @Test func parsesErrorLine() throws {
        let chunk = try #require(NDJSONStreamParser.parse(line: #"{"error":"model 'gemma4:26b-mlx' not found"}"#))
        #expect(chunk.error == "model 'gemma4:26b-mlx' not found")
        #expect(chunk.done == false)
        #expect(chunk.response == nil)
    }

    @Test func emptyLineReturnsNil() {
        #expect(NDJSONStreamParser.parse(line: "") == nil)
        #expect(NDJSONStreamParser.parse(line: "   ") == nil)
        #expect(NDJSONStreamParser.parse(line: "\n") == nil)
    }

    @Test func garbageReturnsNil() {
        #expect(NDJSONStreamParser.parse(line: "not json") == nil)
        #expect(NDJSONStreamParser.parse(line: "{ broken") == nil)
    }
}
