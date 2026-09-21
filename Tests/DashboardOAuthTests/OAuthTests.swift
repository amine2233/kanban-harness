import Crypto
import DashboardDomain
import Foundation
import Testing
@testable import DashboardOAuth

/// Records requests and answers with a scripted response.
actor StubTransport: HTTPTransport {
    struct Call: Sendable {
        let url: URL
        let headers: [String: String]
        let body: String
    }

    private(set) var calls: [Call] = []
    private let responses: [(Int, String)]
    private var index = 0

    init(_ responses: [(Int, String)]) {
        self.responses = responses
    }

    func post(_ url: URL, headers: [String: String], body: Data) async throws -> (status: Int, body: Data) {
        calls.append(Call(url: url, headers: headers, body: String(decoding: body, as: UTF8.self)))
        let (status, text) = responses[min(index, responses.count - 1)]
        index += 1
        return (status, Data(text.utf8))
    }
}

@Suite struct PKCETests {
    @Test func verifierIsUnpredictableAndURLSafe() {
        let a = PKCE.verifier(), b = PKCE.verifier()
        #expect(a != b)
        #expect(a.count == 43, "32 random bytes, base64url without padding")
        #expect(a.allSatisfy { $0.isLetter || $0.isNumber || $0 == "-" || $0 == "_" })
    }

    @Test func challengeIsBase64URLOfSHA256() {
        // Worked example from RFC 7636 appendix B.
        let verifier = "dBjftJeZ4CVP-mB92K27uhbUJU1p1r_wW1gFWFOEjXk"
        #expect(PKCE.challenge(for: verifier) == "E9Melhoa2OwvFrEMTJguCHaoeK1t8URWbuGJSstw-cM")
    }
}

@Suite struct OAuthCodeFlowTests {
    let callback = URL(string: "http://127.0.0.1:5175/api/auth/callback")!
    let client = OAuthClientSettings(clientId: "app-1")

    func flow(_ transport: StubTransport, secret: String? = nil) -> OAuthCodeFlow {
        OAuthCodeFlow(
            authorizeURL: URL(string: "https://vendor.test/oauth/authorize")!,
            tokenURL: URL(string: "https://vendor.test/oauth/token")!,
            client: OAuthClientSettings(clientId: "app-1", clientSecret: secret),
            scopes: ["openid", "inference-api"],
            transport: transport
        )
    }

    @Test func authorizationURLCarriesPKCEStateAndScopes() throws {
        let url = flow(StubTransport([])).authorizationURL(callback: callback, state: "st", codeChallenge: "ch")
        let items = try #require(URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems)
        let query = Dictionary(uniqueKeysWithValues: items.map { ($0.name, $0.value ?? "") })
        #expect(url.host == "vendor.test" && url.path == "/oauth/authorize")
        #expect(query["response_type"] == "code")
        #expect(query["client_id"] == "app-1")
        #expect(query["redirect_uri"] == callback.absoluteString)
        #expect(query["scope"] == "openid inference-api")
        #expect(query["state"] == "st")
        #expect(query["code_challenge"] == "ch")
        #expect(query["code_challenge_method"] == "S256")
    }

    @Test func exchangePostsTheFormAndReadsTheToken() async throws {
        let transport = StubTransport([(200, #"{"access_token":"at","refresh_token":"rt","expires_in":3600,"token_type":"bearer"}"#)])
        let credential = try await flow(transport, secret: "s3cret").exchange(code: "c0de", codeVerifier: "ver", callback: callback)
        #expect(credential.secret == "at")
        #expect(credential.refreshToken == "rt")
        let expiry = try #require(credential.expiresAt).timeIntervalSinceNow
        #expect(expiry > 3500 && expiry <= 3600)
        let call = try #require(await transport.calls.first)
        #expect(call.url.absoluteString == "https://vendor.test/oauth/token")
        #expect(call.headers["Content-Type"] == "application/x-www-form-urlencoded")
        #expect(call.body == "client_id=app-1&client_secret=s3cret&code=c0de&code_verifier=ver&grant_type=authorization_code&redirect_uri=http%3A%2F%2F127.0.0.1%3A5175%2Fapi%2Fauth%2Fcallback")
    }

    @Test func refreshKeepsTheRefreshTokenWhenTheVendorOmitsIt() async throws {
        let transport = StubTransport([(200, #"{"access_token":"at2","expires_in":60}"#)])
        let renewed = try await flow(transport).refresh(Credential(secret: "old", refreshToken: "rt"))
        #expect(renewed?.secret == "at2")
        #expect(renewed?.refreshToken == "rt")
        #expect(try #require(await transport.calls.first).body == "client_id=app-1&grant_type=refresh_token&refresh_token=rt")
        await #expect(throws: OAuthError.notRefreshable) { _ = try await flow(transport).refresh(Credential(secret: "x")) }
    }

    @Test func vendorErrorsAreTyped() async throws {
        await #expect(throws: OAuthError.vendorRejected(status: 400, body: #"{"error":"invalid_grant"}"#)) {
            _ = try await flow(StubTransport([(400, #"{"error":"invalid_grant"}"#)])).exchange(code: "c", codeVerifier: "v", callback: callback)
        }
        await #expect(throws: OAuthError.malformedResponse("token response has no access_token")) {
            _ = try await flow(StubTransport([(200, #"{"ok":true}"#)])).exchange(code: "c", codeVerifier: "v", callback: callback)
        }
    }
}

@Suite struct SignInSessionsTests {
    @Test func sessionsAreOneShotAndExpire() async {
        let clock = Clock()
        let sessions = SignInSessions(ttl: 600) { clock.now }
        let callback = URL(string: "http://127.0.0.1:1/cb")!
        let (state, verifier) = await sessions.begin(providerId: "hf", callback: callback)
        #expect(await sessions.consume("nope") == nil)
        let pending = await sessions.consume(state)
        #expect(pending?.providerId == "hf" && pending?.codeVerifier == verifier && pending?.callback == callback)
        #expect(await sessions.consume(state) == nil, "a state is consumed once")

        let (stale, _) = await sessions.begin(providerId: "hf", callback: callback)
        clock.advance(601)
        #expect(await sessions.consume(stale) == nil, "expired sessions are dropped")
    }

    final class Clock: @unchecked Sendable {
        private(set) var now = Date.timestamp()
        func advance(_ seconds: TimeInterval) { now = now.addingTimeInterval(seconds) }
    }
}
