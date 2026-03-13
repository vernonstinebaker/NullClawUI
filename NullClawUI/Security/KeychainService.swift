import Foundation
import Security

/// Thread-safe Keychain helper. Credentials are keyed by normalized gateway URL.
/// Item accessibility: kSecAttrAccessibleWhenUnlockedThisDeviceOnly (never migrates to another device).
enum KeychainService {

    private static let servicePrefix = "nullclaw.token"

    // MARK: - Public API

    static func storeToken(_ token: String, for gatewayURL: String) throws {
        let key = itemKey(for: gatewayURL)
        // Delete any existing item first to avoid duplicate-item errors.
        delete(key: key)

        guard let data = token.data(using: .utf8) else { throw KeychainError.encodingFailure }
        let query: [CFString: Any] = [
            kSecClass:               kSecClassGenericPassword,
            kSecAttrService:         key,
            kSecAttrAccessible:      kSecAttrAccessibleWhenUnlockedThisDeviceOnly,
            kSecValueData:           data
        ]
        let status = SecItemAdd(query as CFDictionary, nil)
        guard status == errSecSuccess else { throw KeychainError.unexpectedStatus(status) }
    }

    static func retrieveToken(for gatewayURL: String) throws -> String? {
        let key = itemKey(for: gatewayURL)
        let query: [CFString: Any] = [
            kSecClass:            kSecClassGenericPassword,
            kSecAttrService:      key,
            kSecReturnData:       true,
            kSecMatchLimit:       kSecMatchLimitOne
        ]
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess else { throw KeychainError.unexpectedStatus(status) }
        guard let data = result as? Data, let token = String(data: data, encoding: .utf8) else {
            throw KeychainError.encodingFailure
        }
        return token
    }

    @discardableResult
    static func deleteToken(for gatewayURL: String) -> Bool {
        delete(key: itemKey(for: gatewayURL))
    }

    // MARK: - Helpers

    private static func itemKey(for gatewayURL: String) -> String {
        // Normalize: strip trailing slash, lowercase scheme+host.
        let normalized = gatewayURL.trimmingCharacters(in: .init(charactersIn: "/")).lowercased()
        return "\(servicePrefix).\(normalized)"
    }

    @discardableResult
    private static func delete(key: String) -> Bool {
        let query: [CFString: Any] = [
            kSecClass:        kSecClassGenericPassword,
            kSecAttrService:  key
        ]
        return SecItemDelete(query as CFDictionary) == errSecSuccess
    }
}

// MARK: - Errors

enum KeychainError: Error, LocalizedError {
    case encodingFailure
    case unexpectedStatus(OSStatus)

    var errorDescription: String? {
        switch self {
        case .encodingFailure:          return "Failed to encode/decode token data."
        case .unexpectedStatus(let s):  return "Keychain call failed with status \(s)."
        }
    }
}
