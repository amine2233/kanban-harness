import DashboardAPI
import DashboardDomain
import DashboardRuntime
import Vapor

/// `/api/settings/ai`: the AI provider configuration (keys write-only).
struct AIConfigController: RouteCollection {
    func boot(routes: any RoutesBuilder) throws {
        let ai = routes.grouped("settings", "ai")
        ai.get(use: show)
        ai.put("default", use: setDefault)
        ai.put("providers", ":provider", use: upsert)
        ai.delete("providers", ":provider", use: remove)
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
