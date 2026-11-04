// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Bimeron",
    defaultLocalization: "en",
    platforms: [.macOS(.v14)],
    products: [.executable(name: "Bimeron", targets: ["BimeronApp"])],
    targets: [
        .target(name: "BimeronModel"),
        .executableTarget(name: "BimeronApp", dependencies: ["BimeronModel"], resources: [.process("Resources")]),
        .testTarget(name: "BimeronModelTests", dependencies: ["BimeronModel"], resources: [.copy("Fixtures")]),
        .testTarget(name: "BimeronAppTests", dependencies: ["BimeronApp"])
    ]
)
