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
        #expect(boards[0]["task_list_view"] as? String == "flat")
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

    @Test func helpListsSubcommands() throws {
        let result = try CLI().run("--help")
        #expect(result.status == 0)
        #expect(result.stdout.contains("project"))
        #expect(result.stdout.contains("serve"))
    }
}
