// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "Explorer",
    platforms: [.macOS(.v15)],
    targets: [
        .executableTarget(name: "Explorer", path: "Sources/Explorer"),
        .testTarget(name: "ExplorerTests", dependencies: ["Explorer"], path: "Tests/ExplorerTests"),
    ],
    swiftLanguageModes: [.v5]
)
