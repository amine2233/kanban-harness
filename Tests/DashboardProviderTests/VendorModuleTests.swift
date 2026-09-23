import DashboardAI
import DashboardDomain
import DashboardOAuth
import Foundation
import Testing
@testable import DashboardProviderHuggingFace
@testable import DashboardProviderOpenRouter

actor StubTransport: HTTPTransport {
    struct Call: Sendable { let url: URL; let headers: [String: String]; let body: String }
    private(set) var calls: [Call] = []
    private let response: (Int, String)
    init(_ response: (Int, String)) { self.response = response }
    func post(_ url: URL, headers: [String: String], body: Data) async throws -> (status: Int, body: Data) {
        calls.append(Call(url: url, headers: headers, body: String(decoding: body, as: UTF8.self)))
        return (response.0, Data(response.1.utf8))
    }
}

@Suite struct VendorModuleTests {
    let callback = URL(string: "http://127.0.0.1:5175/api/auth/callback")!

    func query(_ url: URL) -> [String: String] {
        Dictionary(uniqueKeysWithValues: (URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []).map { ($0.name, $0.value ?? "") })
    }

    @Test func modulesRegisterProviderAndSignIn() throws {
        var registry = AIProviderRegistry()
        HuggingFaceProvider.register(in: &registry)
        OpenRouterProvider.register(in: &registry)
        #expect(Set(registry.kinds) == [.huggingface, .openrouter])
        #expect(Set(registry.signInKinds) == [.huggingface, .openrouter])
        let router = try AIProviderConfig(id: "r", kind: .openrouter, name: "R", model: "m")
        #expect(try registry.signIn(for: router) is OpenRouterSignIn)
        let hf = try AIProviderConfig(id: "h", kind: .huggingface, name: "H", model: "m", oauth: OAuthClientSettings(clientId: "app"))
        #expect(try registry.signIn(for: hf) is OAuthCodeFlow)
    }

    @Test func vendorsWithoutAKeyAreNotConfigured() async throws {
        var registry = AIProviderRegistry()
        HuggingFaceProvider.register(in: &registry)
        OpenRouterProvider.register(in: &registry)
        let request = CompletionRequest(system: "sys", prompt: "draft", schema: TicketDraft.jsonSchema)
        for (kind, complaint) in [(AIProviderKind.huggingface, "has no token"), (.openrouter, "has no API key")] {
            let provider = try registry.make(AIProviderConfig(id: "v", kind: kind, name: "V", model: "m"))
            await #expect(throws: AIProviderError.notConfigured("V \(complaint) — paste one or sign in")) {
                for try await _ in provider.stream(request) {}
            }
        }
    }

    @Test func huggingFaceSignInNeedsARegisteredApp() throws {
        let bare = try AIProviderConfig(id: "h", kind: .huggingface, name: "H", model: "m")
        #expect(throws: AIProviderError.self) { _ = try HuggingFaceProvider.signIn(for: bare) }
        let flow = try HuggingFaceProvider.signIn(for: AIProviderConfig(id: "h", kind: .huggingface, name: "H", model: "m", oauth: OAuthClientSettings(clientId: "app")))
        let url = flow.authorizationURL(callback: callback, state: "s", codeChallenge: "c")
        #expect(url.host == "huggingface.co" && url.path == "/oauth/authorize")
        #expect(query(url)["scope"] == "openid profile inference-api")
        #expect(query(url)["client_id"] == "app")
        #expect(flow.tokenURL.absoluteString == "https://huggingface.co/oauth/token")
    }

    @Test func openRouterCarriesStateInTheCallbackAndExchangesForAKey() async throws {
        let transport = StubTransport((200, #"{"key":"sk-or-v1-abc"}"#))
        let signIn = OpenRouterSignIn(transport: transport)
        let url = signIn.authorizationURL(callback: callback, state: "st4te", codeChallenge: "ch")
        #expect(url.host == "openrouter.ai" && url.path == "/auth")
        #expect(query(url)["code_challenge"] == "ch" && query(url)["code_challenge_method"] == "S256")
        let callbackParam = try #require(query(url)["callback_url"])
        let sentCallback = try #require(URL(string: callbackParam))
        #expect(sentCallback.path == "/api/auth/callback" && query(sentCallback)["state"] == "st4te")

        let credential = try await signIn.exchange(code: "c0de", codeVerifier: "ver", callback: callback)
        #expect(credential == Credential(secret: "sk-or-v1-abc"))
        let call = try #require(await transport.calls.first)
        #expect(call.url.absoluteString == "https://openrouter.ai/api/v1/auth/keys")
        #expect(call.headers["Content-Type"] == "application/json")
        #expect(call.body == #"{"code":"c0de","code_challenge_method":"S256","code_verifier":"ver"}"#)
        #expect(try await signIn.refresh(credential) == nil)
    }

    @Test func openRouterRejectionIsTyped() async {
        let signIn = OpenRouterSignIn(transport: StubTransport((403, "nope")))
        await #expect(throws: OAuthError.vendorRejected(status: 403, body: "nope")) {
            _ = try await signIn.exchange(code: "c", codeVerifier: "v", callback: callback)
        }
    }
}
