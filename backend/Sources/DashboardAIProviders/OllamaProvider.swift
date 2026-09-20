import DashboardAI
import DashboardDomain
import Foundation

/// Local Ollama (`/api/chat`, `format` = the JSON schema). No key, no cost.
public struct OllamaProvider: AIProvider {
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
        guard let base = URL(string: config.baseURL ?? "http://127.0.0.1:11434") else { throw AIProviderError.notConfigured("bad base url") }
        let body: [String: Any] = [
            "model": config.model,
            "stream": false,
            "format": request.schema.foundationObject,
            "options": ["num_predict": request.maxTokens],
            "messages": [["role": "system", "content": request.system], ["role": "user", "content": request.prompt]],
        ]
        let response = try await http.post(base.appending(path: "api/chat"), headers: [:], body: body)
        guard let message = response["message"] as? [String: Any],
              let text = message["content"] as? String,
              let json = JSONExtractor.firstObject(in: text)
        else { throw AIProviderError.badResponse("no JSON content in Ollama response") }
        return CompletionResult(
            json: json,
            usage: CompletionUsage(inputTokens: response["prompt_eval_count"] as? Int, outputTokens: response["eval_count"] as? Int),
            model: response["model"] as? String ?? config.model
        )
    }
}
