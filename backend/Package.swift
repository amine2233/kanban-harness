// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "mvp-dashboard-backend",
    platforms: [.macOS(.v14)],
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
    ],
    targets: [
        .target(name: "DashboardDomain"),
        .target(name: "DashboardPersistence", dependencies: ["DashboardDomain"]),
        .target(name: "DashboardPersistenceJSON", dependencies: ["DashboardPersistence"]),
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
            ]
        ),
        .target(name: "DashboardAPI", dependencies: ["DashboardDomain"]),
        .target(
            name: "DashboardServer",
            dependencies: [
                "DashboardService",
                "DashboardAPI",
                "DashboardPersistenceJSON",
                "DashboardPersistenceFluent",
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
                .product(name: "ArgumentParser", package: "swift-argument-parser"),
            ]
        ),
        .testTarget(name: "DashboardDomainTests", dependencies: ["DashboardDomain"]),
        .testTarget(
            name: "DashboardPersistenceJSONTests",
            dependencies: ["DashboardPersistenceJSON"],
            resources: [.copy("Fixtures")]
        ),
        .testTarget(
            name: "DashboardPersistenceFluentTests",
            dependencies: ["DashboardPersistenceFluent", "DashboardPersistenceJSON"],
            resources: [.copy("Fixtures")]
        ),
        .testTarget(
            name: "DashboardServiceTests",
            dependencies: ["DashboardService", "DashboardPersistenceJSON", "DashboardPersistenceFluent"]
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
