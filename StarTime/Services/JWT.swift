import Foundation

enum JWTError: Error {
    case malformed
}

/// Decodes a JWT's payload claims without verifying the signature -- safe
/// here because the token came directly from Cognito over TLS in this same
/// request; real verification happens server-side (API Gateway's Cognito
/// authorizer) on every subsequent request that carries it.
enum JWT {
    static func claims(from token: String) throws -> [String: Any] {
        let segments = token.split(separator: ".")
        guard segments.count >= 2 else { throw JWTError.malformed }

        var base64 = String(segments[1])
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        while base64.count % 4 != 0 {
            base64 += "="
        }

        guard let data = Data(base64Encoded: base64),
              let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw JWTError.malformed
        }
        return json
    }
}
