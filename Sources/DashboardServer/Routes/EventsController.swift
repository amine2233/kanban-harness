import DashboardAPI
import DashboardRuntime
import DashboardService
import Vapor

/// `GET /api/events` → WebSocket streaming `ChangeEventDTO` frames for every
/// mutation made through this server. Clients refetch what an event names.
struct EventsController: RouteCollection {
    func boot(routes: any RoutesBuilder) throws {
        routes.webSocket("events") { req, socket in
            let broadcaster = req.application.services.make(ChangeBroadcasterKey.self)
            let logger = req.logger
            let events = await broadcaster.subscribe()
            try? await socket.send(Self.frame(.hello))
            let pump = Task {
                for await event in events {
                    guard !socket.isClosed else { break }

                    try? await socket.send(Self.frame(ChangeEventDTO(event)))
                }
            }
            socket.onClose.whenComplete { _ in
                pump.cancel()
                logger.debug("events client disconnected")
            }
        }
    }

    static func frame(_ event: ChangeEventDTO) -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        return String(decoding: (try? encoder.encode(event)) ?? Data("{}".utf8), as: UTF8.self)
    }
}

extension ChangeEventDTO {
    /// Maps the service event onto the wire type.
    init(_ event: ChangeEvent) {
        switch event {
        case .projectsChanged: self.init(kind: .projectsChanged)
        case .settingsChanged: self.init(kind: .settingsChanged)
        case .aiConfigChanged: self.init(kind: .aiConfigChanged)
        case let .workspaceChanged(projectId): self.init(kind: .workspaceChanged, projectId: projectId)
        }
    }
}
