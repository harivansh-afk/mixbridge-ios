import Foundation

/// Decode JWT session token to extract user information
struct SessionTokenDecoder {

    /// Decode JWT and extract userId
    static func getUserId(from token: String) -> String? {
        print("🔍 [JWT] Decoding token to extract userId...")
        print("🔍 [JWT] Token preview: \(String(token.prefix(50)))...")

        let payload = decodeJWT(token: token)

        if let payload = payload {
            print("🔍 [JWT] Payload keys: \(payload.keys)")
            print("🔍 [JWT] Full payload: \(payload)")
        } else {
            print("❌ [JWT] Failed to decode payload")
        }

        let userId = payload?["userId"] as? String
        print("🔍 [JWT] Extracted userId: \(userId ?? "nil")")

        return userId
    }

    /// Decode JWT and extract username
    static func getUsername(from token: String) -> String? {
        let payload = decodeJWT(token: token)
        return payload?["username"] as? String
    }

    /// Decode JWT and extract avatar URL
    static func getAvatarUrl(from token: String) -> String? {
        let payload = decodeJWT(token: token)
        return payload?["avatar_url"] as? String
    }

    /// Decode JWT payload (without verification)
    /// Note: This is safe for reading user info, but don't use for authorization
    private static func decodeJWT(token: String) -> [String: Any]? {
        let segments = token.components(separatedBy: ".")
        guard segments.count == 3 else {
            print("❌ Invalid JWT format")
            return nil
        }

        let payloadSegment = segments[1]

        // Add padding if needed
        var base64 = payloadSegment
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")

        let remainder = base64.count % 4
        if remainder > 0 {
            base64 += String(repeating: "=", count: 4 - remainder)
        }

        guard let data = Data(base64Encoded: base64),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            print("❌ Failed to decode JWT payload")
            return nil
        }

        return json
    }
}
