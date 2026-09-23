import DashboardAI
import DashboardAPI
import DashboardDomain
import DashboardRuntime
import Foundation
import Vapor

/// `/api/settings/ai`: the AI provider configuration (keys write-only).
struct AIConfigController: RouteCollection {
    /// The origin a browser reaches this dashboard at, when one is configured.
    let publicURL: URL?

    func boot(routes: any RoutesBuilder) throws {
        let ai = routes.grouped("settings", "ai")
        ai.get(use: show)
        ai.put("default", use: setDefault)
        ai.put("providers", ":provider", use: upsert)
        ai.delete("providers", ":provider", use: remove)
        ai.post("providers", ":provider", "sign-in", use: beginSignIn)
        ai.delete("providers", ":provider", "credential", use: signOut)
        routes.get("auth", "callback", use: completeSignIn)
    }

    // MARK: Browser sign-in (OAuth / PKCE)

    /// The vendor sends the user back to `/api/auth/callback` on the origin the
    /// browser has the dashboard at.
    func beginSignIn(req: Request) async throws -> SignInResponse {
        let id = req.parameters.get("provider") ?? ""
        return SignInResponse(url: try await req.signIn.begin(providerId: id, callback: try callback(req)).absoluteString)
    }

    /// `Host` is whatever the caller sent, so it is trusted only when it names the
    /// loopback interface — the one case where the browser is on this machine and
    /// the origin cannot be anyone else's. Served over a LAN address, a proxy or
    /// TLS, a forged header would otherwise steer the vendor's callback, and the
    /// hardcoded `http://` would be wrong; those deployments state their origin
    /// with `--public-url` instead.
    private func callback(_ req: Request) throws -> URL {
        if let publicURL { return publicURL.appending(path: "api/auth/callback") }
        let host = req.headers.first(name: .host) ?? "127.0.0.1"
        guard Self.isLoopback(host), let callback = URL(string: "http://\(host)/api/auth/callback") else {
            throw Abort(.badRequest, reason: "sign-in needs --public-url unless the dashboard is reached over loopback")
        }
        return callback
    }

    private static func isLoopback(_ host: String) -> Bool {
        let name = host.hasPrefix("[")
            ? String(host.dropFirst().prefix { $0 != "]" })
            : String(host.prefix { $0 != ":" })
        return ["127.0.0.1", "::1", "localhost"].contains(name.lowercased())
    }

    /// Top-level navigation from the vendor: lands the user back in Settings either way.
    func completeSignIn(req: Request) async throws -> Response {
        let state: String? = req.query["state"]
        let code: String? = req.query["code"]
        let error: String? = req.query["error_description"] ?? req.query["error"]
        guard let state, let code, error == nil else {
            return req.redirect(to: settings("sign_in_error=" + Self.encode(error ?? "the vendor sent no code")))
        }
        do {
            let id = try await req.signIn.complete(state: state, code: code)
            return req.redirect(to: settings("signed_in=" + Self.encode(id)))
        } catch {
            return req.redirect(to: settings("sign_in_error=" + Self.encode(error.localizedDescription)))
        }
    }

    /// Relative without a public URL: the redirect then resolves against the origin
    /// that served the callback, which is where the app is.
    private func settings(_ query: String) -> String {
        guard let publicURL else { return "/settings?" + query }
        return publicURL.appending(path: "settings").absoluteString + "?" + query
    }

    func signOut(req: Request) async throws -> AIConfigDTO {
        try await req.signIn.signOut(providerId: req.parameters.get("provider") ?? "")
        return AIConfigDTO(try await req.aiConfig.current())
    }

    private static func encode(_ text: String) -> String {
        text.addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? ""
    }

    func show(req: Request) async throws -> AIConfigDTO {
        AIConfigDTO(try await req.aiConfig.current())
    }

    func upsert(req: Request) async throws -> AIConfigDTO {
        let id = req.parameters.get("provider") ?? ""
        let body = try req.content.decode(UpsertAIProviderRequest.self)
        let existing = try await req.aiConfig.current().provider(id)?.apiKey
        let provider = try body.provider(id: id, existingKey: existing)
        return AIConfigDTO(try await req.aiConfig.upsert(provider))
    }

    func remove(req: Request) async throws -> AIConfigDTO {
        AIConfigDTO(try await req.aiConfig.remove(req.parameters.get("provider") ?? ""))
    }

    func setDefault(req: Request) async throws -> AIConfigDTO {
        let body = try req.content.decode(SetDefaultAIProviderRequest.self)
        return AIConfigDTO(try await req.aiConfig.setDefault(body.providerId))
    }
}
