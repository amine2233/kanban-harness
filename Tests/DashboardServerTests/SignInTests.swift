import DashboardServer
import Foundation
import Testing
import VaporTesting

@Suite struct SignInAPITests {
    @Test func signInRoutesRoundTripThroughTheServer() async throws {
        try await withServer { app, home in
            _ = try await app.json(.PUT, "/api/settings/ai/providers/router", body: ["kind": "openrouter", "name": "Router", "model": "m"])

            let (status, body) = try await app.json(.POST, "/api/settings/ai/providers/router/sign-in")
            #expect(status == .ok)
            let urlText = try #require((body as? [String: Any])?["url"] as? String)
            let url = try #require(URL(string: urlText))
            #expect(url.host == "openrouter.ai")
            let callbackParam = try #require(URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?.first { $0.name == "callback_url" }?.value)
            let callback = try #require(URL(string: callbackParam))
            #expect(callback.path == "/api/auth/callback", "the vendor is sent back to this server")
            let state = try #require(URLComponents(url: callback, resolvingAgainstBaseURL: false)?.queryItems?.first { $0.name == "state" }?.value)

            let forged = try await app.sendRequest(.GET, "/api/auth/callback?state=nope&code=c")
            #expect(forged.status == .seeOther)
            #expect(forged.headers.first(name: .location)?.contains("sign_in_error=") == true)

            let denied = try await app.sendRequest(.GET, "/api/auth/callback?state=\(state)&error=access_denied")
            #expect(denied.headers.first(name: .location)?.contains("sign_in_error=access") == true)

            let (noSignIn, _) = try await app.json(.POST, "/api/settings/ai/providers/nothing/sign-in")
            #expect(noSignIn == .notFound)

            let (signedOut, after) = try await app.json(.DELETE, "/api/settings/ai/providers/router/credential")
            #expect(signedOut == .ok)
            #expect(((after as? [String: Any])?["providers"] as? [[String: Any]])?.first?["has_api_key"] as? Bool == false)
            let stored = (try? String(contentsOfFile: home + "/credentials.json", encoding: .utf8)) ?? ""
            #expect(!stored.contains("router"))
        }
    }

    @Test func oauthAppSettingsAreStoredAndOnlyTheClientIdIsExposed() async throws {
        try await withServer { app, home in
            let (status, body) = try await app.json(.PUT, "/api/settings/ai/providers/hf", body: [
                "kind": "huggingface", "name": "HF", "model": "Qwen/Qwen2.5-7B-Instruct",
                "oauth": ["client_id": "app-1", "client_secret": "shh"],
            ])
            #expect(status == .ok)
            let provider = try #require(((body as? [String: Any])?["providers"] as? [[String: Any]])?.first)
            #expect(provider["oauth_client_id"] as? String == "app-1")
            #expect(provider["oauth"] == nil && provider["client_secret"] == nil)
            let raw = try String(contentsOfFile: home + "/config.json", encoding: .utf8)
            #expect(raw.contains("\"client_id\" : \"app-1\""))

            let (signIn, response) = try await app.json(.POST, "/api/settings/ai/providers/hf/sign-in")
            #expect(signIn == .ok)
            let url = try #require((response as? [String: Any])?["url"] as? String)
            #expect(url.hasPrefix("https://huggingface.co/oauth/authorize?"))
            #expect(url.contains("client_id=app-1") && url.contains("code_challenge_method=S256"))
        }
    }
}
