import DashboardAI
import DashboardDomain
import Foundation

/// Chat Completions with `response_format: json_schema` — OpenAI, Mistral,
/// Groq, LM Studio, LiteLLM and friends. `baseURL` must include the version
/// segment when the vendor has one (`https://api.openai.com/v1`).
public struct OpenAICompatibleProvider: AIProvider {
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
        guard let base = URL(string: config.baseURL ?? "https://api.openai.com/v1") else { throw AIProviderError.notConfigured("bad base url") }
        var headers: [String: String] = [:]
        if let key = config.apiKey { headers["Authorization"] = "Bearer \(key)" }
        let body: [String: Any] = [
            "model": config.model,
            "max_tokens": request.maxTokens,
            "messages": [["role": "system", "content": request.system], ["role": "user", "content": request.prompt]],
            "response_format": ["type": "json_schema", "json_schema": ["name": "answer", "strict": false, "schema": request.schema.foundationObject]],
        ]
        let response = try await http.post(base.appending(path: "chat/completions"), headers: headers, body: body)
        guard let choices = response["choices"] as? [[String: Any]],
              let message = choices.first?["message"] as? [String: Any],
              let text = message["content"] as? String,
              let json = JSONExtractor.firstObject(in: text)
        else { throw AIProviderError.badResponse("no JSON content in chat completion") }
        let usage = response["usage"] as? [String: Any]
        return CompletionResult(
            json: json,
            usage: CompletionUsage(inputTokens: usage?["prompt_tokens"] as? Int, outputTokens: usage?["completion_tokens"] as? Int),
            model: response["model"] as? String ?? config.model
        )
    }
}
