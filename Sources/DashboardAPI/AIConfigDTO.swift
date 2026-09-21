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

    enum CodingKeys: String, CodingKey {
        case id, kind, name, model, pricing
        case baseURL = "base_url"
        case maxTokens = "max_tokens"
        case hasAPIKey = "has_api_key"
    }

    public init(_ provider: AIProviderConfig) {
        id = provider.id
        kind = provider.kind
        name = provider.name
        model = provider.model
        baseURL = provider.baseURL
        maxTokens = provider.maxTokens
        pricing = provider.pricing
        hasAPIKey = provider.hasAPIKey
    }

    public func encode(to encoder: any Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(kind, forKey: .kind)
        try c.encode(name, forKey: .name)
        try c.encode(model, forKey: .model)
        try c.encode(baseURL, forKey: .baseURL)
        try c.encode(maxTokens, forKey: .maxTokens)
        try c.encode(pricing, forKey: .pricing)
        try c.encode(hasAPIKey, forKey: .hasAPIKey)
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
        providers = config.providers.map(AIProviderDTO.init)
        defaultProvider = config.defaultProviderId
    }

    public func encode(to encoder: any Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(providers, forKey: .providers)
        try c.encode(defaultProvider, forKey: .defaultProvider)
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

    enum CodingKeys: String, CodingKey {
        case kind, name, model, pricing
        case baseURL = "base_url"
        case apiKey = "api_key"
        case maxTokens = "max_tokens"
    }

    public init(kind: AIProviderKind, name: String, model: String, baseURL: String? = nil, apiKey: String? = nil, maxTokens: Int? = nil, pricing: AIPricing? = nil) {
        self.kind = kind
        self.name = name
        self.model = model
        self.baseURL = baseURL
        self.apiKey = apiKey
        self.maxTokens = maxTokens
        self.pricing = pricing
    }

    /// Builds the domain value, carrying over a key the request did not touch.
    public func provider(id: String, existingKey: String?) throws -> AIProviderConfig {
        let key: String? = switch apiKey {
        case .none: existingKey
        case .some(""): nil
        case let .some(value): value
        }
        return try AIProviderConfig(id: id, kind: kind, name: name, model: model, baseURL: baseURL, apiKey: key, maxTokens: maxTokens, pricing: pricing)
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
