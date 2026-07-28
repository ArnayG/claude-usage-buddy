// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "ClaudeUsageBuddy",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "ClaudeUsageBuddy",
            path: "Sources/ClaudeUsageBuddy"
        )
    ]
)
