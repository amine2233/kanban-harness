import DashboardDomain
import DashboardPersistence
import FluentKit

/// Project registry on any Fluent database (SQLite in production). `save`
/// replaces the whole table in one transaction, matching the `ProjectStore` contract.
public struct FluentProjectStore: ProjectStore {
    public let database: any Database

    public static let migrations: [any Migration] = [CreateProjects()]

    public init(database: any Database) {
        self.database = database
    }

    public func load() async throws -> [Project] {
        try await ProjectModel.query(on: database)
            .sort(\.$createdAt)
            .all()
            .map { try $0.toDomain() }
    }

    public func save(_ projects: [Project]) async throws {
        try await database.transaction { transaction in
            try await ProjectModel.query(on: transaction).delete()
            for project in projects {
                try await ProjectModel(project).create(on: transaction)
            }
        }
    }
}
