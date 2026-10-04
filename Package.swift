// swift-tools-version: 6.3

import PackageDescription

let package = Package(
    name: "DeepListen",
    platforms: [
        .macOS("26.0")
    ],
    products: [
        .executable(name: "DeepListen", targets: ["DeepListen"])
    ],
    targets: [
        .executableTarget(
            name: "DeepListen",
            path: "Sources/DeepListen"
        ),
        .testTarget(
            name: "DeepListenTests",
            dependencies: ["DeepListen"],
            resources: [.copy("Fixtures")]
        )
    ]
)
