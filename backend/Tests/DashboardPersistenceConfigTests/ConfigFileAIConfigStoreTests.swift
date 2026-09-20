import DashboardDomain
import DashboardPersistence
import Foundation
import Testing
@testable import DashboardPersistenceConfig

@Suite struct ConfigFileAIConfigStoreTests {
    func path(_ name: String) throws -> String {
        let dir = NSTemporaryDirectory() + "mvp-dashboard-config-" + UUID().uuidString
        try FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        return dir + "/" + name
    }

    @Test(arguments: ["config.json", "config.yaml"])
    func satisfiesContractInBothFormats(file: String) async throws {
        try await StoreContract.verify(ConfigFileAIConfigStore(path: try path(file), environment: [:]))
        try await StoreContract.verify(InMemoryAIConfigStore())
    }

    @Test func writesReadableJSONWithPrivatePermissions() async throws {
        let store = ConfigFileAIConfigStore(path: try path("config.json"), environment: [:])
        try await store.save(try AIConfig(providers: [AIProviderConfig(id: "claude", kind: .anthropic, name: "Claude", model: "claude-sonnet-5", apiKey: "sk-1")]))
        let raw = try #require(JSONSerialization.jsonObject(with: Data(contentsOf: URL(fileURLWithPath: store.path))) as? [String: Any])
        let ai = try #require(raw["ai"] as? [String: Any])
        #expect(ai["default_provider"] as? String == "claude")
        #expect(ai["provider_ids"] as? [String] == ["claude"])
        #expect(((ai["providers"] as? [String: Any])?["claude"] as? [String: Any])?["api_key"] as? String == "sk-1")
        let mode = try #require(FileManager.default.attributesOfItem(atPath: store.path)[.posixPermissions] as? Int)
        #expect(mode & 0o777 == 0o600)
    }

    @Test func handWrittenYAMLIsRead() async throws {
        let store = ConfigFileAIConfigStore(path: try path("config.yaml"), environment: [:])
        try """
        ai:
          default_provider: local
          provider_ids: [local, claude]
          providers:
            local:
              kind: ollama
              name: Ollama
              model: llama3.2
              base_url: http://127.0.0.1:11434
            claude:
              kind: anthropic
              model: claude-sonnet-5
              max_tokens: 2048
        """.write(toFile: store.path, atomically: true, encoding: .utf8)
        let config = try await store.load()
        #expect(config.defaultProviderId == "local")
        #expect(config.providers.map(\.id) == ["local", "claude"])
        #expect(config.provider("local")?.baseURL == "http://127.0.0.1:11434")
        #expect(config.provider("claude")?.name == "claude", "name defaults to the id")
        #expect(config.provider("claude")?.maxTokens == 2048)
        #expect(config.provider("claude")?.hasAPIKey == false)
    }

    @Test func environmentOverridesTheFileForSecrets() async throws {
        let file = try path("config.json")
        let plain = ConfigFileAIConfigStore(path: file, environment: [:])
        try await plain.save(try AIConfig(providers: [AIProviderConfig(id: "claude", kind: .anthropic, name: "Claude", model: "m")]))
        let withEnv = ConfigFileAIConfigStore(path: file, environment: ["MVP_DASHBOARD_AI_PROVIDERS_CLAUDE_API_KEY": "sk-from-env"])
        #expect(try await withEnv.load().provider("claude")?.apiKey == "sk-from-env")
        #expect(try await plain.load().provider("claude")?.apiKey == nil)

        try await withEnv.save(try await withEnv.load())
        let raw = try String(contentsOfFile: file, encoding: .utf8)
        #expect(!raw.contains("sk-from-env"), "a key that came from the environment is not written to disk")
    }

    @Test func saveKeepsOtherTopLevelSections() async throws {
        let store = ConfigFileAIConfigStore(path: try path("config.json"), environment: [:])
        try #"{"other": {"keep": true}, "ai": {"provider_ids": []}}"#.write(toFile: store.path, atomically: true, encoding: .utf8)
        try await store.save(try AIConfig(providers: [AIProviderConfig(id: "x", kind: .ollama, name: "X", model: "m")]))
        let raw = try #require(JSONSerialization.jsonObject(with: Data(contentsOf: URL(fileURLWithPath: store.path))) as? [String: Any])
        #expect((raw["other"] as? [String: Any])?["keep"] as? Bool == true)
        #expect(((raw["ai"] as? [String: Any])?["provider_ids"] as? [String]) == ["x"])
    }

    @Test func unknownKindAndMissingFileAreHandled() async throws {
        let missing = ConfigFileAIConfigStore(path: try path("config.json"), environment: [:])
        #expect(try await missing.load() == .empty)
        let bad = ConfigFileAIConfigStore(path: try path("config.json"), environment: [:])
        try #"{"ai": {"provider_ids": ["x"], "providers": {"x": {"kind": "magic", "model": "m"}}}}"#.write(toFile: bad.path, atomically: true, encoding: .utf8)
        await #expect(throws: PersistenceError.self) { try await bad.load() }
    }
}
