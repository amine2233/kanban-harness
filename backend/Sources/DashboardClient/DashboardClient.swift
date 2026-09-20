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
