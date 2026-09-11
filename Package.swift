// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "Badges",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(name: "Badges", path: "Sources/Badges")
    ]
)
