import DashboardDomain
import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// The one HTTP call a token exchange needs, behind a protocol so vendor
/// modules are tested without a network.
public protocol HTTPTransport: Sendable {
    func post(_ url: URL, headers: [String: String], body: Data) async throws -> (status: Int, body: Data)
}

public struct URLSessionTransport: HTTPTransport {
    private let session: URLSession

    public init(timeout: TimeInterval = 30) {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = timeout
        self.session = URLSession(configuration: configuration)
    }

    public func post(
        _ url: URL,
        headers: [String: String],
        body: Data
    ) async throws -> (status: Int, body: Data) {
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.httpBody = body
        for (name, value) in headers {
            request.setValue(value, forHTTPHeaderField: name)
        }
        let (data, response) = try await session.data(for: request)
        return ((response as? HTTPURLResponse)?.statusCode ?? 0, data)
    }
}

extension HTTPTransport {
    /// `application/x-www-form-urlencoded` POST, the token-endpoint shape.
    public func postForm(
        _ url: URL,
        _ fields: [String: String],
        headers: [String: String] = [:]
    ) async throws -> (status: Int, body: Data) {
        let encoded = fields.sorted { $0.key < $1.key }.map { "\($0.key)=\(Self.formEncode($0.value))" }
            .joined(separator: "&")
        return try await post(
            url,
            headers: headers.merging(["Content-Type": "application/x-www-form-urlencoded"]) { $1 },
            body: Data(encoded.utf8)
        )
    }

    public func postJSON(
        _ url: URL,
        _ object: [String: Any],
        headers: [String: String] = [:]
    ) async throws -> (status: Int, body: Data) {
        let body = try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
        return try await post(
            url,
            headers: headers.merging(["Content-Type": "application/json"]) { $1 },
            body: body
        )
    }

    static func formEncode(_ value: String) -> String {
        var allowed = CharacterSet.alphanumerics
        allowed.insert(charactersIn: "-._~")
        return value.addingPercentEncoding(withAllowedCharacters: allowed) ?? value
    }
}

/// Decodes a standard token response (`access_token`, `refresh_token`, `expires_in`).
public enum TokenResponse {
    public static func credential(
        from data: Data,
        status: Int,
        now: Date = .timestamp()
    ) throws -> Credential {
        guard (200 ..< 300).contains(status) else {
            throw OAuthError.vendorRejected(status: status, body: String(decoding: data, as: UTF8.self))
        }
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw OAuthError.malformedResponse("token response is not a JSON object")
        }
        guard let token = object["access_token"] as? String, !token.isEmpty else {
            throw OAuthError.malformedResponse("token response has no access_token")
        }

        let expiresIn = (object["expires_in"] as? NSNumber)?.doubleValue
        return Credential(
            secret: token,
            refreshToken: object["refresh_token"] as? String,
            expiresAt: expiresIn.map { now.addingTimeInterval($0) }
        )
    }
}
