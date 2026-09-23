import Crypto
import Foundation

/// RFC 7636 helpers: a high-entropy verifier and its S256 challenge.
public enum PKCE {
    public static func verifier() -> String {
        var bytes = [UInt8](repeating: 0, count: 32)
        for index in bytes.indices {
            bytes[index] = UInt8.random(in: .min ... .max)
        }
        return Data(bytes).base64URLEncoded
    }

    public static func challenge(for verifier: String) -> String {
        Data(SHA256.hash(data: Data(verifier.utf8))).base64URLEncoded
    }

    /// Random `state` for the authorization request; unguessable, URL-safe.
    public static func state() -> String {
        verifier()
    }
}

extension Data {
    /// Base64url without padding (RFC 4648 §5), as OAuth expects.
    var base64URLEncoded: String {
        base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}
