import Foundation

/// Decode JWT session token to extract user information
struct SessionTokenDecoder {

    /// Decode JWT and extract userId
    static func getUserId(from token: String) -> String? {
        let payload = decodeJWT(token: token)
        return payload?["userId"] as? String
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
            return nil
        }

        return json
    }
}
