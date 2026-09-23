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
        registry.register(.openai) { config in
            AnyLanguageModelProvider(config: config) {
                OpenAILanguageModel(baseURL: Self.url(config.baseURL, default: "https://api.openai.com/v1"), apiKey: config.apiKey ?? "", model: config.model)
            }
        }
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

    private static func url(_ configured: String?, default fallback: String) -> URL {
        URL(string: configured ?? fallback) ?? URL(string: fallback)!
    }
}
