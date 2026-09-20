import DashboardAI
import DashboardDomain
import Foundation

/// Claude Code CLI in headless mode (`claude -p`): uses the machine's Claude
/// login, so no API key. Tools are disabled and `--json-schema` makes the
/// CLI return validated structured output. `baseURL` is unused; `model` is
/// passed through (`sonnet`, `opus`, or a full model id).
public struct ClaudeCodeProvider: AIProvider {
    public let config: AIProviderConfig
    let executable: String
    let timeout: TimeInterval

    public init(config: AIProviderConfig, executable: String? = nil, timeout: TimeInterval = 180) {
        self.config = config
        self.executable = executable ?? ProcessInfo.processInfo.environment["MVP_DASHBOARD_CLAUDE_BIN"] ?? "claude"
        self.timeout = timeout
    }

    public func complete(_ request: CompletionRequest) async throws -> CompletionResult {
        let schema = String(decoding: try JSONEncoder().encode(request.schema), as: UTF8.self)
        let arguments = [
            "-p", "--output-format", "json", "--no-session-persistence", "--tools", "", "--strict-mcp-config",
            "--model", config.model, "--system-prompt", request.system, "--json-schema", schema, request.prompt,
        ]
        let output = try await Subprocess.run(executable, arguments: arguments, timeout: timeout)
        guard let object = try? JSONSerialization.jsonObject(with: output) as? [String: Any] else {
            throw AIProviderError.badResponse("claude did not return JSON: \(String(decoding: output.prefix(300), as: UTF8.self))")
        }
        if object["is_error"] as? Bool == true {
            throw AIProviderError.request(object["result"] as? String ?? "claude reported an error")
        }
        let structured = object["structured_output"]
        let json: Data
        if let structured, !(structured is NSNull), JSONSerialization.isValidJSONObject(structured) {
            json = try JSONSerialization.data(withJSONObject: structured)
        } else if let text = object["result"] as? String, let extracted = JSONExtractor.firstObject(in: text) {
            json = extracted
        } else {
            throw AIProviderError.badResponse("claude returned no structured output")
        }
        let usage = object["usage"] as? [String: Any]
        return CompletionResult(
            json: json,
            usage: CompletionUsage(inputTokens: usage?["input_tokens"] as? Int, outputTokens: usage?["output_tokens"] as? Int, costUSD: object["total_cost_usd"] as? Double),
            model: config.model
        )
    }
}

/// Runs a command to completion with a timeout; stderr is discarded from the result but kept for errors.
enum Subprocess {
    static func run(_ executable: String, arguments: [String], timeout: TimeInterval) async throws -> Data {
        let process = Process()
        if executable.contains("/") {
            process.executableURL = URL(fileURLWithPath: executable)
        } else {
            process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
            process.arguments = [executable] + arguments
        }
        if executable.contains("/") { process.arguments = arguments }
        let stdout = Pipe()
        let stderr = Pipe()
        process.standardOutput = stdout
        process.standardError = stderr
        process.standardInput = FileHandle.nullDevice
        do {
            try process.run()
        } catch {
            throw AIProviderError.unavailable("cannot start '\(executable)': \(error.localizedDescription)")
        }
        let output = Task.detached { stdout.fileHandleForReading.readDataToEndOfFile() }
        let errors = Task.detached { stderr.fileHandleForReading.readDataToEndOfFile() }
        let deadline = Date().addingTimeInterval(timeout)
        while process.isRunning {
            if Date() > deadline {
                process.terminate()
                throw AIProviderError.unavailable("'\(executable)' timed out after \(Int(timeout))s")
            }
            try await Task.sleep(for: .milliseconds(50))
        }
        let data = await output.value
        guard process.terminationStatus == 0 else {
            let message = String(decoding: await errors.value.prefix(500), as: UTF8.self)
            throw AIProviderError.request("'\(executable)' exited with \(process.terminationStatus): \(message)")
        }
        return data
    }
}
