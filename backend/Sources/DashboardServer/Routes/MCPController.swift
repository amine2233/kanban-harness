import DashboardMCP
import DashboardRuntime
import MCP
import Vapor

/// `POST /mcp`: the same tools over MCP's streamable HTTP transport, so
/// browser-side or remote agents can use the running server directly.
struct MCPController: RouteCollection {
    let transport: StatelessHTTPServerTransport

    func boot(routes: any RoutesBuilder) throws {
        routes.on(.POST, "mcp", body: .collect(maxSize: "1mb"), use: handle)
        routes.get("mcp", use: reject)
        routes.delete("mcp", use: reject)
    }

    func handle(req: Vapor.Request) async throws -> Vapor.Response {
        var headers: [String: String] = [:]
        for (name, value) in req.headers { headers[name] = value }
        let body = req.body.data.map { Data(buffer: $0) }
        let mcpResponse = await transport.handleRequest(MCP.HTTPRequest(method: "POST", headers: headers, body: body, path: req.url.path))
        return Self.response(from: mcpResponse)
    }

    func reject(req: Vapor.Request) -> Vapor.Response {
        Self.response(from: .error(statusCode: 405, .invalidRequest("Method Not Allowed"), extraHeaders: ["Allow": "POST"]))
    }

    static func response(from mcp: MCP.HTTPResponse) -> Vapor.Response {
        let response = Vapor.Response(status: HTTPResponseStatus(statusCode: mcp.statusCode))
        for (name, value) in mcp.headers { response.headers.replaceOrAdd(name: name, value: value) }
        switch mcp {
        case let .data(data, _):
            response.body = .init(data: data)
        case let .stream(stream, _):
            response.body = .init(asyncStream: { writer in
                for try await chunk in stream { try await writer.write(.buffer(ByteBuffer(data: chunk))) }
                try await writer.write(.end)
            })
        case .error:
            if let data = mcp.bodyData { response.body = .init(data: data) }
        case .accepted, .ok:
            break
        }
        return response
    }
}

/// Starts the shared MCP server over the stateless HTTP transport once per app.
enum MCPHost {
    static func start(_ app: Vapor.Application) async throws -> MCPController {
        let transport = StatelessHTTPServerTransport(logger: app.logger)
        let server = await DashboardMCPServer.make(
            projects: app.services.make(ProjectCommandsKey.self),
            boards: app.services.make(BoardCommandsKey.self)
        )
        try await server.start(transport: transport)
        app.lifecycle.use(StopMCP(server: server))
        return MCPController(transport: transport)
    }

    private struct StopMCP: LifecycleHandler {
        let server: MCP.Server
        func shutdownAsync(_ application: Vapor.Application) async {
            await server.stop()
        }
    }
}
