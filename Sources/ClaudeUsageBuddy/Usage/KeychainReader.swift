import Foundation
import Security

/// Reads the OAuth access token Claude Code stores in the login keychain.
///
/// The token is read on demand and never copied to disk by this app. macOS will
/// prompt for keychain access the first time; an ad-hoc signed binary gets a fresh
/// prompt after every rebuild because the signature changes.
enum KeychainReader {
    static let service = "Claude Code-credentials"

    struct Credentials {
        let accessToken: String
        let expiresAt: Date?

        var isExpired: Bool {
            guard let expiresAt else { return false }
            return expiresAt <= Date()
        }
    }

    enum Failure: Error {
        case notFound
        case unreadable(OSStatus)
        case malformed
    }

    static func load() throws -> Credentials {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]

        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        switch status {
        case errSecSuccess: break
        case errSecItemNotFound: throw Failure.notFound
        default: throw Failure.unreadable(status)
        }

        guard let data = item as? Data,
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { throw Failure.malformed }

        // The payload has been nested under a provider key in some versions, so
        // accept either the flat shape or one level of nesting.
        let candidates: [[String: Any]] = [json] + json.values.compactMap { $0 as? [String: Any] }

        for candidate in candidates {
            guard let token = firstString(in: candidate,
                                          keys: ["accessToken", "access_token"]) else { continue }
            return Credentials(accessToken: token, expiresAt: expiry(in: candidate))
        }
        throw Failure.malformed
    }

    private static func firstString(in dict: [String: Any], keys: [String]) -> String? {
        for k in keys {
            if let v = dict[k] as? String, !v.isEmpty { return v }
        }
        return nil
    }

    private static func expiry(in dict: [String: Any]) -> Date? {
        for key in ["expiresAt", "expires_at"] {
            if let ms = dict[key] as? Double {
                // Stored as epoch milliseconds.
                return Date(timeIntervalSince1970: ms > 1e11 ? ms / 1000 : ms)
            }
            if let s = dict[key] as? String, let d = ISO8601DateFormatter().date(from: s) {
                return d
            }
        }
        return nil
    }
}
