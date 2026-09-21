import DashboardAI
import DashboardDomain
import Foundation
import Synchronization

/// Claude Code CLI in headless mode (`claude -p`): uses the machine's Claude
/// login, so no API key. Tools are disabled and `--json-schema` makes the
/// CLI return validated structured output. `stream-json` with partial
/// messages lets us render the draft as it is typed. `baseURL` is unused;
/// `model` is passed through (`sonnet`, `opus`, or a full model id).
public struct ClaudeCodeProvider: AIProvider {
    public let config: AIProviderConfig
    let executable: String
    let timeout: TimeInterval

    public init(config: AIProviderConfig, executable: String, timeout: TimeInterval = 180) {
        self.config = config
        self.executable = executable
        self.timeout = timeout
    }

    public func stream(_ request: CompletionRequest) -> AsyncThrowingStream<CompletionEvent, any Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    let schema = String(decoding: try JSONEncoder().encode(request.schema), as: UTF8.self)
                    let arguments = [
                        "-p", "--output-format", "stream-json", "--verbose", "--include-partial-messages",
                        "--no-session-persistence", "--tools", "", "--strict-mcp-config",
                        "--model", config.model, "--system-prompt", request.system, "--json-schema", schema, request.prompt,
                    ]
                    var typed = ""
                    var finished = false
                    for try await line in Subprocess.lines(executable, arguments: arguments, timeout: timeout) {
                        try Task.checkCancellation()
                        guard let object = try? JSONSerialization.jsonObject(with: Data(line.utf8)) as? [String: Any] else { continue }
                        if object["is_error"] != nil {
                            let (json, usage) = try Self.finalOutput(object)
                            continuation.yield(.usage(usage))
                            continuation.yield(.done(json: json, model: config.model))
                            finished = true
                        } else if let delta = Self.delta(in: object) {
                            typed += delta
                            continuation.yield(.text(delta))
                            if let partial = Self.partialSnapshot(typed) { continuation.yield(.snapshot(partial)) }
                        }
                    }
                    guard finished else { throw AIProviderError.badResponse("claude ended without a result") }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    /// Text or tool-input fragments from `--include-partial-messages` events.
    private static func delta(in object: [String: Any]) -> String? {
        guard object["type"] as? String == "stream_event",
              let delta = (object["event"] as? [String: Any])?["delta"] as? [String: Any]
        else { return nil }
        return delta["text"] as? String ?? delta["partial_json"] as? String
    }

    /// The CLI sometimes streams the structured output as one escaped JSON
    /// string under a placeholder key (`{"$PARAMETER_NAME": "{\"title\": …`);
    /// unwrap that so partial drafts still render.
    static func partialSnapshot(_ typed: String) -> Data? {
        guard let completed = JSONCompleter.complete(typed) else { return nil }
        if let object = try? JSONSerialization.jsonObject(with: completed) as? [String: Any],
           object.count == 1, let inner = object.values.first as? String, inner.contains("{") {
            return JSONCompleter.complete(inner)
        }
        return completed
    }

    private static func finalOutput(_ object: [String: Any]) throws -> (Data, CompletionUsage) {
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
        return (json, CompletionUsage(inputTokens: usage?["input_tokens"] as? Int, outputTokens: usage?["output_tokens"] as? Int, costUSD: object["total_cost_usd"] as? Double))
    }
}

/// Runs a command and yields its stdout line by line; the stream fails on a
/// non-zero exit (with stderr), on a timeout, or when the consumer cancels.
enum Subprocess {
    private final class Handle: @unchecked Sendable {
        let process = Process()
        let timedOut = Mutex(false)
    }

    static func lines(_ executable: String, arguments: [String], timeout: TimeInterval) -> AsyncThrowingStream<String, any Error> {
        AsyncThrowingStream { continuation in
            let handle = Handle()
            let process = handle.process
            if executable.contains("/") {
                process.executableURL = URL(fileURLWithPath: executable)
                process.arguments = arguments
            } else {
                process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
                process.arguments = [executable] + arguments
            }
            let stdout = Pipe()
            let stderr = Pipe()
            process.standardOutput = stdout
            process.standardError = stderr
            process.standardInput = FileHandle.nullDevice
            do {
                try process.run()
            } catch {
                continuation.finish(throwing: AIProviderError.unavailable("cannot start '\(executable)': \(error.localizedDescription)"))
                return
            }
            let errors = Task.detached { stderr.fileHandleForReading.readDataToEndOfFile() }
            let watchdog = Task.detached {
                try await Task.sleep(for: .seconds(timeout))
                handle.timedOut.withLock { $0 = true }
                handle.process.terminate()
            }
            Task.detached {
                let reader = stdout.fileHandleForReading
                var buffer = Data()
                while true {
                    let chunk = reader.availableData
                    if chunk.isEmpty { break }
                    buffer.append(chunk)
                    while let newline = buffer.firstIndex(of: UInt8(ascii: "\n")) {
                        continuation.yield(String(decoding: buffer[buffer.startIndex ..< newline], as: UTF8.self))
                        buffer.removeSubrange(buffer.startIndex ... newline)
                    }
                }
                if !buffer.isEmpty { continuation.yield(String(decoding: buffer, as: UTF8.self)) }
                handle.process.waitUntilExit()
                watchdog.cancel()
                if handle.timedOut.withLock({ $0 }) {
                    continuation.finish(throwing: AIProviderError.unavailable("'\(executable)' timed out after \(Int(timeout))s"))
                } else if handle.process.terminationStatus != 0 {
                    let message = String(decoding: await errors.value.prefix(500), as: UTF8.self)
                    continuation.finish(throwing: AIProviderError.request("'\(executable)' exited with \(handle.process.terminationStatus): \(message)"))
                } else {
                    continuation.finish()
                }
            }
            continuation.onTermination = { _ in
                watchdog.cancel()
                if handle.process.isRunning { handle.process.terminate() }
            }
        }
    }
}
