import DashboardDomain
import Foundation

/// Scripted provider for tests and dry runs: returns canned JSON, records requests.
public actor FakeProvider: AIProvider {
    public nonisolated let config: AIProviderConfig
    private var responses: [String]
    private(set) public var requests: [CompletionRequest] = []
    private let failure: AIProviderError?

    public init(config: AIProviderConfig? = nil, responses: [String] = [], failure: AIProviderError? = nil) {
        // swiftlint:disable:next force_try
        self.config = config ?? (try! AIProviderConfig(id: "fake", kind: .ollama, name: "Fake", model: "fake"))
        self.responses = responses
        self.failure = failure
    }

    public func complete(_ request: CompletionRequest) async throws -> CompletionResult {
        requests.append(request)
        if let failure { throw failure }
        guard !responses.isEmpty else { throw AIProviderError.badResponse("fake provider has no scripted response") }
        let text = responses.removeFirst()
        guard let json = JSONExtractor.firstObject(in: text) else { throw AIProviderError.badResponse("no JSON in scripted response") }
        return CompletionResult(json: json, usage: CompletionUsage(inputTokens: 10, outputTokens: 20), model: config.model)
    }
}
