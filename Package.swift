// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "WhatsAppBridge",
    platforms: [.macOS(.v26)],
    products: [
        .executable(name: "WhatsAppBridge", targets: ["WhatsAppBridge"]),
        .executable(name: "whatsapp-local-mcp", targets: ["whatsapp-local-mcp"]),
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
            name: "whatsapp-local-mcp",
            dependencies: ["ChatCore"]
        ),
        // App SwiftUI: onboarding, statistiche, impostazioni.
        .executableTarget(
            name: "WhatsAppBridge",
            dependencies: ["ChatCore"]
        ),
    ]
)
