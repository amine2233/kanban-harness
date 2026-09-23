import DashboardDomain

/// Where provider secrets live, apart from the config file so that file can
/// be shared and the backend can differ per platform (file, Keychain…).
public protocol CredentialStore: Sendable {
    func get(_ providerId: String) async throws -> Credential?
    func set(_ credential: Credential, for providerId: String) async throws
    func remove(_ providerId: String) async throws
}

public actor CredentialStoreInMemory: CredentialStore {
    private var credentials: [String: Credential] = [:]

    public init() {}

    public func get(_ providerId: String) async throws -> Credential? {
        credentials[providerId]
    }

    public func set(_ credential: Credential, for providerId: String) async throws {
        credentials[providerId] = credential
    }

    public func remove(_ providerId: String) async throws {
        credentials[providerId] = nil
    }
}

extension StoreContract {
    /// used only for unit-test
    public static func verify(_ store: any CredentialStore) async throws {
        try await require(store.get("hf") == nil, "fresh store must be empty")
        let token = Credential(
            secret: "hf_abc",
            refreshToken: "r1",
            expiresAt: .timestamp().addingTimeInterval(3_600)
        )
        try await store.set(token, for: "hf")
        try await store.set(Credential(secret: "sk-or-1"), for: "router")
        try await require(store.get("hf") == token, "set then get must round-trip, expiry included")
        try await require(store.get("router")?.secret == "sk-or-1", "stores are keyed by provider")
        try await store.set(Credential(secret: "hf_new"), for: "hf")
        try await require(store.get("hf")?.refreshToken == nil, "set replaces the whole credential")
        try await store.remove("hf")
        try await require(store.get("hf") == nil, "remove must forget the credential")
        try await require(store.get("router") != nil, "remove must not touch the others")
    }
}
