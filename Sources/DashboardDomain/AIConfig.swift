import Foundation

/// Which wire protocol a provider speaks. One implementation per kind covers many vendors.
public enum AIProviderKind: String, Codable, Sendable, CaseIterable {
    /// Apple's on-device Foundation Model (macOS 26+): free, private, no key.
    case apple
    case anthropic
    /// OpenAI and every OpenAI-compatible endpoint (Mistral, Groq, LM Studio, LiteLLM…) via `base_url`.
    case openai
    case gemini
    case ollama
    /// Hugging Face Inference Providers (OpenAI-compatible router): free monthly credits with a token.
    case huggingface
    /// The Claude Code CLI in headless mode: uses the machine's Claude login, no API key.
    case claudeCode = "claude_code"

    /// Whether requests need an API key at all.
    /// No bill per draft: local runtimes, or Hugging Face's free credits (set `pricing` if you pay).
    public var isFree: Bool { self == .apple || self == .ollama || self == .huggingface }

    public var requiresAPIKey: Bool {
        switch self {
        case .anthropic, .openai, .gemini, .huggingface: true
        case .apple, .ollama, .claudeCode: false
        }
    }

    /// Accepts the pre-0.2 spelling from existing config files.
    public init?(configValue: String) {
        if let kind = AIProviderKind(rawValue: configValue) { self = kind } else if configValue == "openai_compatible" { self = .openai } else { return nil }
    }
}

/// One configured AI provider. `apiKey` is a secret: it is persisted in the
/// USD per million tokens, used to price a draft when the vendor does not report a cost.
public struct AIPricing: Codable, Equatable, Sendable {
    public var inputPerMillion: Double
    public var outputPerMillion: Double

    enum CodingKeys: String, CodingKey {
        case inputPerMillion = "input_per_million"
        case outputPerMillion = "output_per_million"
    }

    public init(inputPerMillion: Double, outputPerMillion: Double) throws {
        guard inputPerMillion >= 0, outputPerMillion >= 0, inputPerMillion.isFinite, outputPerMillion.isFinite else {
            throw DomainError.invalidPricing
        }
        self.inputPerMillion = inputPerMillion
        self.outputPerMillion = outputPerMillion
    }

    public func cost(inputTokens: Int?, outputTokens: Int?) -> Double {
        Double(inputTokens ?? 0) / 1_000_000 * inputPerMillion + Double(outputTokens ?? 0) / 1_000_000 * outputPerMillion
    }
}

/// config file (or supplied by the environment) and never exposed as-is.
public struct AIProviderConfig: Codable, Equatable, Sendable {

    public let id: String
    public var kind: AIProviderKind
    public var name: String
    public var model: String
    public var baseURL: String?
    public var apiKey: String?
    public var maxTokens: Int?
    public var pricing: AIPricing?

    enum CodingKeys: String, CodingKey {
        case id, kind, name, model, pricing
        case baseURL = "base_url"
        case apiKey = "api_key"
        case maxTokens = "max_tokens"
    }

    public init(
        id: String, kind: AIProviderKind, name: String, model: String,
        baseURL: String? = nil, apiKey: String? = nil, maxTokens: Int? = nil, pricing: AIPricing? = nil
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
        self.pricing = pricing
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
