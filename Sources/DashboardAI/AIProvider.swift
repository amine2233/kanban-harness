import DashboardDomain
import DashboardOAuth
import Foundation

/// One structured-output request: a system prompt, a user prompt and the
/// JSON schema the answer must satisfy. Vendors map this onto their API.
public struct CompletionRequest: Sendable, Equatable {
    public var system: String
    public var prompt: String
    public var schema: JSONValue
    public var maxTokens: Int

    public init(system: String, prompt: String, schema: JSONValue, maxTokens: Int = 2_048) {
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

    public init(
        inputTokens: Int? = nil,
        outputTokens: Int? = nil,
        costUSD: Double? = nil,
        estimated: Bool = false
    ) {
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
        case let .notConfigured(reason): "provider not configured: \(reason)"
        case let .unavailable(reason): "provider unavailable: \(reason)"
        case let .request(reason): "provider request failed: \(reason)"
        case let .badResponse(reason): "provider returned an unusable answer: \(reason)"
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
            case let .usage(reported): usage = reported
            case let .done(json, model): return CompletionResult(json: json, usage: usage, model: model)
            }
        }
        throw AIProviderError.badResponse("stream ended without a result")
    }
}

/// Maps a kind to an implementation — and, for vendors that support it, to a
/// browser sign-in; registered by the composition root.
///
/// A kind in `disabled` is one whose registration does not happen: the guard
/// lives here rather than at each call site, so a module keeps calling
/// `register` unconditionally and a disabled provider is simply absent.
public struct AIProviderRegistry: Sendable {
    public typealias Factory = @Sendable (AIProviderConfig) -> any AIProvider
    public typealias SignInFactory = @Sendable (AIProviderConfig) throws -> any ProviderSignIn
    private var factories: [AIProviderKind: Factory] = [:]
    private var signIns: [AIProviderKind: SignInFactory] = [:]
    private let disabled: Set<AIProviderKind>

    public init(disabled: Set<AIProviderKind> = []) {
        self.disabled = disabled
    }

    public mutating func register(_ kind: AIProviderKind, _ factory: @escaping Factory) {
        guard !disabled.contains(kind) else { return }

        factories[kind] = factory
    }

    public mutating func registerSignIn(_ kind: AIProviderKind, _ factory: @escaping SignInFactory) {
        guard !disabled.contains(kind) else { return }

        signIns[kind] = factory
    }

    public func make(_ config: AIProviderConfig) throws -> any AIProvider {
        guard let factory = factories[config.kind] else {
            throw AIProviderError.notConfigured(
                disabled.contains(config.kind)
                    ? "provider kind '\(config.kind.rawValue)' is disabled for this home"
                    : "no implementation for kind '\(config.kind.rawValue)'"
            )
        }

        return factory(config)
    }

    public func signIn(for config: AIProviderConfig) throws -> any ProviderSignIn {
        guard let factory = signIns[config.kind]
        else {
            throw AIProviderError
                .notConfigured("\(config.kind.rawValue) has no browser sign-in — paste an API key")
        }

        return try factory(config)
    }

    public var kinds: [AIProviderKind] {
        Array(factories.keys)
    }

    public var signInKinds: [AIProviderKind] {
        Array(signIns.keys)
    }
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
                if escaped {
                    escaped = false
                } else if char == "\\" {
                    escaped = true
                } else if char == "\"" {
                    inString = false
                }
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
