import Configuration
import DashboardDomain
import DashboardPersistence
import Foundation
import SystemPackage
import Yams

/// AI provider configuration in the dashboard's config file (`config.json` or
/// `config.yaml`), read through swift-configuration so environment variables
/// override the file — e.g. `MVP_DASHBOARD_AI_PROVIDERS_CLAUDE_API_KEY` supplies
/// a secret that never has to be written to disk. Secrets are kept in the
/// `CredentialStore`, not in this file: resolution is environment → credential
/// store → a legacy `api_key` left in the file. Writes go to the file only,
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
    private let credentials: any CredentialStore

    public init(
        path: String,
        credentials: any CredentialStore = CredentialStoreInMemory(),
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) {
        self.path = path
        self.credentials = credentials
        self.environment = environment
    }

    public var isYAML: Bool {
        ["yaml", "yml"].contains((path as NSString).pathExtension.lowercased())
    }

    // MARK: Read (swift-configuration)

    public func load() async throws -> AIConfig {
        let reader = try await reader()
        let aiScope = reader.scoped(to: "ai")
        let ids = aiScope.stringArray(forKey: "provider_ids", default: [])
        var providers: [AIProviderConfig] = []
        for id in ids {
            let scope = aiScope.scoped(to: ConfigKey(["providers", id]))
            guard let kindRaw = scope.string(forKey: "kind"),
                  let kind = AIProviderKind(configValue: kindRaw) else {
                throw PersistenceError.corrupt(
                    path: path,
                    reason: "ai.providers.\(id).kind is missing or unknown"
                )
            }

            let stored = try await credentials.get(id)?.secret
            let apiKey = environmentAPIKey(for: id) ?? stored ?? scope.string(
                forKey: "api_key",
                isSecret: true
            )
            do {
                try providers.append(AIProviderConfig(
                    id: id,
                    kind: kind,
                    name: scope.string(forKey: "name", default: id),
                    model: scope.string(forKey: "model", default: ""),
                    baseURL: scope.string(forKey: "base_url"),
                    apiKey: apiKey,
                    maxTokens: scope.int(forKey: "max_tokens"),
                    pricing: Self.pricing(scope.scoped(to: "pricing")),
                    oauth: Self.oauth(scope.scoped(to: "oauth"))
                ))
            } catch {
                throw PersistenceError.corrupt(
                    path: path,
                    reason: "ai.providers.\(id): \(error.localizedDescription)"
                )
            }
        }
        do {
            return try AIConfig(
                providers: providers,
                defaultProviderId: aiScope.string(forKey: "default_provider")
            )
        } catch {
            throw PersistenceError.corrupt(path: path, reason: error.localizedDescription)
        }
    }

    private static func pricing(_ scope: ConfigReader) throws -> AIPricing? {
        guard let input = scope.double(forKey: "input_per_million") ?? scope
            .double(forKey: "output_per_million") else { return nil }

        return try AIPricing(
            inputPerMillion: scope.double(forKey: "input_per_million", default: input),
            outputPerMillion: scope.double(forKey: "output_per_million", default: input)
        )
    }

    private static func oauth(_ scope: ConfigReader) -> OAuthClientSettings? {
        guard let clientId = scope.string(forKey: "client_id") else { return nil }

        return OAuthClientSettings(
            clientId: clientId,
            clientSecret: scope.string(forKey: "client_secret", isSecret: true)
        )
    }

    private func reader() async throws -> ConfigReader {
        let env = EnvironmentVariablesProvider(environmentVariables: environment)
            .prefixKeys(with: ConfigKey([Self.envPrefix]))
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

    // MARK: Write (settings to the file, secrets to the credential store; env values stay in the environment)

    public func save(_ config: AIConfig) async throws {
        var document = try readDocument()
        var aiSection: [String: Any] = [:]
        if let current = config.defaultProviderId { aiSection["default_provider"] = current }
        aiSection["provider_ids"] = config.providers.map(\.id)
        let existing = (document["ai"] as? [String: Any])?["providers"] as? [String: Any] ?? [:]
        var providers: [String: Any] = [:]
        for provider in config.providers {
            var entry: [String: Any] = [
                "kind": provider.kind.rawValue,
                "name": provider.name,
                "model": provider.model
            ]
            if let baseURL = provider.baseURL { entry["base_url"] = baseURL }
            try await storeSecret(provider.apiKey, for: provider.id)
            if let maxTokens = provider.maxTokens { entry["max_tokens"] = maxTokens }
            if let pricing = provider.pricing {
                entry["pricing"] = [
                    "input_per_million": pricing.inputPerMillion,
                    "output_per_million": pricing.outputPerMillion
                ]
            }
            if let oauth = provider.oauth {
                var settings: [String: Any] = ["client_id": oauth.clientId]
                if let secret = oauth.clientSecret { settings["client_secret"] = secret }
                entry["oauth"] = settings
            }
            providers[provider.id] = entry
        }
        for removed in existing.keys where providers[removed] == nil {
            try await credentials.remove(removed)
        }
        aiSection["providers"] = providers
        document["ai"] = aiSection
        try write(document)
    }

    /// A key that came from the environment is never persisted; a pasted one
    /// replaces the stored credential only when it actually changed, so an
    /// OAuth token's refresh data survives a settings edit.
    private func storeSecret(_ apiKey: String?, for id: String) async throws {
        guard let apiKey else { return try await credentials.remove(id) }

        if apiKey == environmentAPIKey(for: id) { return }
        if try await credentials.get(id)?.secret == apiKey { return }
        try await credentials.set(Credential(secret: apiKey), for: id)
    }

    private func environmentAPIKey(for id: String) -> String? {
        environment["\(Self.envPrefix)_AI_PROVIDERS_\(id)_API_KEY".uppercased()]
    }

    private func readDocument() throws -> [String: Any] {
        guard let data = try AtomicFile.read(path) else { return [:] }

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
                data = try Data(Yams.dump(object: document, sortKeys: true).utf8)
            } else {
                data = try JSONSerialization.data(
                    withJSONObject: document,
                    options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
                )
            }
        } catch {
            throw PersistenceError.corrupt(path: path, reason: String(describing: error))
        }
        try AtomicFile.write(data, to: path, mode: 0o600)
    }
}

// Atomic file helpers; the config file is created private (0600) because it can hold API keys.
