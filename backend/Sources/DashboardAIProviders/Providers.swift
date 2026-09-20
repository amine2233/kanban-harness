import DashboardAI

extension AIProviderRegistry {
    /// Every vendor this build ships.
    public static var standard: AIProviderRegistry {
        var registry = AIProviderRegistry()
        registry.register(.anthropic) { AnthropicProvider(config: $0) }
        registry.register(.openaiCompatible) { OpenAICompatibleProvider(config: $0) }
        registry.register(.ollama) { OllamaProvider(config: $0) }
        registry.register(.claudeCode) { ClaudeCodeProvider(config: $0) }
        return registry
    }
}
