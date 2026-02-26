import Foundation
import Security
import CryptoKit

// MARK: - Service Account JWT authentication

struct JWTService {

    private struct ServiceAccountKey: Decodable {
        let type: String
        let project_id: String
        let private_key_id: String
        let private_key: String
        let client_email: String
        let token_uri: String
    }

    /// Fetch an access token from `ServiceAccount.json` with analytics.readonly scope.
    static func accessToken() async throws -> String {
        try await accessToken(resource: "ServiceAccount",
                              scope: "https://www.googleapis.com/auth/analytics.readonly")
    }

    /// Fetch an access token using an arbitrary bundled SA JSON resource and OAuth scope.
    static func accessToken(resource: String, scope: String) async throws -> String {
        let key = try loadServiceAccountKey(resource: resource)
        let jwt = try buildJWT(key: key, scope: scope)
        return try await exchangeJWTForToken(jwt: jwt, tokenURI: key.token_uri)
    }

    /// Fetch an access token from raw service account JSON string (user-provided, stored in Keychain).
    static func accessToken(fromJSON json: String, scope: String) async throws -> String {
        guard let data = json.data(using: .utf8) else { throw AuthError.missingServiceAccountFile }
        let key = try JSONDecoder().decode(ServiceAccountKey.self, from: data)
        let jwt = try buildJWT(key: key, scope: scope)
        return try await exchangeJWTForToken(jwt: jwt, tokenURI: key.token_uri)
    }

    // MARK: - Private

    private static func loadServiceAccountKey(resource: String = "ServiceAccount") throws -> ServiceAccountKey {
        guard let url = Bundle.main.url(forResource: resource, withExtension: "json"),
              let data = try? Data(contentsOf: url) else {
            throw AuthError.missingServiceAccountFile
        }
        return try JSONDecoder().decode(ServiceAccountKey.self, from: data)
    }

    private static func buildJWT(key: ServiceAccountKey,
                                 scope: String = "https://www.googleapis.com/auth/analytics.readonly") throws -> String {
        let now = Int(Date().timeIntervalSince1970)

        let headerJSON = ["alg": "RS256", "typ": "JWT"]
        let payloadJSON: [String: Any] = [
            "iss": key.client_email,
            "scope": scope,
            "aud": key.token_uri,
            "iat": now,
            "exp": now + 3600
        ]

        let header = try base64URLEncode(JSONSerialization.data(withJSONObject: headerJSON))
        let payload = try base64URLEncode(JSONSerialization.data(withJSONObject: payloadJSON))
        let signingInput = "\(header).\(payload)"

        let privateKey = try importRSAPrivateKey(pem: key.private_key)
        let signature = try rsaSign(data: Data(signingInput.utf8), key: privateKey)
        let sigB64 = base64URLEncode(signature)

        return "\(signingInput).\(sigB64)"
    }

    private static func exchangeJWTForToken(jwt: String, tokenURI: String) async throws -> String {
        guard let url = URL(string: tokenURI) else { throw AuthError.invalidTokenURI }

        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")

        let body = "grant_type=urn%3Aietf%3Aparams%3Aoauth%3Agrant-type%3Ajwt-bearer&assertion=\(jwt)"
        req.httpBody = body.data(using: .utf8)

        let (data, _) = try await URLSession.shared.data(for: req)

        struct TokenResponse: Decodable {
            let access_token: String
        }
        let response = try JSONDecoder().decode(TokenResponse.self, from: data)
        return response.access_token
    }

    // MARK: - RSA helpers

