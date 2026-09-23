import AnyLanguageModel
import DashboardAI
import DashboardDomain
import Foundation

extension AIProviderRegistry {
    /// Every vendor this build ships. Cloud/local backends go through
    /// AnyLanguageModel; Claude Code is our own CLI-backed implementation.
    public static func standard(claudeExecutable: String = "claude", disabled: Set<AIProviderKind> = []) -> AIProviderRegistry {
        var registry = AIProviderRegistry(disabled: disabled)
        registry.register(.apple) { config in
            AnyLanguageModelProvider(config: config) {
                #if canImport(FoundationModels)
                if #available(macOS 26.0, *) {
                    let model = SystemLanguageModel.default
                    if case let .unavailable(reason) = model.availability {
                        throw AIProviderError.unavailable("Apple Intelligence model: \(reason)")
                    }
                    return model
                }
                throw AIProviderError.unavailable("Apple's on-device model needs macOS 26 or later")
                #else
                throw AIProviderError.unavailable("Apple's on-device model is only available on macOS 26 or later")
                #endif
            }
        }
        registry.register(.anthropic) { config in
            AnyLanguageModelProvider(config: config) {
                guard let key = config.apiKey else { throw AIProviderError.notConfigured("\(config.name) has no API key") }
                return AnthropicLanguageModel(baseURL: Self.url(config.baseURL, default: "https://api.anthropic.com/v1"), apiKey: key, model: config.model)
            }
        }
        registry.registerOpenAICompatible(.openai, baseURL: "https://api.openai.com/v1")
        registry.register(.gemini) { config in
            AnyLanguageModelProvider(config: config) {
                guard let key = config.apiKey else { throw AIProviderError.notConfigured("\(config.name) has no API key") }
                return GeminiLanguageModel(baseURL: Self.url(config.baseURL, default: "https://generativelanguage.googleapis.com/v1beta"), apiKey: key, model: config.model)
            }
        }
        registry.register(.ollama) { config in
            AnyLanguageModelProvider(config: config) {
                OllamaLanguageModel(baseURL: Self.url(config.baseURL, default: "http://127.0.0.1:11434"), model: config.model)
            }
        }
        registry.register(.claudeCode) { ClaudeCodeProvider(config: $0, executable: claudeExecutable) }
        return registry
    }

    /// One OpenAI-compatible endpoint, one line: the vendors differ only in
    /// their base URL and in whether they answer an anonymous request.
    /// `requiresKey` is the complaint for those that do not; nil leaves the key
    /// optional, which is what a local endpoint (LM Studio, LiteLLM) needs.
    public mutating func registerOpenAICompatible(_ kind: AIProviderKind, baseURL fallback: String, requiresKey complaint: String? = nil) {
        register(kind) { config in
            AnyLanguageModelProvider(config: config) {
                if let complaint, config.apiKey == nil {
                    throw AIProviderError.notConfigured("\(config.name) \(complaint)")
                }
                return OpenAILanguageModel(baseURL: Self.url(config.baseURL, default: fallback), apiKey: config.apiKey ?? "", model: config.model, apiVariant: .chatCompletions)
            }
        }
    }

    private static func url(_ configured: String?, default fallback: String) -> URL {
        URL(string: configured ?? fallback) ?? URL(string: fallback)!
    }
}
