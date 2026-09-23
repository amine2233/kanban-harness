import DashboardAI
import DashboardAIProviders
import DashboardDomain
import DashboardOAuth
import Foundation

/// OpenRouter: one OpenAI-compatible endpoint in front of many vendors; the
/// `:free` models cost nothing. Its PKCE sign-in hands back a plain API key,
/// so a signed-in provider is indistinguishable from a pasted key afterwards.
public enum OpenRouterProvider {
    public static let apiURL = "https://openrouter.ai/api/v1"
    public static let authURL = URL(string: "https://openrouter.ai/auth")!
    public static let keysURL = URL(string: "https://openrouter.ai/api/v1/auth/keys")!

    public static func register(in registry: inout AIProviderRegistry, transport: any HTTPTransport = URLSessionTransport()) {
        registry.registerOpenAICompatible(.openrouter, baseURL: apiURL, requiresKey: "has no API key — paste one or sign in")
        registry.registerSignIn(.openrouter) { _ in OpenRouterSignIn(transport: transport) }
    }
}

/// https://openrouter.ai/docs/use-cases/oauth-pkce — no client registration,
/// no expiry: the exchange returns an API key.
public struct OpenRouterSignIn: ProviderSignIn {
    private let transport: any HTTPTransport

    public init(transport: any HTTPTransport = URLSessionTransport()) {
        self.transport = transport
    }

    public func authorizationURL(callback: URL, state: String, codeChallenge: String) -> URL {
        var components = URLComponents(url: OpenRouterProvider.authURL, resolvingAgainstBaseURL: false)!
        // OpenRouter has no `state` parameter; it is carried inside the callback URL instead.
        components.queryItems = [
            URLQueryItem(name: "callback_url", value: Self.callback(callback, state: state).absoluteString),
            URLQueryItem(name: "code_challenge", value: codeChallenge),
            URLQueryItem(name: "code_challenge_method", value: "S256"),
        ]
        return components.url!
    }

    public func exchange(code: String, codeVerifier: String, callback: URL) async throws -> Credential {
        let (status, body) = try await transport.postJSON(OpenRouterProvider.keysURL, [
            "code": code, "code_verifier": codeVerifier, "code_challenge_method": "S256",
        ])
        guard (200 ..< 300).contains(status) else { throw OAuthError.vendorRejected(status: status, body: String(decoding: body, as: UTF8.self)) }
        guard let object = try? JSONSerialization.jsonObject(with: body) as? [String: Any], let key = object["key"] as? String, !key.isEmpty else {
            throw OAuthError.malformedResponse("no key in the exchange response")
        }
        return Credential(secret: key)
    }

    public func refresh(_ credential: Credential) async throws -> Credential? { nil }

    static func callback(_ callback: URL, state: String) -> URL {
        var components = URLComponents(url: callback, resolvingAgainstBaseURL: false)!
        components.queryItems = (components.queryItems ?? []) + [URLQueryItem(name: "state", value: state)]
        return components.url!
    }
}
