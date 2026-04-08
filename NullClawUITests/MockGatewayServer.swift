import Foundation
@testable import NullClawUI

/// Actor‑based mock of a NullClaw Gateway server that responds to the standard API endpoints.
/// Uses `MockURLProtocol` under the hood to intercept URLSession requests.
actor MockGatewayServer {
    private let baseURL: URL

    init(baseURL: URL = URL(string: "http://localhost:5111")!) {
        self.baseURL = baseURL
    }

    /// Registers a handler for the health endpoint (`GET /health`).
    func stubHealth(httpStatus: Int = 200) {
        let responseData = Data("{\"status\":\"healthy\"}".utf8)
        MockURLProtocol.handle(path: "/health") { _ in
            let response = HTTPURLResponse(
                url: self.baseURL.appendingPathComponent("health"),
                statusCode: httpStatus,
                httpVersion: "HTTP/1.1",
                headerFields: ["Content-Type": "application/json"]
            )
            return (responseData, response, nil)
        }
    }

    /// Registers a handler for the agent‑card endpoint (`GET /.well‑known/agent‑card.json`).
    func stubAgentCard(
        name: String = "Test Agent",
        capabilities: AgentCard.AgentCapabilities? = nil,
        httpStatus: Int = 200
    ) {
        let card = AgentCard(
            name: name,
            version: "1.0.0",
            description: nil,
            capabilities: capabilities,
            accentColor: nil
        )
        let responseData = try! JSONEncoder().encode(card)
        MockURLProtocol.handle(path: "/.well-known/agent-card.json") { _ in
            let response = HTTPURLResponse(
                url: self.baseURL.appendingPathComponent(".well-known/agent-card.json"),
                statusCode: httpStatus,
                httpVersion: "HTTP/1.1",
                headerFields: ["Content-Type": "application/json"]
            )
            return (responseData, response, nil)
        }
    }

    /// Registers a handler for the pairing endpoint (`POST /pair`).
    func stubPairing(token: String, httpStatus: Int = 200) {
        let responseData = Data("{\"token\":\"\(token)\"}".utf8)
        MockURLProtocol.handle(path: "/pair") { _ in
            let response = HTTPURLResponse(
                url: self.baseURL.appendingPathComponent("pair"),
                statusCode: httpStatus,
                httpVersion: "HTTP/1.1",
                headerFields: ["Content-Type": "application/json"]
            )
            return (responseData, response, nil)
        }
    }

    /// Registers a handler for the A2A endpoint (`POST /a2a`).
    /// Returns a JSON-RPC response wrapping a NullClawTask.
    func stubA2A(
        taskID: String = "test-task-123",
        contextID: String? = nil,
        replyText: String = "Test reply",
        httpStatus: Int = 200
    ) {
        let rpcResponse: [String: Any?] = [
            "jsonrpc": "2.0",
            "id": "1",
            "result": [
                "id": taskID,
                "context_id": contextID as Any?,
                "status": [
                    "state": "completed",
                    "message": [
                        "role": "assistant",
                        "parts": [["text": replyText]]
                    ]
                ],
                "messages": nil,
                "artifacts": nil,
                "history": nil
            ] as [String: Any?]
        ]
        let responseData = try! JSONSerialization.data(
            withJSONObject: rpcResponse.compactMapValues { $0 },
            options: .withoutEscapingSlashes
        )
        MockURLProtocol.handle(path: "/a2a") { _ in
            let response = HTTPURLResponse(
                url: self.baseURL.appendingPathComponent("a2a"),
                statusCode: httpStatus,
                httpVersion: "HTTP/1.1",
                headerFields: ["Content-Type": "application/json"]
            )
            return (responseData, response, nil)
        }
    }

    /// Registers a handler for the task status endpoint (`GET /tasks/{id}`).
    func stubTask(
        id: String,
        contextID: String? = nil,
        replyText: String = "Task reply",
        httpStatus: Int = 200
    ) {
        stubA2A(taskID: id, contextID: contextID, replyText: replyText, httpStatus: httpStatus)
    }

    /// Clears all registered handlers.
    func clear() {
        MockURLProtocol.clearHandlers()
    }
}
