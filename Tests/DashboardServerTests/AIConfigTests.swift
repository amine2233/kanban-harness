import DashboardServer
import Foundation
import Testing
import Vapor
import VaporTesting

@Suite(.serialized)
struct AIConfigAPITests {
    @Test
    func providersAreManagedThroughTheAPIAndPersistedToConfigJSON() async throws {
        try await withServer { app, home in
            let (status, empty) = try await app.json(.GET, "/api/settings/ai")
            #expect(status == .ok)
            #expect(((empty as? [String: Any])?["providers"] as? [Any])?.isEmpty == true)

            let (put, body) = try await app.json(.PUT, "/api/settings/ai/providers/claude", body: [
                "kind": "anthropic", "name": "Claude", "model": "claude-sonnet-5", "api_key": "sk-secret",
                "max_tokens": 4_096,
                "pricing": ["input_per_million": 3, "output_per_million": 15]
            ])
            #expect(put == .ok)
            let config = try #require(body as? [String: Any])
            #expect(config["default_provider"] as? String == "claude", "first provider becomes default")
            let provider = try #require((config["providers"] as? [[String: Any]])?.first)
            #expect(provider["has_api_key"] as? Bool == true)
            #expect(provider["api_key"] == nil, "keys never leave the server")
            #expect(provider["base_url"] is NSNull)
            #expect((provider["pricing"] as? [String: Double])?["input_per_million"] == 3)

            let raw = try String(contentsOfFile: home + "/config.json", encoding: .utf8)
            #expect(!raw.contains("sk-secret"), "the config file never holds secrets")
            #expect(raw.contains("\"provider_ids\""))
            let credentials = try String(contentsOfFile: home + "/credentials.json", encoding: .utf8)
            #expect(credentials.contains("sk-secret"), "secrets live in credentials.json")

            _ = try await app.json(
                .PUT,
                "/api/settings/ai/providers/local",
                body: [
                    "kind": "ollama",
                    "name": "Ollama",
                    "model": "llama3.2",
                    "base_url": "http://127.0.0.1:11434"
                ]
            )
            let (_, switched) = try await app.json(
                .PUT,
                "/api/settings/ai/default",
                body: ["provider_id": "local"]
            )
            #expect((switched as? [String: Any])?["default_provider"] as? String == "local")

            let (_, renamed) = try await app.json(
                .PUT,
                "/api/settings/ai/providers/claude",
                body: ["kind": "anthropic", "name": "Claude Sonnet", "model": "claude-sonnet-5"]
            )
            let claude = try #require((renamed as? [String: Any])?["providers"] as? [[String: Any]])
                .first { $0["id"] as? String == "claude" }
            #expect(claude?["has_api_key"] as? Bool == true, "omitting api_key keeps the stored key")

            let (_, cleared) = try await app.json(
                .PUT,
                "/api/settings/ai/providers/claude",
                body: ["kind": "anthropic", "name": "Claude", "model": "m", "api_key": ""]
            )
            let clearedClaude = try #require((cleared as? [String: Any])?["providers"] as? [[String: Any]])
                .first { $0["id"] as? String == "claude" }
            #expect(clearedClaude?["has_api_key"] as? Bool == false, "empty api_key clears it")

            let (deleted, after) = try await app.json(.DELETE, "/api/settings/ai/providers/local")
            #expect(deleted == .ok)
            #expect((after as? [String: Any])?["default_provider"] as? String == "claude")
        }
    }

    @Test
    func validationAndNotFoundUseTheErrorEnvelope() async throws {
        try await withServer { app, _ in
            let (bad, err) = try await app.json(
                .PUT,
                "/api/settings/ai/providers/Bad-Id",
                body: ["kind": "ollama", "name": "x", "model": "m"]
            )
            #expect(bad == .badRequest)
            #expect((err as? [String: Any])?["code"] as? String == "VALIDATION_FAILED")
            #expect(try await app.json(
                .PUT,
                "/api/settings/ai/providers/x",
                body: ["kind": "magic", "name": "x", "model": "m"]
            ).0 == .badRequest)
            #expect(try await app.json(.DELETE, "/api/settings/ai/providers/ghost").0 == .notFound)
            #expect(try await app.json(.PUT, "/api/settings/ai/default", body: ["provider_id": "ghost"])
                .0 == .notFound)
        }
    }

    @Test
    func handEditedYAMLConfigIsUsedWhenPresent() async throws {
        let home = try tempDir()
        try """
        ai:
          provider_ids: [local]
          providers:
            local: { kind: ollama, name: Local, model: llama3.2 }
        """.write(toFile: home + "/config.yaml", atomically: true, encoding: .utf8)
        try await withApp(configure: { try await configure($0, config: ServerConfig(home: home)) }) { app in
            let (_, body) = try await app.testing().json(.GET, "/api/settings/ai")
            #expect(((body as? [String: Any])?["providers"] as? [[String: Any]])?
                .first?["name"] as? String == "Local")
            _ = try await app.testing().json(
                .PUT,
                "/api/settings/ai/providers/local",
                body: ["kind": "ollama", "name": "Renamed", "model": "llama3.2"]
            )
            let yaml = try String(contentsOfFile: home + "/config.yaml", encoding: .utf8)
            #expect(yaml.contains("name: Renamed"), "edits go back to the same YAML file")
            #expect(!FileManager.default.fileExists(atPath: home + "/config.json"))
        }
    }
}
