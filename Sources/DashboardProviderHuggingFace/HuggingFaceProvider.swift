import AnyLanguageModel
import DashboardAI
import DashboardAIProviders
import DashboardDomain
import DashboardOAuth
import Foundation

/// Hugging Face Inference Providers: an OpenAI-compatible router in front of
/// the Hub's hosted models, paid with the account's free monthly credits.
/// Authenticates with a user token (`hf_…`) or, once an OAuth app is
/// registered on hf.co, through the browser.
public enum HuggingFaceProvider {
    public static let routerURL = "https://router.huggingface.co/v1"
    public static let authorizeURL = URL(string: "https://huggingface.co/oauth/authorize")!
    public static let tokenURL = URL(string: "https://huggingface.co/oauth/token")!
    /// `inference-api` is the scope that lets the token call the router.
    public static let scopes = ["openid", "profile", "inference-api"]

    public static func register(
        in registry: inout AIProviderRegistry,
        transport: any HTTPTransport = URLSessionTransport()
    ) {
        registry.register(.huggingface) { config in
            AnyLanguageModelProvider(config: config) {
                guard let key = config.apiKey
                else {
                    throw AIProviderError.notConfigured("\(config.name) has no token — paste one or sign in")
                }

                return OpenAILanguageModel(
                    baseURL: url(config.baseURL),
                    apiKey: key,
                    model: config.model,
                    apiVariant: .chatCompletions
                )
            }
        }
        registry.registerSignIn(.huggingface) { config in
            try signIn(for: config, transport: transport)
        }
    }

    /// The OAuth app's client id comes from the provider's `oauth` settings:
    /// Hugging Face has no public client for third-party apps.
    public static func signIn(
        for config: AIProviderConfig,
        transport: any HTTPTransport = URLSessionTransport()
    ) throws -> OAuthCodeFlow {
        guard let client = config.oauth else {
            throw AIProviderError
                .notConfigured(
                    "\(config.name): set oauth.client_id (an OAuth app from huggingface.co/settings/applications) to sign in"
                )
        }

        return OAuthCodeFlow(
            authorizeURL: authorizeURL,
            tokenURL: tokenURL,
            client: client,
            scopes: scopes,
            transport: transport
        )
    }

    static func url(_ configured: String?) -> URL {
        URL(string: configured ?? routerURL) ?? URL(string: routerURL)!
    }
}
