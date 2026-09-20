import DashboardDomain
import Foundation

/// Scripted provider for tests and dry runs: streams canned JSON in chunks, records requests.
public actor FakeProvider: AIProvider {
    public nonisolated let config: AIProviderConfig
    private var responses: [String]
    private(set) public var requests: [CompletionRequest] = []
    private let failure: AIProviderError?
    private let chunkSize: Int

    public init(config: AIProviderConfig? = nil, responses: [String] = [], failure: AIProviderError? = nil, chunkSize: Int = 12) {
        // swiftlint:disable:next force_try
        self.config = config ?? (try! AIProviderConfig(id: "fake", kind: .ollama, name: "Fake", model: "fake"))
        self.responses = responses
        self.failure = failure
        self.chunkSize = chunkSize
    }

    private func next(_ request: CompletionRequest) throws -> String {
        requests.append(request)
        if let failure { throw failure }
        guard !responses.isEmpty else { throw AIProviderError.badResponse("fake provider has no scripted response") }
        return responses.removeFirst()
    }

    public nonisolated func stream(_ request: CompletionRequest) -> AsyncThrowingStream<CompletionEvent, any Error> {
        AsyncThrowingStream { continuation in
            Task {
                do {
                    let text = try await self.next(request)
                    var buffer = ""
                    for chunk in text.chunked(self.chunkSize) {
                        buffer += chunk
                        continuation.yield(.text(chunk))
                        if let snapshot = JSONCompleter.complete(buffer) { continuation.yield(.snapshot(snapshot)) }
                    }
                    guard let json = JSONExtractor.firstObject(in: text) else { throw AIProviderError.badResponse("no JSON in scripted response") }
                    continuation.yield(.usage(CompletionUsage(inputTokens: 10, outputTokens: 20)))
                    continuation.yield(.done(json: json, model: self.config.model))
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
        }
    }
}

extension String {
    func chunked(_ size: Int) -> [String] {
        var chunks: [String] = []
        var index = startIndex
        while index < endIndex {
            let end = self.index(index, offsetBy: size, limitedBy: endIndex) ?? endIndex
            chunks.append(String(self[index ..< end]))
            index = end
        }
        return chunks
    }
}
