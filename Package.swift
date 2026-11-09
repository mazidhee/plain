// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "Plain",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "Plain", targets: ["Plain"])
    ],
    targets: [
        .executableTarget(
            name: "Plain",
            path: "Sources/Plain",
            linkerSettings: [.linkedFramework("Carbon")]
        )
    ]
)
