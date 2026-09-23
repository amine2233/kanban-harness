import DashboardDomain
import DashboardPersistence
import FluentKit
import Foundation

/// Fluent row for the project registry. Kept out of the domain: `Project`
/// stays a validated value type, this is only its table mapping.
public final class ProjectModel: Model, @unchecked Sendable {
    public static let schema = "projects"

    @ID(custom: .id, generatedBy: .user)
    public var id: UUID?

    @Field(key: "name")
    public var name: String

    @Field(key: "path")
    public var path: String

    @Field(key: "storage")
    public var storage: String

    @Field(key: "created_at")
    public var createdAt: Date

    public init() {}

    convenience init(_ project: Project) {
        self.init()
        self.id = project.id
        self.name = project.name
        self.path = project.path
        self.storage = project.storage.rawValue
        self.createdAt = project.createdAt
    }

    func toDomain() throws -> Project {
        guard let id, let storage = StorageKind(rawValue: storage) else {
            throw PersistenceError.corrupt(
                path: Self.schema,
                reason: "row \(String(describing: self.id)) has unknown storage '\(self.storage)'"
            )
        }

        // SQLite keeps the date as a REAL; snap the float noise back to the microsecond the domain wrote.
        return try Project(
            name: name,
            path: path,
            storage: storage,
            id: id,
            createdAt: createdAt.quantizedToMicroseconds
        )
    }
}

public struct CreateProjects: AsyncMigration {
    public init() {}

    public func prepare(on database: any Database) async throws {
        try await database.schema(ProjectModel.schema)
            .id()
            .field("name", .string, .required)
            .field("path", .string, .required)
            .field("storage", .string, .required)
            .field("created_at", .datetime, .required)
            .unique(on: "path")
            .create()
    }

    public func revert(on database: any Database) async throws {
        try await database.schema(ProjectModel.schema).delete()
    }
}
