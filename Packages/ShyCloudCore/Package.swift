// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "ShyCloudCore",
    platforms: [.macOS("26.0")],
    products: [
        .library(name: "ShyCloudCore", targets: ["ShyCloudCore"]),
    ],
    targets: [
        .target(name: "ShyCloudCore"),
        .testTarget(name: "ShyCloudCoreTests", dependencies: ["ShyCloudCore"]),
    ],
    swiftLanguageModes: [.v6]
)
