import DashboardRuntime
import Foundation
import Testing
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// Runs the built `dashboard` executable, the way a user would.
final class CLI {
    let home: String

    /// The `dashboard` product next to the test host (Linux), else under the
    /// package's `.build/<config>/` derived from this file's location (macOS).
    static var binary: URL {
        let candidates = [
            Bundle.main.bundleURL.appendingPathComponent("dashboard"),
            packageRoot.appendingPathComponent(".build/debug/dashboard"),
            packageRoot.appendingPathComponent(".build/release/dashboard"),
        ]
        return candidates.first { FileManager.default.isExecutableFile(atPath: $0.path) } ?? candidates[1]
    }

    private static var packageRoot: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }

    /// Each home gets its own daemon on its own port, so a dashboard running on
    /// the machine cannot interfere and tests stay independent.
    static var baseEnvironment: [String: String] {
        var environment = ProcessInfo.processInfo.environment
        environment.removeValue(forKey: "MVP_DASHBOARD_DAEMON_PORT")
        return environment
    }

    /// The daemon inherits the environment of whichever command started it, and
    /// it is the daemon that does the work — so anything read from the
    /// environment must be set on *every* invocation, not just the one that
    /// needs it.
    var extraEnvironment: [String: String] = [:]

    /// The home is not a flag any more, so a test isolates itself through the
    /// environment — which is also how the daemon inherits it.
    var environment: [String: String] {
        Self.baseEnvironment
            .merging(["MVP_DASHBOARD_HOME": home]) { $1 }
            .merging(extraEnvironment) { $1 }
    }

    init() throws {
        home = NSTemporaryDirectory() + "mvp-dashboard-cli-" + UUID().uuidString
        try FileManager.default.createDirectory(atPath: home, withIntermediateDirectories: true)
    }

    /// The daemon outlives the command that started it by design, so every
    /// fixture releases its home; otherwise a run leaves one daemon per test.
    deinit { stopDaemon() }

    func stopDaemon() {
        let process = Process()
        process.executableURL = Self.binary
        process.arguments = ["daemon", "stop"]
        process.environment = environment
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try? process.run()
        process.waitUntilExit()
    }

    private var baseArguments: [String] { [] }

    func tempFolder(_ name: String = "project") -> String {
        home + "/folders/" + name
    }

    @discardableResult
    func run(_ arguments: String...) throws -> (status: Int32, stdout: String, stderr: String) {
        let process = Process()
        process.executableURL = Self.binary
        process.environment = environment
        process.arguments = baseArguments + arguments
        let out = Pipe()
        let err = Pipe()
        process.standardOutput = out
        process.standardError = err
        try process.run()
        let stdout = String(decoding: out.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
        let stderr = String(decoding: err.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
        process.waitUntilExit()
        return (process.terminationStatus, stdout, stderr)
    }

    func json(_ arguments: String...) throws -> Any {
        let result = try run(arguments.first!, Array(arguments.dropFirst()))
        #expect(result.status == 0, "stderr: \(result.stderr)")
        return try JSONSerialization.jsonObject(with: Data(result.stdout.utf8))
    }

    private func run(_ first: String, _ rest: [String]) throws -> (status: Int32, stdout: String, stderr: String) {
        let process = Process()
        process.executableURL = Self.binary
        process.environment = environment
        process.arguments = baseArguments + [first] + rest
        let out = Pipe()
        let err = Pipe()
        process.standardOutput = out
        process.standardError = err
        try process.run()
        let stdout = String(decoding: out.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
        let stderr = String(decoding: err.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
        process.waitUntilExit()
        return (process.terminationStatus, stdout, stderr)
    }
}

@Suite(.serialized) struct CLITests {
    @Test func projectListStartsEmpty() throws {
        let cli = try CLI()
        #expect((try cli.json("project", "list") as? [Any])?.isEmpty == true)
    }

    @Test func projectAddDefaultsNameToFolderAndSeedsWorkspace() throws {
        let cli = try CLI()
        let folder = cli.tempFolder("Alpha Project")
        let created = try #require(try cli.json("project", "add", folder) as? [String: Any])
        #expect(created["name"] as? String == "Alpha Project")
        #expect(created["storage"] as? String == "json")
        #expect(FileManager.default.fileExists(atPath: folder + "/kanban.json"))
        #expect(FileManager.default.fileExists(atPath: cli.home + "/projects.sqlite"))
    }

    @Test func projectAddResolvesRelativePathsAgainstCwd() throws {
        let cli = try CLI()
        let cwd = FileManager.default.currentDirectoryPath
        let created = try #require(try cli.json("project", "add", "relative-demo-\(UUID().uuidString)", "--name", "Rel") as? [String: Any])
        let path = try #require(created["path"] as? String)
        #expect(path.hasPrefix("/"))
        #expect(path.hasPrefix(URL(fileURLWithPath: cwd).standardizedFileURL.path))
        try? FileManager.default.removeItem(atPath: path)
    }

    @Test func projectAddDuplicateNameFailsWithJSONError() throws {
        let cli = try CLI()
        _ = try cli.json("project", "add", cli.tempFolder("a"), "--name", "Dup")
        let result = try cli.run("project", "add", cli.tempFolder("b"), "--name", "dup")
        #expect(result.status == 1)
        #expect(result.stderr.contains("already exists"))
        #expect(result.stderr.hasPrefix("{\"error\""))
    }

    @Test func projectShowAndRemoveByNameAndId() throws {
        let cli = try CLI()
        let folder = cli.tempFolder("gamma")
        let created = try #require(try cli.json("project", "add", folder, "--name", "Gamma") as? [String: Any])
        let id = try #require(created["id"] as? String)
        #expect((try cli.json("project", "show", "gamma") as? [String: Any])?["id"] as? String == id)
        #expect((try cli.json("project", "remove", id) as? [String: Any])?["name"] as? String == "Gamma")
        #expect((try cli.json("project", "list") as? [Any])?.isEmpty == true)
        #expect(FileManager.default.fileExists(atPath: folder + "/kanban.json"), "files are kept")
    }

    @Test func projectRemoveUnknownFails() throws {
        let cli = try CLI()
        let result = try cli.run("project", "remove", "ghost")
        #expect(result.status == 1)
        #expect(result.stderr.contains("not found"))
    }

    @Test func projectBoardsListsSeededBoard() throws {
        let cli = try CLI()
        _ = try cli.json("project", "add", cli.tempFolder("delta"), "--name", "Delta")
        let boards = try #require(try cli.json("project", "boards", "Delta") as? [[String: Any]])
        #expect(boards.count == 1)
        #expect(boards[0]["name"] as? String == "Delta")
        #expect(boards[0]["position"] as? Int == 0)
        #expect(boards[0].keys.contains("card_prefix"))
    }

    @Test func projectStorageConvertsBetweenFormats() throws {
        let cli = try CLI()
        let folder = cli.tempFolder("conv")
        _ = try cli.json("project", "add", folder, "--name", "Conv")
        let sqlite = try #require(try cli.json("project", "storage", "Conv", "sqlite") as? [String: Any])
        #expect(sqlite["storage"] as? String == "sqlite")
        #expect(FileManager.default.fileExists(atPath: folder + "/kanban.sqlite"))
        let boards = try #require(try cli.json("project", "boards", "Conv") as? [[String: Any]])
        #expect(boards.first?["name"] as? String == "Conv")
        let json = try #require(try cli.json("project", "storage", "Conv", "json") as? [String: Any])
        #expect(json["storage"] as? String == "json")
    }

    @Test func projectAddWithSQLiteStorage() throws {
        let cli = try CLI()
        let folder = cli.tempFolder("sq")
        let created = try #require(try cli.json("project", "add", folder, "--storage", "sqlite") as? [String: Any])
        #expect(created["storage"] as? String == "sqlite")
        #expect(FileManager.default.fileExists(atPath: folder + "/kanban.sqlite"))
    }

    @Test func registryPersistsBetweenInvocations() throws {
        let cli = try CLI()
        _ = try cli.json("project", "add", cli.tempFolder("p"), "--name", "Persist")
        let listed = try #require(try cli.json("project", "list") as? [[String: Any]])
        #expect(listed.first?["name"] as? String == "Persist")
    }

    @Test func unknownStorageIsRejectedByTheParser() throws {
        let cli = try CLI()
        let result = try cli.run("project", "add", cli.tempFolder("x"), "--storage", "yaml")
        #expect(result.status != 0)
        #expect(result.stderr.contains("storage"))
    }

    @Test func serveAnswersHealthUntilTerminated() async throws {
        let cli = try CLI()
        let port = Int.random(in: 20000 ... 40000)
        let process = Process()
        process.executableURL = CLI.binary
        process.arguments = ["serve", "--port", String(port)]
        process.environment = cli.environment
        process.standardOutput = Pipe()
        process.standardError = Pipe()
        try process.run()
        defer { process.terminate() }

        var body: String?
        for _ in 0 ..< 50 {
            if let data = try? await URLSession.shared.data(from: URL(string: "http://127.0.0.1:\(port)/api/health")!).0 {
                body = String(decoding: data, as: UTF8.self)
                break
            }
            try await Task.sleep(for: .milliseconds(100))
        }
        #expect(body == #"{"status":"ok"}"#)
    }

    @Test func settingsShowAndSetPersistToSettingsFile() throws {
        let cli = try CLI()
        let initial = try #require(try cli.json("settings", "show") as? [String: Any])
        #expect(initial["default_storage"] as? String == "json")
        let updated = try #require(try cli.json("settings", "set", "--default-storage", "sqlite", "--cors-origin", "http://localhost:5173/", "http://127.0.0.1:5173") as? [String: Any])
        #expect(updated["default_storage"] as? String == "sqlite")
        #expect(updated["cors_origins"] as? [String] == ["http://localhost:5173", "http://127.0.0.1:5173"])
        #expect(FileManager.default.fileExists(atPath: cli.home + "/settings.json"))
        let cleared = try #require(try cli.json("settings", "set", "--clear-cors") as? [String: Any])
        #expect(cleared["cors_origins"] as? [String] == [])
        #expect(cleared["default_storage"] as? String == "sqlite", "unrelated fields are kept")
        let created = try #require(try cli.json("project", "add", cli.tempFolder("def")) as? [String: Any])
        #expect(created["storage"] as? String == "sqlite", "project add follows default_storage")
        let bad = try cli.run("settings", "set", "--cors-origin", "nope")
        #expect(bad.status == 1)
        #expect(bad.stderr.contains("invalid origin"))
    }

    @Test func homeFallsBackToEnvironmentWhenFlagIsAbsent() throws {
        let cli = try CLI()
        let process = Process()
        process.executableURL = CLI.binary
        process.arguments = ["project", "list"]
        process.environment = ProcessInfo.processInfo.environment.merging(["MVP_DASHBOARD_HOME": cli.home]) { $1 }
        let out = Pipe()
        process.standardOutput = out
        process.standardError = Pipe()
        try process.run()
        let stdout = String(decoding: out.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
        process.waitUntilExit()
        #expect(process.terminationStatus == 0)
        #expect(stdout.trimmingCharacters(in: .whitespacesAndNewlines).hasPrefix("["))
        #expect(FileManager.default.fileExists(atPath: cli.home + "/projects.sqlite"))
    }

    /// Migrations belong to the daemon now, so they show up in *its* stderr, not
    /// in the stderr of a command that merely asked it something.
    @Test func verboseFlagTurnsOnInfoLogsInTheDaemon() throws {
        let cli = try CLI()
        #expect(!(try cli.run("project", "list")).stderr.contains("Migrator"), "a command's own stderr stays quiet")

        let daemon = try CLI()
        let process = Process()
        process.executableURL = CLI.binary
        process.arguments = ["--verbose", "daemon", "run"]
        process.environment = daemon.environment
        let err = Pipe()
        process.standardOutput = FileHandle.nullDevice
        process.standardError = err
        try process.run()
        defer { process.terminate() }

        var stderr = ""
        let deadline = Date().addingTimeInterval(10)
        while Date() < deadline, !stderr.contains("Migrator") {
            stderr += String(decoding: err.fileHandleForReading.availableData, as: UTF8.self)
        }
        #expect(stderr.contains("Migrator"), "the daemon reports its own migrations")
    }

    /// Starts `dashboard serve` on a free port and returns (process, port).
    func startServer(_ cli: CLI) throws -> (Process, Int) {
        let port = Int.random(in: 20000 ... 40000)
        let process = Process()
        process.executableURL = CLI.binary
        process.arguments = ["serve", "--port", String(port)]
        process.environment = cli.environment
        process.standardOutput = Pipe()
        process.standardError = Pipe()
        try process.run()
        return (process, port)
    }

    func waitForHealth(port: Int) async throws {
        for _ in 0 ..< 50 {
            if (try? await URLSession.shared.data(from: URL(string: "http://127.0.0.1:\(port)/api/health")!)) != nil { return }
            try await Task.sleep(for: .milliseconds(100))
        }
        Issue.record("server did not come up")
    }

    @Test func cliRoutesThroughItsOwnDaemonAndHonoursAnExplicitServer() async throws {
        let serverFixture = try CLI()
        let (server, port) = try startServer(serverFixture)
        defer { server.terminate() }
        try await waitForHealth(port: port)

        let cli = try CLI()
        let created = try #require(try cli.json("--server", "http://127.0.0.1:\(port)", "project", "add", cli.tempFolder("via-server"), "--name", "Via server") as? [String: Any])
        #expect(created["name"] as? String == "Via server")
        let (data, _) = try await URLSession.shared.data(from: URL(string: "http://127.0.0.1:\(port)/api/projects")!)
        let serverSide = try #require(try JSONSerialization.jsonObject(with: data) as? [[String: Any]])
        #expect(serverSide.map { $0["name"] as? String } == ["Via server"], "the server's registry received it")
        #expect(!FileManager.default.fileExists(atPath: cli.home + "/projects.sqlite"), "--server means no daemon was started for this home")

        let own = try #require(try cli.json("project", "list") as? [Any])
        #expect(own.isEmpty, "without --server the CLI starts a daemon for its own home, which is empty")
        #expect(FileManager.default.fileExists(atPath: cli.home + "/" + RuntimeConfig.daemonPortFileName), "the daemon published its port")

        let unreachable = try cli.run("--server", "http://127.0.0.1:1", "project", "list")
        #expect(unreachable.status == 1, "an explicit server that does not answer fails; there is no local fallback left to silently corrupt files")
    }

    @Test func aiProvidersAreEditedThroughTheCLIAndStoredInConfigJSON() throws {
        let cli = try CLI()
        #expect(((try cli.json("ai", "providers", "list") as? [String: Any])?["providers"] as? [Any])?.isEmpty == true)
        let added = try #require(try cli.json("ai", "providers", "add", "claude", "--kind", "anthropic", "--model", "claude-sonnet-5", "--api-key", "sk-cli") as? [String: Any])
        #expect(added["default_provider"] as? String == "claude")
        let provider = try #require((added["providers"] as? [[String: Any]])?.first)
        #expect(provider["has_api_key"] as? Bool == true)
        #expect(provider["api_key"] == nil, "the key is never printed")
        #expect(!(try String(contentsOfFile: cli.home + "/config.json", encoding: .utf8)).contains("sk-cli"), "secrets never land in the config file")
        #expect(try String(contentsOfFile: cli.home + "/credentials.json", encoding: .utf8).contains("sk-cli"))

        _ = try cli.json("ai", "providers", "add", "local", "--kind", "ollama", "--model", "llama3.2", "--base-url", "http://127.0.0.1:11434")
        #expect((try cli.json("ai", "providers", "default", "local") as? [String: Any])?["default_provider"] as? String == "local")
        #expect(((try cli.json("ai", "providers", "remove", "claude") as? [String: Any])?["providers"] as? [Any])?.count == 1)
        #expect(try cli.run("ai", "providers", "add", "Bad Id", "--kind", "ollama", "--model", "m").status == 1)
        #expect(try cli.run("ai", "providers", "add", "x", "--kind", "magic", "--model", "m").status != 0)
    }

    @Test func mcpOverStdioAnswersInitializeAndToolsList() throws {
        let cli = try CLI()
        _ = try cli.json("project", "add", cli.tempFolder("mcp"), "--name", "MCP demo")
        let process = Process()
        process.executableURL = CLI.binary
        process.arguments = ["mcp"]
        process.environment = cli.environment
        let input = Pipe(), output = Pipe()
        process.standardInput = input
        process.standardOutput = output
        process.standardError = Pipe()
        try process.run()
        let messages = [
            #"{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2025-06-18","capabilities":{},"clientInfo":{"name":"test","version":"1"}}}"#,
            #"{"jsonrpc":"2.0","method":"notifications/initialized"}"#,
            #"{"jsonrpc":"2.0","id":2,"method":"tools/call","params":{"name":"list_boards","arguments":{"project":"MCP demo"}}}"#,
        ]
        input.fileHandleForWriting.write(Data((messages.joined(separator: "\n") + "\n").utf8))
        var collected = Data()
        let deadline = Date().addingTimeInterval(10)
        while Date() < deadline {
            collected.append(output.fileHandleForReading.availableData)
            if String(decoding: collected, as: UTF8.self).components(separatedBy: "\n").filter({ $0.contains("\"id\"") }).count >= 2 { break }
        }
        process.terminate()
        let lines = String(decoding: collected, as: UTF8.self).split(separator: "\n").compactMap { try? JSONSerialization.jsonObject(with: Data($0.utf8)) as? [String: Any] }
        let initialize = try #require(lines.first { $0["id"] as? Int == 1 })
        #expect(((initialize["result"] as? [String: Any])?["serverInfo"] as? [String: Any])?["name"] as? String == "mvp-dashboard")
        let call = try #require(lines.first { $0["id"] as? Int == 2 })
        let structured = try #require((call["result"] as? [String: Any])?["structuredContent"] as? [String: Any])
        #expect((structured["items"] as? [[String: Any]])?.first?["name"] as? String == "MCP demo")
    }

    @Test func aiTicketDraftsAndOptionallyCreatesACard() throws {
        var cli = try CLI()
        let dir = NSTemporaryDirectory() + "claude-stub-" + UUID().uuidString
        try FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        let stub = dir + "/claude"
        try "#!/bin/sh\ncat > /dev/null\necho '{\"is_error\":false,\"result\":\"\",\"structured_output\":{\"title\":\"Drafted by CLI\",\"acceptance_criteria\":[\"ok\"],\"priority\":\"low\",\"subtasks\":[{\"title\":\"Part one\"},{\"title\":\"Part two\",\"points\":2}]}}'\n".write(toFile: stub, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: stub)
        cli.extraEnvironment["MVP_DASHBOARD_CLAUDE_BIN"] = stub
        let folder = cli.tempFolder("ai")
        _ = try cli.json("project", "add", folder, "--name", "AI demo")
        _ = try cli.json("ai", "providers", "add", "cc", "--kind", "claude_code", "--model", "sonnet")

        let run = { (args: [String]) throws -> ([String: Any], String) in
            let p = Process()
            p.executableURL = CLI.binary
            p.arguments = args
            p.environment = cli.environment
            let out = Pipe()
            let err = Pipe()
            p.standardOutput = out
            p.standardError = err
            try p.run()
            let data = out.fileHandleForReading.readDataToEndOfFile()
            let stderr = String(decoding: err.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
            p.waitUntilExit()
            return (try JSONSerialization.jsonObject(with: data) as? [String: Any] ?? [:], stderr)
        }
        let process = { (args: [String]) throws -> [String: Any] in try run(args).0 }
        let drafted = try process(["ai", "ticket", "AI demo", "password reset"])
        #expect((drafted["draft"] as? [String: Any])?["title"] as? String == "Drafted by CLI")
        #expect(drafted["provider"] as? String == "cc")
        let (streamed, narration) = try run(["ai", "ticket", "AI demo", "password reset", "--stream"])
        #expect((streamed["draft"] as? [String: Any])?["title"] as? String == "Drafted by CLI", "stdout stays JSON")
        #expect(narration.contains("] resolve: cc (sonnet)") && narration.contains("] done"))
        let created = try process(["ai", "ticket", "AI demo", "password reset", "--create", "--column", "To do"])
        #expect(created["key"] as? String == "task-1")
        let file = try String(contentsOfFile: folder + "/kanban.json", encoding: .utf8)
        #expect(file.contains(#""ai_cost""#) && file.contains(#""provider" : "cc""#), "the created card remembers its draft cost")
        #expect(file.contains("Part one") && file.contains("Part two"), "sub-tasks are created with the card")
        #expect(file.components(separatedBy: #""source" :"#).count == 3, "two spawns edges link them to the parent")
        let boards = try #require(try cli.json("project", "boards", "AI demo") as? [[String: Any]])
        #expect(boards.count == 1)
    }

    @Test func helpListsSubcommands() throws {
        let result = try CLI().run("--help")
        #expect(result.status == 0)
        #expect(result.stdout.contains("project"))
        #expect(result.stdout.contains("serve"))
    }
}
