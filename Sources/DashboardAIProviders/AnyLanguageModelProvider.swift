import AnyLanguageModel
import DashboardAI
import DashboardDomain
import Foundation

/// The `TicketDraft` schema as a guided-generation type. Streaming asks for
/// its `generationSchema` rather than the type so every partial parse is
/// surfaced, not only the ones where all required fields are already present.
@Generable(description: "A kanban ticket: title, description, acceptance criteria, priority, story points")
struct GeneratedTicket {
    @Guide(description: "Short imperative title, max 200 characters")
    var title: String
    @Guide(description: "What and why, in markdown, 1-3 paragraphs")
    var description: String
    @Guide(description: "Verifiable statements, 2-6 items")
    var acceptance_criteria: [String]
    @Guide(description: "One of: low, medium, high, critical", .anyOf(["low", "medium", "high", "critical"]))
    var priority: String
    @Guide(description: "Story points 0-255; omit when unsure")
    var points: Int?
    @Guide(description: "Child cards only when the idea needs several independent pieces of work; otherwise empty", .maximumCount(8))
    var subtasks: [GeneratedSubtask]
}

@Generable(description: "A child card of the ticket")
struct GeneratedSubtask {
    @Guide(description: "Short imperative title")
    var title: String
    @Guide(description: "One or two sentences: what exactly to do")
    var description: String?
    @Guide(description: "Story points 0-255; omit when unsure")
    var points: Int?
}

/// One adapter for every AnyLanguageModel backend. Adding a vendor is one
/// line in `AIProviderRegistry.standard`.
public struct AnyLanguageModelProvider: AIProvider {
    public let config: AIProviderConfig
    private let make: @Sendable () throws -> any LanguageModel

    public init(config: AIProviderConfig, model: @escaping @Sendable () throws -> any LanguageModel) {
        self.config = config
        self.make = model
    }

    public func stream(_ request: CompletionRequest) -> AsyncThrowingStream<CompletionEvent, any Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    let model = try make()
                    let session = LanguageModelSession(model: model, instructions: request.system)
                    var options = GenerationOptions()
                    options.maximumResponseTokens = request.maxTokens
                    var last: GeneratedContent?
                    var typed = ""
                    var usage = CompletionUsage()
                    for try await snapshot in session.streamResponse(to: Prompt(request.prompt), schema: GeneratedTicket.generationSchema, options: options) {
                        try Task.checkCancellation()
                        last = snapshot.rawContent
                        let text = Self.text(snapshot.rawContent)
                        if text != typed {
                            continuation.yield(.text(text.hasPrefix(typed) ? String(text.dropFirst(typed.count)) : "\n" + text))
                            typed = text
                        }
                        if let json = Self.json(snapshot.rawContent) { continuation.yield(.snapshot(json)) }
                        let reported = snapshot.usage
                        usage = CompletionUsage(
                            inputTokens: reported.input.totalTokenCount > 0 ? reported.input.totalTokenCount : nil,
                            outputTokens: reported.output.totalTokenCount > 0 ? reported.output.totalTokenCount : nil
                        )
                    }
                    guard let final = last, let json = Self.json(final) else { throw AIProviderError.badResponse("\(config.name) produced no content") }
                    continuation.yield(.usage(usage))
                    continuation.yield(.done(json: json, model: config.model))
                    continuation.finish()
                } catch is CancellationError {
                    continuation.finish(throwing: CancellationError())
                } catch let error as AIProviderError {
                    continuation.finish(throwing: error)
                } catch {
                    continuation.finish(throwing: AIProviderError.request(Self.describe(error)))
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    /// ALM falls back to a raw string when the JSON so far does not parse; our
    /// completer closes it properly so partial drafts still render.
    /// What the model has typed so far: ALM hands back either the raw string or a parsed object.
    private static func text(_ content: GeneratedContent) -> String {
        if case let .string(text) = content.kind { return text }
        return content.jsonString
    }

    private static func json(_ content: GeneratedContent) -> Data? {
        if case let .string(text) = content.kind { return JSONCompleter.complete(text) }
        return Data(content.jsonString.utf8)
    }

    static func describe(_ error: any Error) -> String {
        (error as? LocalizedError)?.errorDescription ?? String(describing: error)
    }
}
