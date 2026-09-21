import DashboardAPI
import DashboardDomain
import Vapor

struct SettingsController: RouteCollection {
    func boot(routes: any RoutesBuilder) throws {
        routes.get("settings", use: show)
        routes.patch("settings", use: update)
    }

    func show(req: Request) async throws -> Settings {
        try await req.settings.current()
    }

    func update(req: Request) async throws -> Settings {
        let body = try req.content.decode(UpdateSettingsRequest.self)
        return try await req.settings.update(defaultStorage: body.defaultStorage, corsOrigins: body.corsOrigins)
    }
}
