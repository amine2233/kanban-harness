import DashboardDomain
import DashboardOAuth
import DashboardPersistence
import DashboardService
import Foundation
import Testing
@testable import DashboardAI

/// A vendor that accepts any code and hands out a token; records what it was asked.
actor FakeSignIn: ProviderSignIn {
    private(set) var exchanged: [(code: String, verifier: String, callback: URL)] = []
    private(set) var refreshed = 0
    var expiresIn: TimeInterval?

    init(expiresIn: TimeInterval? = nil) {
        self.expiresIn = expiresIn
    }

    nonisolated func authorizationURL(callback: URL, state: String, codeChallenge: String) -> URL {
        URL(
            string: "https://vendor.test/auth?state=\(state)&challenge=\(codeChallenge)&cb=\(callback.absoluteString)"
        )!
    }

    func exchange(code: String, codeVerifier: String, callback: URL) async throws -> Credential {
        exchanged.append((code, codeVerifier, callback))
        return Credential(
            secret: "token-for-\(code)",
            refreshToken: "r",
            expiresAt: expiresIn.map { Date.timestamp().addingTimeInterval($0) }
        )
    }

    func refresh(_ credential: Credential) async throws -> Credential? {
        refreshed += 1
        return Credential(
            secret: "renewed",
            refreshToken: credential.refreshToken,
            expiresAt: .timestamp().addingTimeInterval(3_600)
        )
    }
}

@Suite
struct ProviderSignInServiceTests {
    let callback = URL(string: "http://127.0.0.1:5175/api/auth/callback")!

    func fixture(_ vendor: FakeSignIn = FakeSignIn()) async throws
        -> (ProviderSignInService, AIConfigService, InMemoryCredentialStore, FakeSignIn) {
        let credentials = InMemoryCredentialStore()
        let aiConfig = AIConfigService(store: InMemoryAIConfigStore())
        _ = try await aiConfig.upsert(AIProviderConfig(
            id: "router",
            kind: .openrouter,
            name: "Router",
            model: "m"
        ))
        _ = try await aiConfig.upsert(AIProviderConfig(
            id: "claude",
            kind: .anthropic,
            name: "Claude",
            model: "m",
            apiKey: "sk"
        ))
        var registry = AIProviderRegistry()
        registry.registerSignIn(.openrouter) { _ in vendor }
        return (
            ProviderSignInService(aiConfig: aiConfig, credentials: credentials, registry: registry),
            aiConfig,
            credentials,
            vendor
        )
    }

    @Test
    func beginThenCompleteStoresTheCredential() async throws {
        let (service, _, credentials, vendor) = try await fixture()
        let url = try await service.begin(providerId: "router", callback: callback)
        let query =
            Dictionary(uniqueKeysWithValues: (URLComponents(url: url, resolvingAgainstBaseURL: false)?
                    .queryItems ?? []).map { (
                $0.name,
                $0.value ?? ""
            ) })
        let state = try #require(query["state"])
        #expect(query["cb"] == callback.absoluteString)
        #expect(query["challenge"]?.isEmpty == false)

        #expect(try await service.complete(state: state, code: "c0de") == "router")
        #expect(try await credentials.get("router")?.secret == "token-for-c0de")
        let call = try #require(await vendor.exchanged.first)
        #expect(call.callback == callback)
        #expect(
            PKCE.challenge(for: call.verifier) == query["challenge"],
            "the verifier matches the challenge sent to the vendor"
        )
    }

    @Test
    func unknownOrReusedStateIsRefused() async throws {
        let (service, _, _, _) = try await fixture()
        let url = try await service.begin(providerId: "router", callback: callback)
        let state = try #require(URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?
            .first { $0.name == "state" }?.value)
        _ = try await service.complete(state: state, code: "c")
        await #expect(throws: ServiceError.self) { _ = try await service.complete(state: state, code: "c") }
        await #expect(throws: ServiceError.self) { _ = try await service.complete(state: "forged", code: "c")
        }
    }

    @Test
    func kindsWithoutSignInAndUnknownProvidersFail() async throws {
        let (service, _, _, _) = try await fixture()
        await #expect(throws: ServiceError.self) { _ = try await service.begin(
            providerId: "claude",
            callback: callback
        ) }
        await #expect(throws: ServiceError.self) { _ = try await service.begin(
            providerId: "ghost",
            callback: callback
        ) }
    }

    @Test
    func signOutForgetsTheCredential() async throws {
        let (service, _, credentials, _) = try await fixture()
        try await credentials.set(Credential(secret: "x"), for: "router")
        try await service.signOut(providerId: "router")
        #expect(try await credentials.get("router") == nil)
    }

    @Test
    func expiringTokensAreRenewedBeforeUse() async throws {
        let (service, _, credentials, vendor) = try await fixture()
        let config = try AIProviderConfig(
            id: "router",
            kind: .openrouter,
            name: "Router",
            model: "m",
            apiKey: "old"
        )
        try await credentials.set(
            Credential(secret: "old", refreshToken: "r", expiresAt: .timestamp().addingTimeInterval(3_600)),
            for: "router"
        )
        #expect(try await service.refreshed(config).apiKey == "old", "a fresh token is left alone")

        try await credentials.set(
            Credential(secret: "old", refreshToken: "r", expiresAt: .timestamp().addingTimeInterval(10)),
            for: "router"
        )
        #expect(try await service.refreshed(config).apiKey == "renewed")
        #expect(try await credentials.get("router")?.secret == "renewed")
        #expect(await vendor.refreshed == 1)

        let plain = try AIProviderConfig(
            id: "claude",
            kind: .anthropic,
            name: "Claude",
            model: "m",
            apiKey: "sk"
        )
        #expect(try await service.refreshed(plain) == plain, "kinds without a sign-in pass through")
    }
}
