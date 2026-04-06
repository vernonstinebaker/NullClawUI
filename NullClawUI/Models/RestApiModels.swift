import Foundation

// MARK: - REST Admin API Response Types

/// Response from GET /api/status
struct ApiStatusResponse: Decodable, Sendable {
    let version: String
    let pid: Int
    let uptimeSeconds: Int
    let status: String
    let components: [String: ApiStatusComponent]
}

struct ApiStatusComponent: Decodable, Sendable {
    let status: String
    let restartCount: Int
    let lastError: String?
}

/// Response from GET /api/config?path=...
struct ConfigValueResponse: Decodable {
    let path: String
    let value: AnyCodable?
}

/// Response from GET /api/models
struct ApiModelsResponse: Decodable, Sendable {
    let defaultProvider: String
    let defaultModel: String?
    let providers: [ApiProviderInfo]
}

struct ApiProviderInfo: Decodable, Sendable {
    let name: String
    let hasKey: Bool
}

/// Response from GET /api/channels
struct ApiChannelInfo: Decodable, Sendable {
    let type: String
    let accountId: String
    let configured: Bool
    let status: String
}

/// Response from GET /api/channels/:name
struct ApiChannelDetail: Decodable, Sendable {
    let type: String
    let status: String
    let accounts: [ApiChannelAccount]
}

struct ApiChannelAccount: Decodable, Sendable {
    let accountId: String
    let configured: Bool
}

/// Response from GET /api/mcp
struct ApiMCPServerInfo: Decodable, Sendable {
    let name: String
    let transport: String
    let command: String
}

/// Response from GET /api/mcp/:name
struct ApiMCPServerDetail: Decodable, Sendable {
    let name: String
    let transport: String
    let command: String
    let args: [String]
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
            value = array.map { $0.value }
        } else if let dict = try? container.decode([String: AnyCodable].self) {
            value = dict.mapValues { $0.value }
        } else if container.decodeNil() {
            value = NSNull()
        } else {
            throw DecodingError.dataCorruptedError(
                in: container, debugDescription: "Cannot decode AnyCodable")
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
                value, EncodingError.Context(codingPath: [],
                    debugDescription: "Cannot encode AnyCodable"))
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
                value, EncodingError.Context(codingPath: [],
                    debugDescription: "Cannot encode AnyEncodable"))
        }
    }
}
