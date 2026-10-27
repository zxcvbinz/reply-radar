// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "ReplyRadar",
    platforms: [.macOS(.v26)],
    products: [
        .executable(name: "ReplyRadar", targets: ["ReplyRadar"]),
        .executable(name: "reply-radar-mcp", targets: ["reply-radar-mcp"]),
    ],
    dependencies: [
        .package(url: "https://github.com/groue/GRDB.swift.git", from: "7.0.0"),
    ],
    targets: [
        // Lettura in sola lettura del database di WhatsApp, statistiche, impostazioni condivise.
        .target(
            name: "ChatCore",
            dependencies: [.product(name: "GRDB", package: "GRDB.swift")]
        ),
        // Server MCP su stdio, avviato da Claude Code.
        .executableTarget(
            name: "reply-radar-mcp",
            dependencies: ["ChatCore"]
        ),
        // App SwiftUI: onboarding, statistiche, impostazioni.
        .executableTarget(
            name: "ReplyRadar",
            dependencies: ["ChatCore"]
        ),
    ]
)
