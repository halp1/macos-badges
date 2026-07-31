// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "Badgeify",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(name: "Badgeify", path: "Sources/Badgeify")
    ]
)
