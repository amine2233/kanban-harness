/// Same `{code, message}` envelope kanban-server uses, so the frontend has one error shape.
public struct ApiError: Codable, Sendable, Equatable {
    public let code: String
    public let message: String

    public init(code: String, message: String) {
        self.code = code
        self.message = message
    }
}
