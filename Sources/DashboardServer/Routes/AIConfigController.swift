import DashboardAI
import DashboardAPI
import DashboardDomain
import DashboardRuntime
import Vapor

/// `/api/settings/ai`: the AI provider configuration (keys write-only).
struct AIConfigController: RouteCollection {
    func boot(routes: any RoutesBuilder) throws {
        let aiRoutes = routes.grouped("settings", "ai")
        aiRoutes.get(use: show)
        aiRoutes.put("default", use: setDefault)
        aiRoutes.put("providers", ":provider", use: upsert)
        aiRoutes.delete("providers", ":provider", use: remove)
        aiRoutes.post("providers", ":provider", "sign-in", use: beginSignIn)
        aiRoutes.delete("providers", ":provider", "credential", use: signOut)
        routes.get("auth", "callback", use: completeSignIn)
    }

    // MARK: Browser sign-in (OAuth / PKCE)

    /// The vendor sends the user back to this server's own `/api/auth/callback`.
    func beginSignIn(req: Request) async throws -> SignInResponse {
        let id = req.parameters.get("provider") ?? ""
        let host = req.headers.first(name: .host) ?? "127.0.0.1"
        guard let callback = URL(string: "http://\(host)/api/auth/callback") else { throw Abort(
            .badRequest,
            reason: "bad Host header"
        ) }

        return try await SignInResponse(url: req.signIn.begin(providerId: id, callback: callback)
            .absoluteString)
    }

    /// Top-level navigation from the vendor: lands the user back in Settings either way.
    func completeSignIn(req: Request) async throws -> Response {
        let state: String? = req.query["state"]
        let code: String? = req.query["code"]
        let error: String? = req.query["error_description"] ?? req.query["error"]
        guard let state, let code, error == nil else {
            return req
                .redirect(to: "/settings?sign_in_error=" + Self.encode(error ?? "the vendor sent no code"))
        }

        do {
            let id = try await req.signIn.complete(state: state, code: code)
            return req.redirect(to: "/settings?signed_in=" + Self.encode(id))
        } catch {
            return req.redirect(to: "/settings?sign_in_error=" + Self.encode(error.localizedDescription))
        }
    }

    func signOut(req: Request) async throws -> AIConfigDTO {
        try await req.signIn.signOut(providerId: req.parameters.get("provider") ?? "")
        return try await AIConfigDTO(req.aiConfig.current())
    }

    private static func encode(_ text: String) -> String {
        text.addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? ""
    }

    func show(req: Request) async throws -> AIConfigDTO {
        try await AIConfigDTO(req.aiConfig.current())
    }

    func upsert(req: Request) async throws -> AIConfigDTO {
        let id = req.parameters.get("provider") ?? ""
        let body = try req.content.decode(UpsertAIProviderRequest.self)
        let existing = try await req.aiConfig.current().provider(id)?.apiKey
        let provider = try body.provider(id: id, existingKey: existing)
        return try await AIConfigDTO(req.aiConfig.upsert(provider))
    }

    func remove(req: Request) async throws -> AIConfigDTO {
        try await AIConfigDTO(req.aiConfig.remove(req.parameters.get("provider") ?? ""))
    }

    func setDefault(req: Request) async throws -> AIConfigDTO {
        let body = try req.content.decode(SetDefaultAIProviderRequest.self)
        return try await AIConfigDTO(req.aiConfig.setDefault(body.providerId))
    }
}
