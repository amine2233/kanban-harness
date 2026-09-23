import Foundation
import Testing
@testable import DashboardDomain

@Suite
struct AIConfigTests {
    func claude(key: String? = "sk-test") throws -> AIProviderConfig {
        try AIProviderConfig(
            id: "claude",
            kind: .anthropic,
            name: " Claude ",
            model: "claude-sonnet-5",
            apiKey: key
        )
    }

    @Test
    func providerConfigValidatesAndTrims() throws {
        let provider = try claude()
        #expect(provider.name == "Claude")
        #expect(provider.hasAPIKey)
        #expect(try AIProviderConfig(
            id: "local",
            kind: .ollama,
            name: "Ollama",
            model: "llama3",
            baseURL: "http://127.0.0.1:11434"
        ).baseURL == "http://127.0.0.1:11434")
        #expect(try claude(key: "").hasAPIKey == false, "empty key is no key")
    }

    @Test
    func providerConfigRejectsBadInput() {
        #expect(throws: DomainError.invalidProviderId("Bad Id")) { try AIProviderConfig(
            id: "Bad Id",
            kind: .ollama,
            name: "x",
            model: "m"
        ) }
        #expect(throws: DomainError.emptyName) { try AIProviderConfig(
            id: "a",
            kind: .ollama,
            name: " ",
            model: "m"
        ) }
        #expect(throws: DomainError.emptyModel("a")) { try AIProviderConfig(
            id: "a",
            kind: .ollama,
            name: "x",
            model: ""
        ) }
        #expect(throws: DomainError.invalidOrigin("ftp://x")) { try AIProviderConfig(
            id: "a",
            kind: .ollama,
            name: "x",
            model: "m",
            baseURL: "ftp://x"
        ) }
        #expect(throws: DomainError.invalidMaxTokens(0)) { try AIProviderConfig(
            id: "a",
            kind: .ollama,
            name: "x",
            model: "m",
            maxTokens: 0
        ) }
    }

    @Test
    func pricingIsValidatedAndPricesTokens() throws {
        let pricing = try AIPricing(inputPerMillion: 3, outputPerMillion: 15)
        #expect(pricing.cost(inputTokens: 1_000_000, outputTokens: 200_000) == 6)
        #expect(pricing.cost(inputTokens: nil, outputTokens: nil) == 0)
        #expect(throws: DomainError.invalidPricing) { try AIPricing(inputPerMillion: -1, outputPerMillion: 0)
        }
        #expect(throws: DomainError.invalidPricing) { try AIPricing(
            inputPerMillion: .infinity,
            outputPerMillion: 0
        ) }
        #expect(AIProviderKind.apple.isFree && AIProviderKind.ollama.isFree && !AIProviderKind.anthropic
            .isFree && !AIProviderKind.claudeCode.isFree)
    }

    @Test
    func kindKnowsWhetherAKeyIsRequired() {
        #expect(AIProviderKind.anthropic.requiresAPIKey)
        #expect(AIProviderKind.openai.requiresAPIKey)
        #expect(AIProviderKind.gemini.requiresAPIKey)
        #expect(!AIProviderKind.ollama.requiresAPIKey)
        #expect(!AIProviderKind.apple.requiresAPIKey)
        #expect(!AIProviderKind.claudeCode.requiresAPIKey)
        #expect(AIProviderKind(rawValue: "claude_code") == .claudeCode)
        #expect(
            AIProviderKind(configValue: "openai_compatible") == .openai,
            "legacy config value keeps working"
        )
        #expect(AIProviderKind(configValue: "gemini") == .gemini)
        #expect(AIProviderKind(configValue: "bogus") == nil)
    }

    @Test
    func firstProviderBecomesDefaultAndUpsertReplaces() throws {
        var config = AIConfig.empty
        try config.upsert(claude())
        #expect(config.defaultProviderId == "claude")
        var renamed = try claude()
        renamed.name = "Claude Sonnet"
        try config.upsert(renamed)
        #expect(config.providers.count == 1)
        #expect(config.provider("claude")?.name == "Claude Sonnet")
    }

    @Test
    func removeFallsBackToAnotherDefault() throws {
        var config = try AIConfig(
            providers: [claude(), AIProviderConfig(
                id: "local",
                kind: .ollama,
                name: "Ollama",
                model: "llama3"
            )],
            defaultProviderId: "claude"
        )
        try config.remove("claude")
        #expect(config.defaultProviderId == "local")
        try config.remove("local")
        #expect(config.defaultProviderId == nil)
        #expect(throws: DomainError.providerNotFound("ghost")) { try config.remove("ghost") }
    }

    @Test
    func setDefaultRequiresAKnownProvider() throws {
        var config = try AIConfig(providers: [claude()])
        #expect(throws: DomainError.providerNotFound("nope")) { try config.setDefault("nope") }
        #expect(throws: DomainError.providerNotFound("nope")) { try AIConfig(
            providers: [],
            defaultProviderId: "nope"
        ) }
    }
}
