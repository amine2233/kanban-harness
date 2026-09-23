import DashboardDomain
import Foundation

/// A provider as exposed over the API: the key itself never leaves the server.
public struct AIProviderDTO: Codable, Equatable, Sendable {
    public let id: String
    public let kind: AIProviderKind
    public let name: String
    public let model: String
    public let baseURL: String?
    public let maxTokens: Int?
    public let pricing: AIPricing?
    public let hasAPIKey: Bool
    /// The registered OAuth app's client id (the secret never leaves the server).
    public let oauthClientId: String?

    enum CodingKeys: String, CodingKey {
        case id
        case kind
        case name
        case model
        case pricing
        case baseURL = "base_url"
        case maxTokens = "max_tokens"
        case hasAPIKey = "has_api_key"
        case oauthClientId = "oauth_client_id"
    }

    public init(_ provider: AIProviderConfig) {
        self.id = provider.id
        self.kind = provider.kind
        self.name = provider.name
        self.model = provider.model
        self.baseURL = provider.baseURL
        self.maxTokens = provider.maxTokens
        self.pricing = provider.pricing
        self.hasAPIKey = provider.hasAPIKey
        self.oauthClientId = provider.oauth?.clientId
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(kind, forKey: .kind)
        try container.encode(name, forKey: .name)
        try container.encode(model, forKey: .model)
        try container.encode(baseURL, forKey: .baseURL)
        try container.encode(maxTokens, forKey: .maxTokens)
        try container.encode(pricing, forKey: .pricing)
        try container.encode(hasAPIKey, forKey: .hasAPIKey)
        try container.encode(oauthClientId, forKey: .oauthClientId)
    }
}

public struct AIConfigDTO: Codable, Equatable, Sendable {
    public let providers: [AIProviderDTO]
    public let defaultProvider: String?

    enum CodingKeys: String, CodingKey {
        case providers
        case defaultProvider = "default_provider"
    }

    public init(_ config: AIConfig) {
        self.providers = config.providers.map(AIProviderDTO.init)
        self.defaultProvider = config.defaultProviderId
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(providers, forKey: .providers)
        try container.encode(defaultProvider, forKey: .defaultProvider)
    }
}

/// Create or replace a provider. `api_key` absent or `null` keeps the stored
/// key (or the environment's); an empty string clears it.
public struct UpsertAIProviderRequest: Codable, Sendable {
    public var kind: AIProviderKind
    public var name: String
    public var model: String
    public var baseURL: String?
    public var apiKey: String?
    public var maxTokens: Int?
    public var pricing: AIPricing?
    public var oauth: OAuthClientSettings?

    enum CodingKeys: String, CodingKey {
        case kind
        case name
        case model
        case pricing
        case oauth
        case baseURL = "base_url"
        case apiKey = "api_key"
        case maxTokens = "max_tokens"
    }

    public init(
        kind: AIProviderKind,
        name: String,
        model: String,
        baseURL: String? = nil,
        apiKey: String? = nil,
        maxTokens: Int? = nil,
        pricing: AIPricing? = nil,
        oauth: OAuthClientSettings? = nil
    ) {
        self.kind = kind
        self.name = name
        self.model = model
        self.baseURL = baseURL
        self.apiKey = apiKey
        self.maxTokens = maxTokens
        self.pricing = pricing
        self.oauth = oauth
    }

    /// Builds the domain value, carrying over a key the request did not touch.
    public func provider(id: String, existingKey: String?) throws -> AIProviderConfig {
        let key: String? = switch apiKey {
        case .none: existingKey
        case .some(""): nil
        case let .some(value): value
        }
        return try AIProviderConfig(
            id: id,
            kind: kind,
            name: name,
            model: model,
            baseURL: baseURL,
            apiKey: key,
            maxTokens: maxTokens,
            pricing: pricing,
            oauth: oauth
        )
    }
}

/// Where the browser must go to sign a provider in.
public struct SignInResponse: Codable, Equatable, Sendable {
    public let url: String

    public init(url: String) {
        self.url = url
    }
}

public struct SetDefaultAIProviderRequest: Codable, Sendable {
    public var providerId: String

    enum CodingKeys: String, CodingKey {
        case providerId = "provider_id"
    }

    public init(providerId: String) {
        self.providerId = providerId
    }
}
