import DashboardDomain
import Foundation

/// Authorization-code grant with PKCE against a standard OAuth 2 server
/// (RFC 6749 + 7636). One instance per vendor endpoint pair.
public struct OAuthCodeFlow: ProviderSignIn {
    public let authorizeURL: URL
    public let tokenURL: URL
    public let client: OAuthClientSettings
    public let scopes: [String]
    private let transport: any HTTPTransport

    public init(
        authorizeURL: URL,
        tokenURL: URL,
        client: OAuthClientSettings,
        scopes: [String],
        transport: any HTTPTransport = URLSessionTransport()
    ) {
        self.authorizeURL = authorizeURL
        self.tokenURL = tokenURL
        self.client = client
        self.scopes = scopes
        self.transport = transport
    }

    public func authorizationURL(callback: URL, state: String, codeChallenge: String) -> URL {
        var components = URLComponents(url: authorizeURL, resolvingAgainstBaseURL: false)!
        components.queryItems = (components.queryItems ?? []) + [
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "client_id", value: client.clientId),
            URLQueryItem(name: "redirect_uri", value: callback.absoluteString),
            URLQueryItem(name: "scope", value: scopes.joined(separator: " ")),
            URLQueryItem(name: "state", value: state),
            URLQueryItem(name: "code_challenge", value: codeChallenge),
            URLQueryItem(name: "code_challenge_method", value: "S256")
        ]
        return components.url!
    }

    public func exchange(code: String, codeVerifier: String, callback: URL) async throws -> Credential {
        var fields = [
            "grant_type": "authorization_code",
            "code": code,
            "code_verifier": codeVerifier,
            "redirect_uri": callback.absoluteString,
            "client_id": client.clientId
        ]
        if let secret = client.clientSecret { fields["client_secret"] = secret }
        let (status, body) = try await transport.postForm(tokenURL, fields)
        return try TokenResponse.credential(from: body, status: status)
    }

    public func refresh(_ credential: Credential) async throws -> Credential? {
        guard let refreshToken = credential.refreshToken else { throw OAuthError.notRefreshable }

        var fields = [
            "grant_type": "refresh_token",
            "refresh_token": refreshToken,
            "client_id": client.clientId
        ]
        if let secret = client.clientSecret { fields["client_secret"] = secret }
        let (status, body) = try await transport.postForm(tokenURL, fields)
        var renewed = try TokenResponse.credential(from: body, status: status)
        if renewed.refreshToken == nil { renewed.refreshToken = refreshToken }
        return renewed
    }
}
