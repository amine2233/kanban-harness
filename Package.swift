// swift-tools-version: 6.1
import PackageDescription

let package = Package(
    name: "mvp-dashboard-backend",
    platforms: [.macOS(.v15)],
    products: [
        .executable(name: "dashboard", targets: ["DashboardCLI"]),
        .library(name: "DashboardServer", targets: ["DashboardServer"]),
    ],
    dependencies: [
        .package(url: "https://github.com/amine2233/cascade-kit.git", from: "1.0.0"),
        .package(url: "https://github.com/vapor/vapor.git", from: "4.122.0"),
        .package(url: "https://github.com/apple/swift-argument-parser.git", from: "1.8.0"),
        .package(url: "https://github.com/vapor/fluent.git", from: "4.13.0"),
        .package(url: "https://github.com/vapor/fluent-sqlite-driver.git", from: "4.9.0"),
        .package(url: "https://github.com/apple/swift-log.git", from: "1.6.0"),
        .package(url: "https://github.com/apple/swift-configuration.git", from: "1.2.0", traits: ["JSON", "YAML"]),
        .package(url: "https://github.com/jpsim/Yams.git", from: "6.2.2"),
        .package(url: "https://github.com/modelcontextprotocol/swift-sdk.git", from: "0.12.0"),
        .package(url: "https://github.com/mattt/AnyLanguageModel.git", from: "0.13.0", traits: ["AsyncHTTPClient"]),
        .package(url: "https://github.com/apple/swift-crypto.git", from: "3.0.0"),
    ],
    targets: [
        .target(name: "DashboardDomain"),
        .target(name: "DashboardPersistence", dependencies: ["DashboardDomain"]),
        .target(name: "DashboardPersistenceJSON", dependencies: ["DashboardPersistence"]),
        .target(
            name: "DashboardPersistenceConfig",
            dependencies: [
                "DashboardPersistence",
                .product(name: "Configuration", package: "swift-configuration"),
                .product(name: "Yams", package: "Yams"),
            ]
        ),
        .target(
            name: "DashboardPersistenceFluent",
            dependencies: [
                "DashboardPersistence",
                .product(name: "FluentSQLiteDriver", package: "fluent-sqlite-driver"),
            ]
        ),
        .target(
            name: "DashboardService",
            dependencies: [
                "DashboardPersistence",
                .product(name: "CascadeKit", package: "cascade-kit"),
                .product(name: "Logging", package: "swift-log"),
            ]
        ),
        .target(name: "DashboardAPI", dependencies: ["DashboardDomain"]),
        .target(
            name: "DashboardOAuth",
            dependencies: ["DashboardDomain", .product(name: "Crypto", package: "swift-crypto")]
        ),
        .target(name: "DashboardAI", dependencies: ["DashboardDomain", "DashboardService", "DashboardOAuth"]),
        .target(
            name: "DashboardAIProviders",
            dependencies: [
                "DashboardAI",
                .product(name: "AnyLanguageModel", package: "AnyLanguageModel"),
                .product(name: "Logging", package: "swift-log"),
            ]
        ),
        .target(
            name: "DashboardProviderHuggingFace",
            dependencies: ["DashboardAIProviders", "DashboardOAuth", .product(name: "AnyLanguageModel", package: "AnyLanguageModel")]
        ),
        .target(
            name: "DashboardProviderOpenRouter",
            dependencies: ["DashboardAIProviders", "DashboardOAuth", .product(name: "AnyLanguageModel", package: "AnyLanguageModel")]
        ),
        .target(
            name: "DashboardMCP",
            dependencies: [
                "DashboardDomain",
                "DashboardService",
                .product(name: "MCP", package: "swift-sdk"),
                .product(name: "Logging", package: "swift-log"),
            ]
        ),
        .target(
            name: "DashboardClient",
            dependencies: ["DashboardAPI", "DashboardPersistence", "DashboardService", "DashboardAI"]
        ),
        .target(
            name: "DashboardRuntime",
            dependencies: [
                "DashboardService",
                "DashboardPersistenceJSON",
                "DashboardPersistenceConfig",
                "DashboardAI",
                "DashboardAIProviders",
                "DashboardProviderHuggingFace",
                "DashboardProviderOpenRouter",
                "DashboardPersistenceFluent",
                .product(name: "CascadeKit", package: "cascade-kit"),
            ]
        ),
        .target(
            name: "DashboardServer",
            dependencies: [
                "DashboardRuntime",
                "DashboardAPI",
                "DashboardMCP",
                .product(name: "Vapor", package: "vapor"),
                .product(name: "Fluent", package: "fluent"),
                .product(name: "FluentSQLiteDriver", package: "fluent-sqlite-driver"),
                .product(name: "CascadeKit", package: "cascade-kit"),
            ]
        ),
        .executableTarget(
            name: "DashboardCLI",
            dependencies: [
                "DashboardServer",
                "DashboardClient",
                "DashboardMCP",
                .product(name: "ArgumentParser", package: "swift-argument-parser"),
                .product(name: "Logging", package: "swift-log"),
            ]
        ),
        .testTarget(name: "DashboardDomainTests", dependencies: ["DashboardDomain"]),
        .testTarget(
            name: "DashboardPersistenceJSONTests",
            dependencies: ["DashboardPersistenceJSON"],
            resources: [.copy("Fixtures")]
        ),
        .testTarget(name: "DashboardPersistenceConfigTests", dependencies: ["DashboardPersistenceConfig"]),
        .testTarget(
            name: "DashboardPersistenceFluentTests",
            dependencies: ["DashboardPersistenceFluent", "DashboardPersistenceJSON"],
            resources: [.copy("Fixtures")]
        ),
        .testTarget(
            name: "DashboardServiceTests",
            dependencies: ["DashboardService", "DashboardPersistenceJSON", "DashboardPersistenceFluent"]
        ),
        .testTarget(name: "DashboardRuntimeTests", dependencies: ["DashboardRuntime"]),
        .testTarget(name: "DashboardMCPTests", dependencies: ["DashboardMCP", "DashboardPersistence"]),
        .testTarget(name: "DashboardOAuthTests", dependencies: ["DashboardOAuth"]),
        .testTarget(
            name: "DashboardProviderTests",
            dependencies: ["DashboardProviderHuggingFace", "DashboardProviderOpenRouter", .product(name: "Vapor", package: "vapor")]
        ),
        .testTarget(name: "DashboardAITests", dependencies: ["DashboardAI", "DashboardPersistence"]),
        .testTarget(
            name: "DashboardAIProvidersTests",
            dependencies: ["DashboardAIProviders", .product(name: "Vapor", package: "vapor")]
        ),
        .testTarget(
            name: "DashboardClientTests",
            dependencies: [
                "DashboardClient",
                "DashboardServer",
                .product(name: "VaporTesting", package: "vapor"),
            ]
        ),
        .testTarget(
            name: "DashboardServerTests",
            dependencies: [
                "DashboardServer",
                .product(name: "VaporTesting", package: "vapor"),
            ]
        ),
        .testTarget(name: "DashboardCLITests", dependencies: ["DashboardCLI"]),
    ],
    swiftLanguageModes: [.v6]
)
