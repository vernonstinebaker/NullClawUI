import Foundation

// MARK: - REST Admin API Response Types

/// Response from GET /api/status
struct ApiStatusResponse: Decodable {
    let version: String
    let pid: Int
    let uptimeSeconds: Int
    let status: String
    let components: [String: ApiStatusComponent]
}

struct ApiStatusComponent: Decodable {
    let status: String
    let restartCount: Int
    let lastError: String?
}

/// Response from GET /api/config?path=...
struct ConfigValueResponse: Decodable, @unchecked Sendable {
    let path: String
    let value: AnyCodable?
}

/// Response from GET /api/models
struct ApiModelsResponse: Decodable {
    let defaultProvider: String
    let defaultModel: String?
    let providers: [ApiProviderInfo]
}

struct ApiProviderInfo: Decodable {
    let name: String
    let hasKey: Bool
}

/// Response from GET /api/channels
struct ApiChannelInfo: Decodable {
    let type: String
    let accountId: String
    let configured: Bool
    let status: String
}

/// Response from GET /api/channels/:name
struct ApiChannelDetail: Decodable {
    let type: String
    let status: String
    let accounts: [ApiChannelAccount]
}

struct ApiChannelAccount: Decodable {
    let accountId: String
    let configured: Bool
}

/// Response from GET /api/mcp
struct ApiMCPServerInfo: Decodable {
    let name: String
    let transport: String
    let command: String
}

/// Response from GET /api/mcp/:name
struct ApiMCPServerDetail: Decodable {
    let name: String
    let transport: String
    let command: String
    let args: [String]
}

// MARK: - Doctor (GET /api/doctor)

struct ApiDoctorComponent: Decodable {
    let status: String
    let restartCount: Int
    let updatedAt: String?
    let lastOk: String?
    let lastError: String?
}

struct ApiDoctorResponse: Decodable {
    let pid: Int
    let uptimeSeconds: Int
    let ready: Bool
    let components: [String: ApiDoctorComponent]
}

// MARK: - Capabilities (GET /api/capabilities)

struct ApiCapabilityChannel: Decodable {
    let key: String
    let label: String
    let enabledInBuild: Bool
    let configured: Bool
    let configuredCount: Int
}

struct ApiCapabilitiesResponse: Decodable {
    let version: String
    let activeMemoryBackend: String
    let channels: [ApiCapabilityChannel]
}

// MARK: - Models (GET /api/models/:name)

struct ApiModelDetail: Decodable {
    let name: String
    let canonicalProvider: String
    let contextInfo: String?
    let pricingInfo: String?
}

// MARK: - Skills (GET /api/skills)

struct ApiSkillInfo: Decodable {
    let name: String
    let description: String?
    let version: String?
    let enabled: Bool?
}

struct ApiSkillsResponse: Decodable {
    let outputDir: String
    let skills: [ApiSkillInfo]
}

// MARK: - Cron Run History (GET /api/cron/:id/runs)

struct ApiCronRunEntry: Decodable {
    let id: String?
    let startedAt: String?
    let finishedAt: String?
    let status: String?
    let output: String?
}

struct ApiCronRunsResponse: Decodable {
    let jobId: String
    let runs: [ApiCronRunEntry]
    let total: Int
}

// MARK: - Agent Sessions (GET /api/agent/sessions)

struct ApiAgentSessionSummary: Decodable {
    let sessionId: String
    let messageCount: Int
    let firstMessageAt: String?
    let lastMessageAt: String?
}

struct ApiAgentSessionsResponse: Decodable {
    let sessions: [ApiAgentSessionSummary]
    let total: Int
}

/// Response from POST /api/agent (blocking chat turn)
struct ApiAgentTurnResponse: Decodable {
    let session: String
    let response: String
    let turnCount: Int
}

// MARK: - Memory (GET /api/memory, GET /api/memory/:key, POST /api/memory/search)

struct ApiMemoryEntry: Decodable {
    let id: String
    let key: String
    let content: String
    let category: String?
    let timestamp: String?
    let sessionId: String?
    let score: Double?
}

struct ApiMemoryListResponse: Decodable {
    let entries: [ApiMemoryEntry]
    let total: Int?
    let backend: String?
}

struct ApiMemorySearchResponse: Decodable {
    let entries: [ApiMemoryEntry]
    let total: Int
    let backend: String?
}

struct ApiMemoryStatsResponse: Decodable {
    let backend: String
    let count: Int
}

// MARK: - History (GET /api/history, GET /api/history/:session_id)

struct ApiHistoryMessage: Decodable {
    let role: String
    let content: String
    let createdAt: String?
}

struct ApiHistorySession: Decodable {
    let sessionId: String
    let messageCount: Int
    let firstMessageAt: String?
    let lastMessageAt: String?
}

struct ApiHistoryListResponse: Decodable {
    let sessions: [ApiHistorySession]
}

struct ApiHistoryDetailResponse: Decodable {
    let sessionId: String
    let messages: [ApiHistoryMessage]
    let total: Int
    let limit: Int?
    let offset: Int?
}

// MARK: - Config Reload/Validate response

struct ApiConfigReloadResponse: Decodable {
    let valid: Bool
    let requiresRestart: Bool?
    let message: String?
}

// MARK: - AnyCodable (for config values of arbitrary type)

/// A type-erased Codable wrapper for config values that can be any JSON type.
struct AnyCodable: Codable {
    let value: Any

    init(_ value: Any) {
        self.value = value
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let bool = try? container.decode(Bool.self) {
            value = bool
        } else if let int = try? container.decode(Int.self) {
            value = int
        } else if let double = try? container.decode(Double.self) {
            value = double
        } else if let string = try? container.decode(String.self) {
            value = string
        } else if let array = try? container.decode([AnyCodable].self) {
            value = array.map(\.value)
        } else if let dict = try? container.decode([String: AnyCodable].self) {
            value = dict.mapValues { $0.value }
        } else if container.decodeNil() {
            value = NSNull()
        } else {
            throw DecodingError.dataCorruptedError(
                in: container, debugDescription: "Cannot decode AnyCodable"
            )
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch value {
        case let bool as Bool: try container.encode(bool)
        case let int as Int: try container.encode(int)
        case let double as Double: try container.encode(double)
        case let string as String: try container.encode(string)
        case let array as [Any]:
            try container.encode(array.map { AnyCodable($0) })
        case let dict as [String: Any]:
            try container.encode(dict.mapValues { AnyCodable($0) })
        case is NSNull: try container.encodeNil()
        default:
            throw EncodingError.invalidValue(
                value, EncodingError.Context(
                    codingPath: [],
                    debugDescription: "Cannot encode AnyCodable"
                )
            )
        }
    }
}

/// A type-erased Encodable wrapper for config mutation values.
struct AnyEncodable: Encodable {
    let value: Any

    init(_ value: Any) {
        self.value = value
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch value {
        case let bool as Bool: try container.encode(bool)
        case let int as Int: try container.encode(int)
        case let double as Double: try container.encode(double)
        case let string as String: try container.encode(string)
        case let array as [Any]:
            try container.encode(array.map { AnyEncodable($0) })
        case let dict as [String: Any]:
            try container.encode(dict.mapValues { AnyEncodable($0) })
        case is NSNull: try container.encodeNil()
        default:
            throw EncodingError.invalidValue(
                value, EncodingError.Context(
                    codingPath: [],
                    debugDescription: "Cannot encode AnyEncodable"
                )
            )
        }
    }
}
