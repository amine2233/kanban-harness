import Configuration
import DashboardDomain
import DashboardPersistence
import Foundation
import SystemPackage
import Yams

/// AI provider configuration in the dashboard's config file (`config.json` or
/// `config.yaml`), read through swift-configuration so environment variables
/// override the file — e.g. `MVP_DASHBOARD_AI_PROVIDERS_CLAUDE_API_KEY` supplies
/// a secret that never has to be written to disk. Writes go to the file only,
/// atomically, and leave every other top-level section untouched.
///
/// Layout (swift-configuration flattens nested keys; arrays hold primitives only):
///
///     ai:
///       default_provider: claude
///       provider_ids: [claude, local]
///       providers:
///         claude: { kind: anthropic, name: Claude, model: claude-sonnet-5, api_key: ... }
///         local:  { kind: ollama, name: Ollama, model: llama3.2, base_url: http://127.0.0.1:11434 }
public struct ConfigFileAIConfigStore: AIConfigStore {
    public static let envPrefix = "mvp_dashboard"

    public let path: String
    private let environment: [String: String]

    public init(path: String, environment: [String: String] = ProcessInfo.processInfo.environment) {
        self.path = path
        self.environment = environment
    }

    public var isYAML: Bool {
        ["yaml", "yml"].contains((path as NSString).pathExtension.lowercased())
    }

    // MARK: Read (swift-configuration)

    public func load() async throws -> AIConfig {
        let reader = try await reader()
        let ai = reader.scoped(to: "ai")
        let ids = ai.stringArray(forKey: "provider_ids", default: [])
        var providers: [AIProviderConfig] = []
        for id in ids {
            let scope = ai.scoped(to: ConfigKey(["providers", id]))
            guard let kindRaw = scope.string(forKey: "kind"), let kind = AIProviderKind(rawValue: kindRaw) else {
                throw PersistenceError.corrupt(path: path, reason: "ai.providers.\(id).kind is missing or unknown")
            }
            do {
                providers.append(try AIProviderConfig(
                    id: id,
                    kind: kind,
                    name: scope.string(forKey: "name", default: id),
                    model: scope.string(forKey: "model", default: ""),
                    baseURL: scope.string(forKey: "base_url"),
                    apiKey: scope.string(forKey: "api_key", isSecret: true),
                    maxTokens: scope.int(forKey: "max_tokens")
                ))
            } catch {
                throw PersistenceError.corrupt(path: path, reason: "ai.providers.\(id): \(error.localizedDescription)")
            }
        }
        do {
            return try AIConfig(providers: providers, defaultProviderId: ai.string(forKey: "default_provider"))
        } catch {
            throw PersistenceError.corrupt(path: path, reason: error.localizedDescription)
        }
    }

    private func reader() async throws -> ConfigReader {
        let env = EnvironmentVariablesProvider(environmentVariables: environment).prefixKeys(with: ConfigKey([Self.envPrefix]))
        let file: any ConfigProvider
        do {
            if isYAML {
                file = try await FileProvider<YAMLSnapshot>(filePath: FilePath(path), allowMissing: true)
            } else {
                file = try await FileProvider<JSONSnapshot>(filePath: FilePath(path), allowMissing: true)
            }
        } catch {
            throw PersistenceError.corrupt(path: path, reason: String(describing: error))
        }
        return ConfigReader(providers: [env, file])
    }

    // MARK: Write (file only; env overrides stay in the environment)

    public func save(_ config: AIConfig) async throws {
        var document = try readDocument()
        var ai: [String: Any] = [:]
        if let current = config.defaultProviderId { ai["default_provider"] = current }
        ai["provider_ids"] = config.providers.map(\.id)
        let existing = (document["ai"] as? [String: Any])?["providers"] as? [String: Any] ?? [:]
        var providers: [String: Any] = [:]
        for provider in config.providers {
            var entry: [String: Any] = ["kind": provider.kind.rawValue, "name": provider.name, "model": provider.model]
            if let baseURL = provider.baseURL { entry["base_url"] = baseURL }
            if let apiKey = provider.apiKey {
                if apiKey == environmentAPIKey(for: provider.id) {
                    // Came from the environment: keep whatever the file had, never persist the env value.
                    if let fileKey = (existing[provider.id] as? [String: Any])?["api_key"] { entry["api_key"] = fileKey }
                } else {
                    entry["api_key"] = apiKey
                }
            }
            if let maxTokens = provider.maxTokens { entry["max_tokens"] = maxTokens }
            providers[provider.id] = entry
        }
        ai["providers"] = providers
        document["ai"] = ai
        try write(document)
    }

    private func environmentAPIKey(for id: String) -> String? {
        environment["\(Self.envPrefix)_AI_PROVIDERS_\(id)_API_KEY".uppercased()]
    }

    private func readDocument() throws -> [String: Any] {
        guard let data = try ConfigFile.read(path) else { return [:] }
        do {
            if isYAML {
                return try Yams.load(yaml: String(decoding: data, as: UTF8.self)) as? [String: Any] ?? [:]
            }
            return try JSONSerialization.jsonObject(with: data) as? [String: Any] ?? [:]
        } catch {
            throw PersistenceError.corrupt(path: path, reason: String(describing: error))
        }
    }

    private func write(_ document: [String: Any]) throws {
        let data: Data
        do {
            if isYAML {
                data = Data(try Yams.dump(object: document, sortKeys: true).utf8)
            } else {
                data = try JSONSerialization.data(withJSONObject: document, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes])
            }
        } catch {
            throw PersistenceError.corrupt(path: path, reason: String(describing: error))
        }
        try ConfigFile.write(data, to: path, mode: 0o600)
    }
}

/// Atomic file helpers; the config file is created private (0600) because it can hold API keys.
enum ConfigFile {
    static func read(_ path: String) throws -> Data? {
        guard FileManager.default.fileExists(atPath: path) else { return nil }
        do {
            return try Data(contentsOf: URL(fileURLWithPath: path))
        } catch {
            throw PersistenceError.io(path: path, underlying: error.localizedDescription)
        }
    }

    static func write(_ data: Data, to path: String, mode: Int) throws {
        let directory = (path as NSString).deletingLastPathComponent
        let temp = path + ".tmp"
        do {
            try FileManager.default.createDirectory(atPath: directory, withIntermediateDirectories: true)
            try data.write(to: URL(fileURLWithPath: temp))
            try FileManager.default.setAttributes([.posixPermissions: mode], ofItemAtPath: temp)
            _ = try FileManager.default.replaceItemAt(URL(fileURLWithPath: path), withItemAt: URL(fileURLWithPath: temp))
        } catch {
            throw PersistenceError.io(path: path, underlying: error.localizedDescription)
        }
    }
}
