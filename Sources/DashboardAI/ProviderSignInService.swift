import DashboardDomain
import DashboardOAuth
import DashboardPersistence
import DashboardService
import Foundation

/// Browser sign-in for a provider, and keeping its token fresh.
public protocol SignInCommands: Sendable {
    /// Starts a sign-in; the URL is what the browser must open. `callback` is
    /// where the vendor sends the user back — the server's own `/api/auth/callback`.
    func begin(providerId: String, callback: URL) async throws(ServiceError) -> URL
    /// Finishes it from the vendor's redirect; returns the provider signed in.
    func complete(state: String, code: String) async throws(ServiceError) -> String
    /// Forgets the stored credential. Nothing is revoked at the vendor — the key or
    /// token stays valid there until the user revokes it on the vendor's site.
    func signOut(providerId: String) async throws(ServiceError)
    /// The config with a usable secret: renews an OAuth token about to expire.
    func refreshed(_ config: AIProviderConfig) async throws(ServiceError) -> AIProviderConfig
}

public actor ProviderSignInService: SignInCommands {
    private let aiConfig: any AIConfigCommands
    private let credentials: any CredentialStore
    private let registry: AIProviderRegistry
    private let sessions: SignInSessions
    private let changes: ChangeBroadcaster

    public init(
        aiConfig: any AIConfigCommands,
        credentials: any CredentialStore,
        registry: AIProviderRegistry,
        sessions: SignInSessions = SignInSessions(),
        changes: ChangeBroadcaster = ChangeBroadcaster()
    ) {
        self.aiConfig = aiConfig
        self.credentials = credentials
        self.registry = registry
        self.sessions = sessions
        self.changes = changes
    }

    public func begin(providerId: String, callback: URL) async throws(ServiceError) -> URL {
        let (config, signIn) = try await resolve(providerId)
        let (state, verifier) = await sessions.begin(providerId: config.id, callback: callback)
        return signIn.authorizationURL(callback: callback, state: state, codeChallenge: PKCE.challenge(for: verifier))
    }

    public func complete(state: String, code: String) async throws(ServiceError) -> String {
        guard let pending = await sessions.consume(state) else { throw .remote(code: "SIGN_IN_FAILED", message: OAuthError.unknownState.message) }
        let (config, signIn) = try await resolve(pending.providerId)
        do {
            let credential = try await signIn.exchange(code: code, codeVerifier: pending.codeVerifier, callback: pending.callback)
            try await credentials.set(credential, for: config.id)
        } catch {
            throw Self.failure(error)
        }
        await changes.publish(.aiConfigChanged)
        return config.id
    }

    public func signOut(providerId: String) async throws(ServiceError) {
        do {
            try await credentials.remove(providerId)
        } catch {
            throw Self.failure(error)
        }
        await changes.publish(.aiConfigChanged)
    }

    /// Renews and stores a token that is about to expire; kinds without a sign-in pass through.
    public func refreshed(_ config: AIProviderConfig) async throws(ServiceError) -> AIProviderConfig {
        guard let signIn = try? registry.signIn(for: config) else { return config }
        do {
            guard let stored = try await credentials.get(config.id), stored.isExpiring() else { return config }
            guard let renewed = try await signIn.refresh(stored) else { return config }
            try await credentials.set(renewed, for: config.id)
            var fresh = config
            fresh.apiKey = renewed.secret
            return fresh
        } catch {
            throw Self.failure(error)
        }
    }

    private func resolve(_ providerId: String) async throws(ServiceError) -> (AIProviderConfig, any ProviderSignIn) {
        guard let config = try await aiConfig.current().provider(providerId) else { throw .domain(.providerNotFound(providerId)) }
        do {
            return (config, try registry.signIn(for: config))
        } catch {
            throw Self.failure(error)
        }
    }

    private static func failure(_ error: any Error) -> ServiceError {
        switch error {
        case let error as ServiceError: error
        case let error as OAuthError: .remote(code: "SIGN_IN_FAILED", message: error.message)
        case let error as AIProviderError: .remote(code: "SIGN_IN_FAILED", message: error.localizedDescription)
        default: .remote(code: "SIGN_IN_FAILED", message: String(describing: error))
        }
    }
}
