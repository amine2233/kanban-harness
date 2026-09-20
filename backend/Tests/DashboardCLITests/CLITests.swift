import Foundation
import Testing
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// Runs the built `dashboard` executable, the way a user would.
struct CLI {
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

    init() throws {
        home = NSTemporaryDirectory() + "mvp-dashboard-cli-" + UUID().uuidString
        try FileManager.default.createDirectory(atPath: home, withIntermediateDirectories: true)
    }

    func tempFolder(_ name: String = "project") -> String {
        home + "/folders/" + name
    }

    @discardableResult
    func run(_ arguments: String...) throws -> (status: Int32, stdout: String, stderr: String) {
        let process = Process()
        process.executableURL = Self.binary
        process.arguments = ["--home", home] + arguments
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
        process.arguments = ["--home", home, first] + rest
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
        process.arguments = ["--home", cli.home, "serve", "--port", String(port)]
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

    @Test func verboseFlagTurnsOnInfoLogs() throws {
        let quiet = try CLI()
        #expect(!(try quiet.run("project", "list")).stderr.contains("Migrator"))
        let verbose = try CLI()
        #expect((try verbose.run("--verbose", "project", "list")).stderr.contains("Migrator"))
    }

    /// Starts `dashboard serve` on a free port and returns (process, port).
    func startServer(home: String) throws -> (Process, Int) {
        let port = Int.random(in: 20000 ... 40000)
        let process = Process()
        process.executableURL = CLI.binary
        process.arguments = ["--home", home, "serve", "--port", String(port)]
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

    @Test func cliRoutesThroughARunningServerAndFallsBackToLocal() async throws {
        let serverHome = try CLI().home
        let (server, port) = try startServer(home: serverHome)
        defer { server.terminate() }
        try await waitForHealth(port: port)

        let cli = try CLI()
        let created = try #require(try cli.json("--server", "http://127.0.0.1:\(port)", "project", "add", cli.tempFolder("via-server"), "--name", "Via server") as? [String: Any])
        #expect(created["name"] as? String == "Via server")
        let (data, _) = try await URLSession.shared.data(from: URL(string: "http://127.0.0.1:\(port)/api/projects")!)
        let serverSide = try #require(try JSONSerialization.jsonObject(with: data) as? [[String: Any]])
        #expect(serverSide.map { $0["name"] as? String } == ["Via server"], "the server's registry received it")
        #expect(!FileManager.default.fileExists(atPath: cli.home + "/projects.sqlite"), "no local registry was touched")

        let local = try #require(try cli.json("--server", "http://127.0.0.1:\(port)", "--local", "project", "list") as? [Any])
        #expect(local.isEmpty, "--local ignores the server and reads this home's (empty) registry")

        let noServer = try cli.run("--server", "http://127.0.0.1:1", "--remote", "project", "list")
        #expect(noServer.status == 1)
        #expect(noServer.stderr.contains("unreachable"))

        let fallback = try #require(try cli.json("--server", "http://127.0.0.1:1", "project", "list") as? [Any])
        #expect(fallback.isEmpty, "without --remote the CLI falls back to local files")
    }

    @Test func helpListsSubcommands() throws {
        let result = try CLI().run("--help")
        #expect(result.status == 0)
        #expect(result.stdout.contains("project"))
        #expect(result.stdout.contains("serve"))
    }
}
