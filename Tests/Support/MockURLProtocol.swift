import Foundation


/// One registration per test; requests can never pick up another test's response.
final class HTTPFixture: @unchecked Sendable {
    typealias Handler = (URLRequest) throws -> (HTTPURLResponse, Data)
    private let id = UUID().uuidString
    var handler: Handler? {
        get { MockURLProtocol.handlers.withLock { $0[id] } }
        set { MockURLProtocol.handlers.withLock { $0[id] = newValue } }
    }
    func configure(_ configuration: URLSessionConfiguration) {
        configuration.protocolClasses = [MockURLProtocol.self]
        configuration.httpAdditionalHeaders = [MockURLProtocol.fixtureHeader: id]
    }
    deinit { _ = MockURLProtocol.handlers.withLock { $0.removeValue(forKey: id) } }
}

final class MockURLProtocol: URLProtocol {
    static let fixtureHeader = "X-Glosso-Test-Fixture"
    final class Registry: @unchecked Sendable {
        private let lock = NSLock()
        private var values: [String: HTTPFixture.Handler] = [:]
        func withLock<T>(_ body: (inout [String: HTTPFixture.Handler]) -> T) -> T {
            lock.lock(); defer { lock.unlock() }
            return body(&values)
        }
    }
    static let handlers = Registry()
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        let id = request.value(forHTTPHeaderField: Self.fixtureHeader) ?? ""
        guard let handler = Self.handlers.withLock({ $0[id] }) else {
            client?.urlProtocol(self, didFailWithError: URLError(.resourceUnavailable))
            return
        }
        do {
            let (response, data) = try handler(request)
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch { client?.urlProtocol(self, didFailWithError: error) }
    }
    override func stopLoading() {}
}
