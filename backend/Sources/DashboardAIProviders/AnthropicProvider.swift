import DashboardAI
import DashboardDomain
import Foundation

/// Anthropic Messages API. Structured output via a forced tool call whose
/// input schema is the requested schema.
public struct AnthropicProvider: AIProvider {
    public let config: AIProviderConfig
    let http: HTTPJSON

    public init(config: AIProviderConfig) {
        self.init(config: config, http: HTTPJSON())
    }

    init(config: AIProviderConfig, http: HTTPJSON) {
        self.config = config
        self.http = http
    }

    public func complete(_ request: CompletionRequest) async throws -> CompletionResult {
        guard let key = config.apiKey else { throw AIProviderError.notConfigured("\(config.name) has no API key") }
        let base = URL(string: config.baseURL ?? "https://api.anthropic.com")!
        let body: [String: Any] = [
            "model": config.model,
            "max_tokens": request.maxTokens,
            "system": request.system,
            "messages": [["role": "user", "content": request.prompt]],
            "tools": [["name": "answer", "description": "Return the answer in the required structure.", "input_schema": request.schema.foundationObject]],
            "tool_choice": ["type": "tool", "name": "answer"],
        ]
        let response = try await http.post(
            base.appending(path: "v1/messages"),
            headers: ["x-api-key": key, "anthropic-version": "2023-06-01"],
            body: body
        )
        guard let content = response["content"] as? [[String: Any]],
              let tool = content.first(where: { $0["type"] as? String == "tool_use" }),
              let input = tool["input"], JSONSerialization.isValidJSONObject(input)
        else { throw AIProviderError.badResponse("no tool_use block in Anthropic response") }
        let usage = response["usage"] as? [String: Any]
        return CompletionResult(
            json: try JSONSerialization.data(withJSONObject: input),
            usage: CompletionUsage(inputTokens: usage?["input_tokens"] as? Int, outputTokens: usage?["output_tokens"] as? Int),
            model: response["model"] as? String ?? config.model
        )
    }
}
