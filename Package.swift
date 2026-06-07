// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Leafblower",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "Leafblower", targets: ["Leafblower"])
    ],
    targets: [
        .executableTarget(name: "Leafblower"),
        .testTarget(
            name: "LeafblowerTests",
            dependencies: ["Leafblower"]
        )
    ]
)
