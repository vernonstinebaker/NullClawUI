import Foundation

/// Mock URLProtocol that intercepts all URLSession requests for testing.
/// Configure with `MockURLProtocol.setup()` before tests and `MockURLProtocol.tearDown()` after.
final class MockURLProtocol: URLProtocol {
    /// Non‑isolated static storage for request handlers.
    /// Accesses are serialized via a DispatchQueue because Swift 6 does not allow
    /// `nonisolated(unsafe)` on mutable state.
    private static let queue = DispatchQueue(label: "MockURLProtocol.handlers")
    private nonisolated(unsafe) static var handlers: [String: (URLRequest) throws -> (Data?, URLResponse?, Error?)] =
        [:]

    /// Registers a handler for a specific URL path.
    /// The handler receives the incoming URLRequest and returns either data + response or an error.
    static func handle(
        path: String,
        handler: @escaping (URLRequest) throws -> (Data?, URLResponse?, Error?)
    ) {
        queue.sync {
            handlers[path] = handler
        }
    }

    /// Clears all registered handlers.
    static func clearHandlers() {
        queue.sync {
            handlers.removeAll()
        }
    }

    /// Sets up the URLProtocol class so URLSession uses this mock.
    /// Call this in `setUp()` or `setUpWithError()`.
    static func setup() {
        URLProtocol.registerClass(MockURLProtocol.self)
    }

    /// Tears down the mock, unregistering the protocol and clearing handlers.
    /// Call this in `tearDown()` or `tearDownWithError()`.
    static func tearDown() {
        URLProtocol.unregisterClass(MockURLProtocol.self)
        clearHandlers()
    }

    // MARK: - URLProtocol overrides

    override static func canInit(with request: URLRequest) -> Bool {
        // Intercept all requests; the handler decides what to do.
        true
    }

    override static func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        guard let url = request.url else {
            client?.urlProtocol(self, didFailWithError: URLError(.badURL))
            return
        }

        let path = url.path
        let handler = Self.queue.sync { Self.handlers[path] }

        guard let handler else {
            // No handler registered for this path → 404.
            let response = HTTPURLResponse(
                url: url,
                statusCode: 404,
                httpVersion: "HTTP/1.1",
                headerFields: ["Content-Type": "application/json"]
            )!
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: Data())
            client?.urlProtocolDidFinishLoading(self)
            return
        }

        do {
            let (data, response, error) = try handler(request)
            if let error {
                client?.urlProtocol(self, didFailWithError: error)
                return
            }
            if let response {
                client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            }
            if let data {
                client?.urlProtocol(self, didLoad: data)
            }
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {
        // No‑op for this mock.
    }
}
