// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "GitDesk",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "GitDesk",
            path: "Sources/GitDesk"
        )
    ]
)
