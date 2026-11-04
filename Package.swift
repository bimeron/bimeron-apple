// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Bimeron",
    defaultLocalization: "en",
    platforms: [.macOS(.v14)],
    products: [.executable(name: "Bimeron", targets: ["BimeronApp"])],
    targets: [
        .target(name: "BimeronGeoData"),
        .testTarget(name: "BimeronGeoDataTests", dependencies: ["BimeronGeoData"]),
        .target(name: "BimeronModel"),
        .target(name: "BimeronSSHAuth"),
        .testTarget(name: "BimeronSSHAuthTests", dependencies: ["BimeronSSHAuth"]),
        .target(name: "BimeronDaemon"),
        .testTarget(name: "BimeronDaemonTests", dependencies: ["BimeronDaemon"]),
        .systemLibrary(name: "CZlib"),
        .target(name: "BimeronCoreCLI", dependencies: ["CZlib"]),
        .testTarget(name: "BimeronCoreCLITests", dependencies: ["BimeronCoreCLI"]),
        .executableTarget(name: "BimeronApp", dependencies: ["BimeronModel", "BimeronDaemon", "BimeronCoreCLI"], resources: [.process("Resources")]),
        .testTarget(name: "BimeronModelTests", dependencies: ["BimeronModel"], resources: [.copy("Fixtures")]),
        .testTarget(name: "BimeronAppTests", dependencies: ["BimeronApp"])
    ]
)
