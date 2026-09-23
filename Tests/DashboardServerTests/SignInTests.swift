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

    /// The redirect URI is the one thing the vendor sends the user back to, so it
    /// must not come from a header the caller controls.
    @Test func theCallbackComesFromThePublicURLOrALoopbackHost() async throws {
        try await withServer { app, _ in
            try await app.addRouter()

            let loopback = try await app.beginSignIn(host: "localhost:5175")
            #expect(loopback.status == .ok)
            #expect(try app.callback(loopback)?.hasPrefix("http://localhost:5175/api/auth/callback?state=") == true)

            let ipv6 = try await app.beginSignIn(host: "[::1]:5175")
            #expect(ipv6.status == .ok)

            let forged = try await app.beginSignIn(host: "evil.example.com")
            #expect(forged.status == .badRequest, "a forged Host must not steer the vendor's callback")
            #expect(try await app.beginSignIn(host: "127.0.0.1.evil.example.com").status == .badRequest)
        }

        try await withServer(publicURL: URL(string: "http://127.0.0.1:5173")) { app, _ in
            try await app.addRouter()

            let response = try await app.beginSignIn(host: "evil.example.com")
            #expect(response.status == .ok, "the configured origin decides, so the Host is never read")
            #expect(try app.callback(response)?.hasPrefix("http://127.0.0.1:5173/api/auth/callback?state=") == true)

            let landing = try await app.sendRequest(.GET, "/api/auth/callback?state=nope&code=c")
            #expect(landing.headers.first(name: .location)?.hasPrefix("http://127.0.0.1:5173/settings?") == true)
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

extension TestingApplicationTester {
    fileprivate func addRouter() async throws {
        let (status, _) = try await json(.PUT, "/api/settings/ai/providers/router", body: ["kind": "openrouter", "name": "Router", "model": "m"])
        #expect(status == .ok)
    }

    fileprivate func beginSignIn(host: String) async throws -> TestingHTTPResponse {
        try await sendRequest(.POST, "/api/settings/ai/providers/router/sign-in", headers: ["Host": host])
    }

    /// OpenRouter carries the redirect URI as `callback_url` on the authorization
    /// URL, with the `state` inside it.
    fileprivate func callback(_ response: TestingHTTPResponse) throws -> String? {
        let body = try JSONSerialization.jsonObject(with: Data(buffer: response.body)) as? [String: Any]
        let authorization = try #require((body?["url"] as? String).flatMap { URL(string: $0) })
        return URLComponents(url: authorization, resolvingAgainstBaseURL: false)?
            .queryItems?.first { $0.name == "callback_url" }?.value
    }
}
