import Foundation
import Testing
@testable import Glosso

@Suite struct URLDetectorTests {
    @Test func acceptsPlainHTTPSURL() {
        #expect(URLDetector.articleURL(in: "https://example.com/a?b=1")?.absoluteString == "https://example.com/a?b=1")
    }

    @Test func acceptsHTTPAndTrimsWhitespace() {
        #expect(URLDetector.articleURL(in: "  http://example.com/artykuł \n")?.host() == "example.com")
    }

    @Test func rejectsURLInsideProse() {
        #expect(URLDetector.articleURL(in: "zobacz https://example.com/a proszę") == nil)
    }

    @Test func rejectsSchemelessAddress() {
        #expect(URLDetector.articleURL(in: "www.example.com") == nil)
    }

    @Test func rejectsNonWebSchemes() {
        #expect(URLDetector.articleURL(in: "mailto:someone@example.com") == nil)
        #expect(URLDetector.articleURL(in: "ftp://example.com/file") == nil)
        #expect(URLDetector.articleURL(in: "file:///etc/hosts") == nil)
    }

    @Test func rejectsHostlessURL() {
        #expect(URLDetector.articleURL(in: "http://") == nil)
    }

    @Test func rejectsTwoURLs() {
        #expect(URLDetector.articleURL(in: "https://a.com https://b.com") == nil)
    }

    @Test func rejectsEmptyAndBlank() {
        #expect(URLDetector.articleURL(in: "") == nil)
        #expect(URLDetector.articleURL(in: "   \n") == nil)
    }
}
