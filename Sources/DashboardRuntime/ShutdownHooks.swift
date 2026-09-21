/// cascade-kit's storage shutdown hooks are synchronous; our resources
/// (SQLite pools, thread pools) shut down asynchronously, so the runtime
/// collects async hooks here and drains them last-registered-first.
public actor ShutdownHooks {
    private var hooks: [@Sendable () async -> Void] = []

    public init() {}

    public func add(_ hook: @escaping @Sendable () async -> Void) {
        hooks.append(hook)
    }

    public func drain() async {
        let pending = hooks.reversed()
        hooks.removeAll()
        for hook in pending {
            await hook()
        }
    }
}
