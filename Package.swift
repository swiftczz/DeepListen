// swift-tools-version: 6.3

import PackageDescription

let package = Package(
    name: "IELTSListeningTrainer",
    platforms: [
        .macOS("26.0")
    ],
    products: [
        .executable(name: "IELTSListeningTrainer", targets: ["IELTSListeningTrainer"])
    ],
    targets: [
        .executableTarget(
            name: "IELTSListeningTrainer",
            path: "Sources/IELTSListeningTrainer"
        )
    ]
)
