import DashboardAI
import DashboardDomain
import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// Minimal JSON-over-HTTP helper shared by the vendor clients.
struct HTTPJSON: Sendable {
    let session: URLSession
    let timeout: TimeInterval

    init(session: URLSession = .shared, timeout: TimeInterval = 120) {
        self.session = session
        self.timeout = timeout
    }

    func post(_ url: URL, headers: [String: String], body: [String: Any]) async throws -> [String: Any] {
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = timeout
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        for (name, value) in headers { request.setValue(value, forHTTPHeaderField: name) }
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            throw AIProviderError.unavailable("\(url.host ?? url.absoluteString): \(error.localizedDescription)")
        }
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard (200 ..< 300).contains(status) else {
            let text = String(decoding: data.prefix(500), as: UTF8.self)
            throw AIProviderError.request("HTTP \(status) from \(url.host ?? ""): \(text)")
        }
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw AIProviderError.badResponse("non-JSON body from \(url.host ?? "")")
        }
        return object
    }
}

extension JSONValue {
    /// Foundation object for embedding a schema in a vendor request body.
    var foundationObject: Any {
        switch self {
        case .null: NSNull()
        case let .bool(b): b
        case let .number(n): n.rounded() == n && abs(n) < 1e15 ? Int(n) : n
        case let .string(s): s
        case let .array(a): a.map(\.foundationObject)
        case let .object(o): o.mapValues(\.foundationObject)
        }
    }
}
