import Foundation

/// Impostazioni condivise fra l'app e il server MCP, in ~/Library/Application Support/WhatsAppBridge/settings.json.
/// Il server MCP non ha un bundle, quindi non può usare UserDefaults dell'app.
public struct BridgeSettings: Codable, Equatable, Sendable {
    public var databasePath: String?
    public var onboardingCompleted = false
    /// Se falso, gli strumenti MCP vedono solo le chat singole.
    public var allowGroupsInMCP = true
    public var maxMessagesPerRequest = 100
    /// Chat tolte dalle "cose in sospeso": id chat → data dell'ultimo messaggio quando l'hai ignorata.
    /// Se arriva un messaggio nuovo la chat ricompare.
    public var dismissedPending: [String: Double] = [:]
    public var workHours = WorkHours()
    /// Se vero, notti e weekend non contano nei tempi di risposta.
    public var workTimeOnly = false

    public init() {}

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        databasePath = try c.decodeIfPresent(String.self, forKey: .databasePath)
        onboardingCompleted = try c.decodeIfPresent(Bool.self, forKey: .onboardingCompleted) ?? false
        allowGroupsInMCP = try c.decodeIfPresent(Bool.self, forKey: .allowGroupsInMCP) ?? true
        maxMessagesPerRequest = try c.decodeIfPresent(Int.self, forKey: .maxMessagesPerRequest) ?? 100
        dismissedPending = try c.decodeIfPresent([String: Double].self, forKey: .dismissedPending) ?? [:]
        workHours = try c.decodeIfPresent(WorkHours.self, forKey: .workHours) ?? WorkHours()
        workTimeOnly = try c.decodeIfPresent(Bool.self, forKey: .workTimeOnly) ?? false
    }

    public static var fileURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appending(path: "Library/Application Support/WhatsAppBridge/settings.json")
    }

    public static func load() -> BridgeSettings {
        guard let data = try? Data(contentsOf: fileURL),
              let settings = try? JSONDecoder().decode(BridgeSettings.self, from: data) else { return BridgeSettings() }
        return settings
    }

    public func save() throws {
        try FileManager.default.createDirectory(at: Self.fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(self).write(to: Self.fileURL, options: .atomic)
        // Contiene il percorso del database e gli id delle chat: leggibile solo dall'utente.
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: Self.fileURL.path)
    }

    /// Percorso salvato oppure ricerca automatica.
    public var resolvedDatabasePath: String? {
        databasePath ?? DatabaseLocator.locate()
    }
}