    private static func importRSAPrivateKey(pem: String) throws -> SecKey {
        let strippedPEM = pem
            .replacingOccurrences(of: "-----BEGIN RSA PRIVATE KEY-----", with: "")
            .replacingOccurrences(of: "-----END RSA PRIVATE KEY-----", with: "")
            .replacingOccurrences(of: "-----BEGIN PRIVATE KEY-----", with: "")
            .replacingOccurrences(of: "-----END PRIVATE KEY-----", with: "")
            .replacingOccurrences(of: "\n", with: "")
            .trimmingCharacters(in: .whitespaces)

        guard var keyData = Data(base64Encoded: strippedPEM) else {
            throw AuthError.invalidPrivateKey
        }

        // Strip PKCS#8 header if present (30 82 ... 30 0d 06 09 2a 86 48 ...)
        keyData = stripPKCS8Header(keyData) ?? keyData

        let attributes: [String: Any] = [
            kSecAttrKeyType as String: kSecAttrKeyTypeRSA,
            kSecAttrKeyClass as String: kSecAttrKeyClassPrivate,
            kSecAttrKeySizeInBits as String: 2048
        ]
        var error: Unmanaged<CFError>?
        guard let secKey = SecKeyCreateWithData(keyData as CFData, attributes as CFDictionary, &error) else {
            throw AuthError.keyImportFailed(error?.takeRetainedValue().localizedDescription ?? "unknown")
        }
        return secKey
    }

    /// Strips the PKCS#8 wrapper from Google service account keys,
    /// returning the inner PKCS#1 RSAPrivateKey DER bytes.
    private static func stripPKCS8Header(_ data: Data) -> Data? {
        let bytes = [UInt8](data)
        var offset = 0

        func readByte() -> UInt8? {
            guard offset < bytes.count else { return nil }
            defer { offset += 1 }
            return bytes[offset]
        }

        func readLength() -> Int? {
            guard let first = readByte() else { return nil }
            if first & 0x80 == 0 { return Int(first) }
            let numLenBytes = Int(first & 0x7F)
            guard numLenBytes > 0, numLenBytes <= 4 else { return nil }
            var length = 0
            for _ in 0..<numLenBytes {
                guard let b = readByte() else { return nil }
                length = (length << 8) | Int(b)
            }
            return length
        }

        // PrivateKeyInfo SEQUENCE
        guard readByte() == 0x30, readLength() != nil else { return nil }
        // version INTEGER (0x02 0x01 0x00)
        guard readByte() == 0x02, let vLen = readLength() else { return nil }
        offset += vLen
        // AlgorithmIdentifier SEQUENCE — skip entirely
        guard readByte() == 0x30, let algoLen = readLength() else { return nil }
        offset += algoLen
        // privateKey OCTET STRING — content is the PKCS#1 key
        guard readByte() == 0x04, readLength() != nil else { return nil }
        guard offset < bytes.count else { return nil }
        return Data(bytes[offset...])
    }

    private static func rsaSign(data: Data, key: SecKey) throws -> Data {
        var error: Unmanaged<CFError>?
        guard let signature = SecKeyCreateSignature(
            key,
            .rsaSignatureMessagePKCS1v15SHA256,
            data as CFData,
            &error
        ) else {
            throw AuthError.signingFailed(error?.takeRetainedValue().localizedDescription ?? "unknown")
        }
        return signature as Data
    }

    private static func base64URLEncode(_ data: Data) -> String {
        data.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    private static func base64URLEncode(_ string: String) throws -> String {
        guard let data = string.data(using: .utf8) else { throw AuthError.encodingFailed }
        return base64URLEncode(data)
    }
}

// MARK: - Errors

enum AuthError: LocalizedError {
    case missingServiceAccountFile
    case invalidPrivateKey
    case keyImportFailed(String)
    case signingFailed(String)
    case invalidTokenURI
    case encodingFailed

    var errorDescription: String? {
        switch self {
        case .missingServiceAccountFile: return "ServiceAccount.json not found in bundle."
        case .invalidPrivateKey:         return "Could not decode private key."
        case .keyImportFailed(let msg):  return "Key import failed: \(msg)"
        case .signingFailed(let msg):    return "JWT signing failed: \(msg)"
        case .invalidTokenURI:           return "Invalid token URI in service account."
        case .encodingFailed:            return "UTF-8 encoding failed."
        }
    }
}
