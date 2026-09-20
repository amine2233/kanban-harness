import Foundation

/// Wire format of a live change notification (`GET /api/events`, WebSocket text frames).
/// `{"kind": "hello"}` is sent once on connect.
public struct ChangeEventDTO: Codable, Equatable, Sendable {
    public enum Kind: String, Codable, Sendable {
        case hello
        case projectsChanged = "projects_changed"
        case workspaceChanged = "workspace_changed"
        case settingsChanged = "settings_changed"
    }

    public let kind: Kind
    public let projectId: UUID?

    enum CodingKeys: String, CodingKey {
        case kind
        case projectId = "project_id"
    }

    public init(kind: Kind, projectId: UUID? = nil) {
        self.kind = kind
        self.projectId = projectId
    }

    public static let hello = ChangeEventDTO(kind: .hello)
}
