import Foundation

/// A secret a provider authenticates with: a pasted API key, or an OAuth
/// access token with what is needed to renew it.
public struct Credential: Codable, Equatable, Sendable {
    public var secret: String
    public var refreshToken: String?
    public var expiresAt: Date?

    enum CodingKeys: String, CodingKey {
        case secret
        case refreshToken = "refresh_token"
        case expiresAt = "expires_at"
    }

    public init(secret: String, refreshToken: String? = nil, expiresAt: Date? = nil) {
        self.secret = secret
        self.refreshToken = refreshToken
        self.expiresAt = expiresAt
    }

    /// True when the token is past, or within `leeway` seconds of, its expiry.
    public func isExpiring(at now: Date = .timestamp(), leeway: TimeInterval = 60) -> Bool {
        guard let expiresAt else { return false }

        return expiresAt.timeIntervalSince(now) <= leeway
    }
}

/// What the vendor issued when the OAuth app was registered. Vendors with a
/// public sign-in flow (OpenRouter) need none of it.
public struct OAuthClientSettings: Codable, Equatable, Sendable {
    public var clientId: String
    public var clientSecret: String?

    enum CodingKeys: String, CodingKey {
        case clientId = "client_id"
        case clientSecret = "client_secret"
    }

    public init(clientId: String, clientSecret: String? = nil) {
        self.clientId = clientId
        self.clientSecret = clientSecret
    }
}
