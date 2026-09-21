import DashboardDomain
import Foundation

/// A vendor's browser sign-in, reduced to the three steps the dashboard drives:
/// where to send the user, how to turn the returned code into a credential,
/// and how to renew it. `OAuthCodeFlow` covers standard OAuth 2 servers;
/// vendors with a custom exchange (OpenRouter) implement it directly.
public protocol ProviderSignIn: Sendable {
    /// `callback` is the loopback URL the server listens on for the redirect.
    func authorizationURL(callback: URL, state: String, codeChallenge: String) -> URL
    func exchange(code: String, codeVerifier: String, callback: URL) async throws -> Credential
    /// Nil when the credential never expires.
    func refresh(_ credential: Credential) async throws -> Credential?
}

public enum OAuthError: Error, Equatable, Sendable {
    case unknownState
    case vendorRejected(status: Int, body: String)
    case malformedResponse(String)
    case notRefreshable

    public var message: String {
        switch self {
        case .unknownState: "sign-in session expired or unknown — start again"
        case let .vendorRejected(status, body): "the vendor refused the exchange (HTTP \(status)): \(body.prefix(300))"
        case let .malformedResponse(detail): "unexpected sign-in response: \(detail)"
        case .notRefreshable: "this credential cannot be refreshed — sign in again"
        }
    }
}
