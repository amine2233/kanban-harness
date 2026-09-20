import Foundation

/// Which wire protocol a provider speaks. One implementation per kind covers many vendors.
public enum AIProviderKind: String, Codable, Sendable, CaseIterable {
    case anthropic
    case openaiCompatible = "openai_compatible"
    case ollama
    /// The Claude Code CLI in headless mode: uses the machine's Claude login, no API key.
    case claudeCode = "claude_code"

    /// Whether requests need an API key at all.
    public var requiresAPIKey: Bool { self == .anthropic || self == .openaiCompatible }
}

/// One configured AI provider. `apiKey` is a secret: it is persisted in the
/// config file (or supplied by the environment) and never exposed as-is.
public struct AIProviderConfig: Codable, Equatable, Sendable {

    public let id: String
    public var kind: AIProviderKind
    public var name: String
    public var model: String
    public var baseURL: String?
    public var apiKey: String?
    public var maxTokens: Int?

    enum CodingKeys: String, CodingKey {
        case id, kind, name, model
        case baseURL = "base_url"
        case apiKey = "api_key"
        case maxTokens = "max_tokens"
    }

    public init(
        id: String, kind: AIProviderKind, name: String, model: String,
        baseURL: String? = nil, apiKey: String? = nil, maxTokens: Int? = nil
    ) throws {
        guard Self.isValidId(id) else { throw DomainError.invalidProviderId(id) }
        let name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let model = model.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { throw DomainError.emptyName }
        guard !model.isEmpty else { throw DomainError.emptyModel(id) }
        if let baseURL {
            guard let url = URL(string: baseURL), let scheme = url.scheme, ["http", "https"].contains(scheme), url.host != nil else {
                throw DomainError.invalidOrigin(baseURL)
            }
        }
        if let maxTokens, maxTokens <= 0 { throw DomainError.invalidMaxTokens(maxTokens) }
        self.id = id
        self.kind = kind
        self.name = name
        self.model = model
        self.baseURL = baseURL
        self.apiKey = apiKey?.isEmpty == true ? nil : apiKey
        self.maxTokens = maxTokens
    }

    public var hasAPIKey: Bool { apiKey?.isEmpty == false }

    /// a-z, 0-9 and _, starting with a letter, max 32 chars: safe as a config key and an env var segment.
    public static func isValidId(_ id: String) -> Bool {
        guard let first = id.first, first.isLetter, first.isLowercase, id.count <= 32 else { return false }
        return id.allSatisfy { ($0.isLetter && $0.isLowercase) || $0.isNumber || $0 == "_" }
    }
}

/// The set of configured providers and which one is used by default.
public struct AIConfig: Equatable, Sendable {
    public private(set) var providers: [AIProviderConfig]
    public private(set) var defaultProviderId: String?

    public static let empty = AIConfig()

    public init(providers: [AIProviderConfig] = [], defaultProviderId: String? = nil) throws {
        self.providers = []
        self.defaultProviderId = nil
        for provider in providers {
            try upsert(provider)
        }
        if let defaultProviderId {
            try setDefault(defaultProviderId)
        }
    }

    private init() {
        providers = []
        defaultProviderId = nil
    }

    public func provider(_ id: String) -> AIProviderConfig? {
        providers.first { $0.id == id }
    }

    public var defaultProvider: AIProviderConfig? {
        defaultProviderId.flatMap(provider)
    }

    /// Adds or replaces a provider by id. The first provider becomes the default.
    public mutating func upsert(_ provider: AIProviderConfig) throws {
        if let index = providers.firstIndex(where: { $0.id == provider.id }) {
            providers[index] = provider
        } else {
            providers.append(provider)
        }
        if defaultProviderId == nil { defaultProviderId = provider.id }
    }

    public mutating func remove(_ id: String) throws {
        guard let index = providers.firstIndex(where: { $0.id == id }) else { throw DomainError.providerNotFound(id) }
        providers.remove(at: index)
        if defaultProviderId == id { defaultProviderId = providers.first?.id }
    }

    public mutating func setDefault(_ id: String) throws {
        guard provider(id) != nil else { throw DomainError.providerNotFound(id) }
        defaultProviderId = id
    }
}
