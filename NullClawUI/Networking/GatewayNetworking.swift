import Foundation

// MARK: - Gateway Errors

enum GatewayError: Error, LocalizedError {
    case invalidURL
    case httpError(statusCode: Int)
    case decodingError(underlying: Error)
    case networkError(underlying: Error)
    case jsonRPCError(code: Int, message: String)
    case unpaired
    case apiError(code: String, message: String)

    var errorDescription: String? {
        switch self {
        case .invalidURL: return "Invalid gateway URL."
        case let .httpError(code): return "HTTP error \(code)."
        case .decodingError: return "Failed to decode server response."
        case let .networkError(e): return e.localizedDescription
        case let .jsonRPCError(_, m): return "RPC error: \(m)"
        case .unpaired: return "Not paired with gateway."
        case let .apiError(code, message):
            if code == "ADMIN_API_DISABLED" {
                return "Admin API is disabled on this gateway. Add \"admin_api\": true to the gateway section of config.json and restart."
            }
            return "API error [\(code)]: \(message)"
        }
    }
}

// MARK: - Pairing Mode

enum PairingMode: Equatable {
    case required
    case notRequired
}

// MARK: - API Envelope

struct ApiEnvelope<T: Decodable>: Decodable {
    let success: Bool
    let data: T?
    let error: ApiErrorPayload?
}

struct ApiErrorPayload: Decodable {
    let code: String
    let message: String
}

struct ApiErrorEnvelope: Decodable {
    let error: ApiErrorPayload?
}

// MARK: - Shared Networking Utilites

enum GatewayNetworking {
    // MARK: Session Factories

    static func defaultSession(using config: URLSessionConfiguration? = nil) -> URLSession {
        if let cfg = config { return URLSession(configuration: cfg) }
        let cfg = URLSessionConfiguration.default
        cfg.timeoutIntervalForRequest = 30
        cfg.timeoutIntervalForResource = 300
        return URLSession(configuration: cfg)
    }

    static func sseSession(using config: URLSessionConfiguration? = nil) -> URLSession {
        if let cfg = config { return URLSession(configuration: cfg) }
        let cfg = URLSessionConfiguration.default
        cfg.timeoutIntervalForRequest = 90
        cfg.timeoutIntervalForResource = 600
        return URLSession(configuration: cfg)
    }

    // MARK: Encoder / Decoder Factories

    static func snakeCaseDecoder() -> JSONDecoder {
        let d = JSONDecoder()
        d.keyDecodingStrategy = .convertFromSnakeCase
        return d
    }

    static func snakeCaseEncoder() -> JSONEncoder {
        let e = JSONEncoder()
        e.keyEncodingStrategy = .convertToSnakeCase
        e.outputFormatting = .withoutEscapingSlashes
        return e
    }

    static func camelCaseEncoder() -> JSONEncoder {
        let e = JSONEncoder()
        e.outputFormatting = .withoutEscapingSlashes
        return e
    }

    // MARK: Request Building

    static func makeRequest(
        url: URL,
        method: String,
        token: String? = nil,
        authenticated: Bool = false
    ) throws -> URLRequest {
        guard url.scheme != nil else { throw GatewayError.invalidURL }
        var req = URLRequest(url: url)
        req.httpMethod = method
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if authenticated, let tok = token {
            req.setValue("Bearer \(tok)", forHTTPHeaderField: "Authorization")
        }
        return req
    }

    // MARK: Response Validation

    static func validate(_ response: URLResponse, data: Data? = nil, decoder: JSONDecoder? = nil) throws {
        guard let http = response as? HTTPURLResponse else { return }
        guard (200 ..< 300).contains(http.statusCode) else {
            if
                let body = data,
                let d = decoder,
                let envelope = try? d.decode(ApiErrorEnvelope.self, from: body),
                let err = envelope.error
            {
                throw GatewayError.apiError(code: err.code, message: err.message)
            }
            throw GatewayError.httpError(statusCode: http.statusCode)
        }
    }

    // MARK: Safe Decoding

    static func decode<T: Decodable>(_ type: T.Type, from data: Data, using decoder: JSONDecoder? = nil) throws -> T {
        let d = decoder ?? snakeCaseDecoder()
        do {
            return try d.decode(type, from: data)
        } catch {
            throw GatewayError.decodingError(underlying: error)
        }
    }

    // MARK: Envelope Decoding

    static func decodeEnvelope<T: Decodable>(
        _ type: T.Type,
        from data: Data,
        using decoder: JSONDecoder? = nil
    ) throws -> T {
        let d = decoder ?? snakeCaseDecoder()
        do {
            let envelope = try d.decode(ApiEnvelope<T>.self, from: data)
            if let err = envelope.error {
                throw GatewayError.apiError(code: err.code, message: err.message)
            }
            guard let result = envelope.data else {
                throw GatewayError.decodingError(underlying: DecodingError.dataCorrupted(
                    .init(codingPath: [], debugDescription: "API envelope data is null")
                ))
            }
            return result
        } catch let e as GatewayError {
            throw e
        } catch {
            throw GatewayError.decodingError(underlying: error)
        }
    }

    static func decodeArrayEnvelope<T: Decodable>(
        _ type: T.Type,
        from data: Data,
        using decoder: JSONDecoder? = nil
    ) throws -> [T] {
        let d = decoder ?? snakeCaseDecoder()
        do {
            let envelope = try d.decode(ApiEnvelope<[T]>.self, from: data)
            if let err = envelope.error {
                throw GatewayError.apiError(code: err.code, message: err.message)
            }
            return envelope.data ?? []
        } catch let e as GatewayError {
            throw e
        } catch {
            throw GatewayError.decodingError(underlying: error)
        }
    }
}
