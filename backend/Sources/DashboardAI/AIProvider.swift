import DashboardDomain
import Foundation

/// One structured-output request: a system prompt, a user prompt and the
/// JSON schema the answer must satisfy. Vendors map this onto their API.
public struct CompletionRequest: Sendable, Equatable {
    public var system: String
    public var prompt: String
    public var schema: JSONValue
    public var maxTokens: Int

    public init(system: String, prompt: String, schema: JSONValue, maxTokens: Int = 2048) {
        self.system = system
        self.prompt = prompt
        self.schema = schema
        self.maxTokens = maxTokens
    }
}

public struct CompletionUsage: Sendable, Equatable, Codable {
    public var inputTokens: Int?
    public var outputTokens: Int?
    public var costUSD: Double?
    /// True when `costUSD` was computed from the provider's pricing rather than reported by the vendor.
    public var estimated: Bool

    enum CodingKeys: String, CodingKey {
        case inputTokens = "input_tokens"
        case outputTokens = "output_tokens"
        case costUSD = "cost_usd"
        case estimated
    }

    public init(inputTokens: Int? = nil, outputTokens: Int? = nil, costUSD: Double? = nil, estimated: Bool = false) {
        self.inputTokens = inputTokens
        self.outputTokens = outputTokens
        self.costUSD = costUSD
        self.estimated = estimated
    }
}

/// What a provider emits while answering. `snapshot` carries the JSON produced
/// so far, completed into a parseable object; `done` carries the final JSON.
public enum CompletionEvent: Sendable, Equatable {
    /// Raw model output appended since the previous `text` event, for logs.
    case text(String)
    /// The JSON produced so far, completed into a parseable object.
    case snapshot(Data)
    case usage(CompletionUsage)
    case done(json: Data, model: String)
}

/// The final answer: the JSON the model produced plus usage.
public struct CompletionResult: Sendable, Equatable {
    public var json: Data
    public var usage: CompletionUsage
    public var model: String

    public init(json: Data, usage: CompletionUsage = .init(), model: String) {
        self.json = json
        self.usage = usage
        self.model = model
    }
}

public enum AIProviderError: Error, Equatable, Sendable {
    case notConfigured(String)
    case unavailable(String)
    case request(String)
    case badResponse(String)
}

extension AIProviderError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case let .notConfigured(m): "provider not configured: \(m)"
        case let .unavailable(m): "provider unavailable: \(m)"
        case let .request(m): "provider request failed: \(m)"
        case let .badResponse(m): "provider returned an unusable answer: \(m)"
        }
    }
}

/// What every vendor implements: a stream of events ending with `.done`.
public protocol AIProvider: Sendable {
    var config: AIProviderConfig { get }
    func stream(_ request: CompletionRequest) -> AsyncThrowingStream<CompletionEvent, any Error>
}

extension AIProvider {
    /// Folds the stream into its final result.
    public func complete(_ request: CompletionRequest) async throws -> CompletionResult {
        var usage = CompletionUsage()
        for try await event in stream(request) {
            switch event {
            case .text, .snapshot: continue
            case let .usage(u): usage = u
            case let .done(json, model): return CompletionResult(json: json, usage: usage, model: model)
            }
        }
        throw AIProviderError.badResponse("stream ended without a result")
    }
}

/// Maps a kind to an implementation; registered by the composition root.
public struct AIProviderRegistry: Sendable {
    public typealias Factory = @Sendable (AIProviderConfig) -> any AIProvider
    private var factories: [AIProviderKind: Factory] = [:]

    public init() {}

    public mutating func register(_ kind: AIProviderKind, _ factory: @escaping Factory) {
        factories[kind] = factory
    }

    public func make(_ config: AIProviderConfig) throws -> any AIProvider {
        guard let factory = factories[config.kind] else { throw AIProviderError.notConfigured("no implementation for kind '\(config.kind.rawValue)'") }
        return factory(config)
    }

    public var kinds: [AIProviderKind] { Array(factories.keys) }
}

/// Pulls the first JSON object out of model text: tolerates prose and ``` fences.
public enum JSONExtractor {
    public static func firstObject(in text: String) -> Data? {
        guard let start = text.firstIndex(of: "{") else { return nil }
        var depth = 0
        var inString = false
        var escaped = false
        var index = start
        while index < text.endIndex {
            let char = text[index]
            if inString {
                if escaped { escaped = false } else if char == "\\" { escaped = true } else if char == "\"" { inString = false }
            } else if char == "\"" {
                inString = true
            } else if char == "{" {
                depth += 1
            } else if char == "}" {
                depth -= 1
                if depth == 0 { return Data(text[start ... index].utf8) }
            }
            index = text.index(after: index)
        }
        return nil
    }
}
