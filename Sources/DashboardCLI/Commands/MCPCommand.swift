import ArgumentParser
import DashboardMCP
import DashboardRuntime
import MCP

struct MCPCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "mcp",
        abstract: "Serve boards and cards as MCP tools over stdio (for Claude Code, Claude Desktop, …).",
        discussion: """
        Add to an MCP client:
          { "mcpServers": { "dashboard": { "command": "dashboard", "args": ["mcp"] } } }
        With a dashboard server running the tools go through it (single writer, live updates);
        otherwise they work on the files directly. Logs go to stderr; stdout is the protocol.
        """
    )

    @OptionGroup var global: GlobalOptions

    func run() async throws {
        try await failing {
            try await Runtime.run(global) { services in
                let server = await DashboardMCPServer.make(
                    projects: services.make(ProjectCommandsKey.self),
                    boards: services.make(BoardCommandsKey.self)
                )
                try await server.start(transport: StdioTransport())
                await server.waitUntilCompleted()
            }
        }
    }
}
