import DashboardAPI
import DashboardDomain
import DashboardPersistence
import DashboardService
import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// HTTP client for a running dashboard server: the remote implementation of
/// the service command protocols, speaking the same `/api` the web app uses.
public struct DashboardClient: Sendable {
    public let baseURL: URL
    private let session: URLSession
    private let timeout: TimeInterval

    public init(baseURL: URL, session: URLSession = .shared, timeout: TimeInterval = 10) {
        self.baseURL = baseURL
        self.session = session
        self.timeout = timeout
    }

    /// True when `/api/health` answers within `timeout`.
    public func isReachable(timeout: TimeInterval = 0.5) async -> Bool {
        var request = URLRequest(url: baseURL.appending(path: "api/health"))
        request.timeoutInterval = timeout
        guard let (_, response) = try? await session.data(for: request) else { return false }
        return (response as? HTTPURLResponse)?.statusCode == 200
    }

    // MARK: Transport

    func send<Body: Encodable, Out: Decodable>(_ method: String, _ path: String, body: Body?, as _: Out.Type) async throws(ServiceError) -> Out {
        let data = try await raw(method, path, body: body)
        do {
            return try Self.decoder.decode(Out.self, from: data)
        } catch {
            throw .remote(code: "BAD_RESPONSE", message: "cannot decode \(method) \(path): \(error)")
        }
    }

    func send<Body: Encodable>(_ method: String, _ path: String, body: Body?) async throws(ServiceError) {
        _ = try await raw(method, path, body: body)
    }

    private func raw<Body: Encodable>(_ method: String, _ path: String, body: Body?) async throws(ServiceError) -> Data {
        guard let url = URL(string: path, relativeTo: baseURL.appending(path: "")) else {
            throw .remote(code: "BAD_REQUEST", message: "invalid path \(path)")
        }
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.timeoutInterval = timeout
        if let body {
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            do {
                request.httpBody = try Self.encoder.encode(body)
            } catch {
                throw .remote(code: "BAD_REQUEST", message: String(describing: error))
            }
        }
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            throw .unreachable(url: baseURL.absoluteString, reason: error.localizedDescription)
        }
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard (200 ..< 300).contains(status) else {
            if let apiError = try? Self.decoder.decode(ApiError.self, from: data) {
                throw .remote(code: apiError.code, message: apiError.message)
            }
            throw .remote(code: "HTTP_\(status)", message: String(decoding: data, as: UTF8.self))
        }
        return data
    }

    /// Sends `body` with `Accept: text/event-stream` and yields the response
    /// line by line (no timeout: a draft takes as long as the model takes).
    /// A non-2xx status is surfaced as the API's error envelope.
    func eventStream<Body: Encodable>(_ method: String, _ path: String, body: Body) -> AsyncThrowingStream<String, any Error> {
        AsyncThrowingStream { continuation in
            guard let url = URL(string: path, relativeTo: baseURL.appending(path: "")) else {
                continuation.finish(throwing: ServiceError.remote(code: "BAD_REQUEST", message: "invalid path \(path)"))
                return
            }
            var request = URLRequest(url: url)
            request.httpMethod = method
            request.timeoutInterval = 600
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.setValue("text/event-stream", forHTTPHeaderField: "Accept")
            do {
                request.httpBody = try Self.encoder.encode(body)
            } catch {
                continuation.finish(throwing: ServiceError.remote(code: "BAD_REQUEST", message: String(describing: error)))
                return
            }
            let delegate = LineDelegate(continuation: continuation, server: baseURL.absoluteString)
            let task = URLSession(configuration: .ephemeral, delegate: delegate, delegateQueue: nil).dataTask(with: request)
            task.resume()
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    static let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        RFC3339.configure(encoder)
        return encoder
    }()

    static let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        RFC3339.configure(decoder)
        return decoder
    }()
}

struct Empty: Encodable {}

/// Splits a streaming response into lines; a failure status is collected and
/// decoded as an `ApiError` when the response ends.
private final class LineDelegate: NSObject, URLSessionDataDelegate, @unchecked Sendable {
    private let continuation: AsyncThrowingStream<String, any Error>.Continuation
    private let server: String
    private var status = 0
    private var buffer = Data()

    init(continuation: AsyncThrowingStream<String, any Error>.Continuation, server: String) {
        self.continuation = continuation
        self.server = server
    }

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive response: URLResponse, completionHandler: @escaping (URLSession.ResponseDisposition) -> Void) {
        status = (response as? HTTPURLResponse)?.statusCode ?? 0
        completionHandler(.allow)
    }

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        buffer.append(data)
        guard (200 ..< 300).contains(status) else { return }
        while let newline = buffer.firstIndex(of: UInt8(ascii: "\n")) {
            continuation.yield(String(decoding: buffer[buffer.startIndex ..< newline], as: UTF8.self))
            buffer.removeSubrange(buffer.startIndex ... newline)
        }
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: (any Error)?) {
        defer { session.finishTasksAndInvalidate() }
        if let error {
            continuation.finish(throwing: ServiceError.unreachable(url: server, reason: error.localizedDescription))
        } else if (200 ..< 300).contains(status) {
            continuation.yield("")
            continuation.finish()
        } else if let apiError = try? DashboardClient.decoder.decode(ApiError.self, from: buffer) {
            continuation.finish(throwing: ServiceError.remote(code: apiError.code, message: apiError.message))
        } else {
            continuation.finish(throwing: ServiceError.remote(code: "HTTP_\(status)", message: String(decoding: buffer, as: UTF8.self)))
        }
    }
}
