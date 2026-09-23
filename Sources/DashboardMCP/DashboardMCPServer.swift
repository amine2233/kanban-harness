import DashboardDomain
import DashboardService
import Logging
import MCP

/// Builds the MCP server that exposes boards and cards as tools. Transport
/// (stdio, HTTP) is chosen by the host; the tools only see command protocols.
public enum DashboardMCPServer {
    public static let name = "mvp-dashboard"
    public static let version = DashboardVersion.declared

    public static func make(projects: any ProjectCommands, boards: any BoardCommands) async -> Server {
        let server = Server(
            name: name,
            version: version,
            instructions: "Kanban boards for registered projects. Refer to projects, boards and columns by name or id; cards by id, number or key (task-12).",
            capabilities: .init(tools: .init(listChanged: false))
        )
        let dispatcher = KanbanToolDispatcher(projects: projects, boards: boards)
        await server.withMethodHandler(ListTools.self) { _ in .init(tools: KanbanTools.all) }
        await server.withMethodHandler(CallTool.self) { params in
            await dispatcher.call(params.name, params.arguments ?? [:])
        }
        return server
    }
}
