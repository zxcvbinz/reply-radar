import AppKit
import ChatCore
import Foundation
import Observation

struct ContactRef: Identifiable, Hashable {
    let id: Int64
    let name: String
}

@Observable
@MainActor
final class AppModel {
    enum Step: Int, CaseIterable {
        case diskAccess, database, verify

        var title: String {
            switch self {
            case .diskAccess: "Accesso al disco"
            case .database: "Database"
            case .verify: "Verifica"
            }
        }
    }

    var settings = BridgeSettings.load()
    var step: Step = .diskAccess
    var hasDiskAccess = DatabaseLocator.hasFullDiskAccess

    var databasePath: String?
    var databaseInfo: DatabaseLocator.FileInfo?
    var database: ChatDatabase?
    var databaseError: String?

    var counts: DatabaseCounts?
    var recentChats: [ChatSummary] = []
    var recentMessages: [ChatMessage] = []

    var periodDays = 30
    /// Contatto aperto nel dettaglio.
    var selectedContact: ContactRef?
    var overview: Overview?
    var isLoading = false

    var showsOnboarding: Bool { !settings.onboardingCompleted || database == nil }

    // MARK: - Avvio

    func start() async {
        hasDiskAccess = DatabaseLocator.hasFullDiskAccess
        if settings.onboardingCompleted, hasDiskAccess, connect(path: settings.resolvedDatabasePath) {
            await refresh()
        } else {
            step = hasDiskAccess ? .database : .diskAccess
            if hasDiskAccess { locateDatabase() }
        }
    }

    /// Aggiornamento periodico mentre l'app è aperta: WhatsApp scrive di continuo.
    func autoRefresh() async {
        while !Task.isCancelled {
            try? await Task.sleep(for: .seconds(60))
            if !showsOnboarding { await refresh() }
        }
    }

    // MARK: - Onboarding

    func openFullDiskAccessSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles") {
            NSWorkspace.shared.open(url)
        }
    }

    /// Controlla il permesso finché non arriva, poi passa da solo al passo successivo.
    func waitForDiskAccess() async {
        while !Task.isCancelled, step == .diskAccess {
            hasDiskAccess = DatabaseLocator.hasFullDiskAccess
            if hasDiskAccess {
                step = .database
                locateDatabase()
                return
            }
            try? await Task.sleep(for: .seconds(1.5))
        }
    }

    /// macOS a volte applica il permesso solo dopo un riavvio dell'app.
    func relaunch() {
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.createsNewApplicationInstance = true
        NSWorkspace.shared.openApplication(at: Bundle.main.bundleURL, configuration: configuration) { _, _ in
            Task { @MainActor in NSApp.terminate(nil) }
        }
    }

    func locateDatabase() {
        databaseError = nil
        guard let path = DatabaseLocator.locate() else {
            databasePath = nil
            databaseInfo = nil
            databaseError = "Non trovo il database di WhatsApp. Apri WhatsApp Desktop, accedi e aspetta che sincronizzi le chat, poi riprova."
            return
        }
        select(path: path)
    }

    func chooseDatabaseManually() {
        let panel = NSOpenPanel()
        panel.title = "Scegli ChatStorage.sqlite"
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.showsHiddenFiles = true
        panel.directoryURL = DatabaseLocator.groupContainersURL
        guard panel.runModal() == .OK, let url = panel.url else { return }
        databaseError = nil
        select(path: url.path)
    }

    private func select(path: String) {
        databasePath = path
        databaseInfo = DatabaseLocator.fileInfo(atPath: path)
        if connect(path: path) {
            settings.databasePath = path == DatabaseLocator.defaultPath ? nil : path
            persist()
        }
    }

    func goToVerify() async {
        step = .verify
        await loadPreview()
    }

    func loadPreview() async {
        guard let database else { return }
        isLoading = true
        defer { isLoading = false }
        let result = await Task.detached {
            (try? database.counts(), (try? database.chats(limit: 8)) ?? [], (try? database.messages(.init())) ?? [])
        }.value
        counts = result.0
        recentChats = result.1
        recentMessages = Array(result.2.prefix(6))
        databaseInfo = databasePath.flatMap(DatabaseLocator.fileInfo(atPath:))
    }

    func completeOnboarding() async {
        settings.onboardingCompleted = true
        persist()
        await refresh()
    }

    func restartOnboarding() {
        settings.onboardingCompleted = false
        persist()
        step = hasDiskAccess ? .database : .diskAccess
    }

    // MARK: - Statistiche

    @discardableResult
    func connect(path: String?) -> Bool {
        guard let path else {
            databaseError = ChatDatabaseError.notFound(DatabaseLocator.defaultPath).localizedDescription
            return false
        }
        if database?.path == path { return true }
        do {
            database = try ChatDatabase(path: path)
            databasePath = path
            databaseError = nil
            return true
        } catch {
            database = nil
            databaseError = error.localizedDescription
            return false
        }
    }

    func refresh() async {
        guard let database else { return }
        isLoading = true
        defer { isLoading = false }
        let days = periodDays
        let settings = settings
        let result = await Task.detached {
            (
                try? database.overview(days: days, dismissed: settings.dismissedPending, workHours: settings.workHours, workTimeOnly: settings.workTimeOnly),
                try? database.counts()
            )
        }.value
        overview = result.0
        counts = result.1
        databaseInfo = databasePath.flatMap(DatabaseLocator.fileInfo(atPath:))
    }

    func contactStats(chatID: Int64) async -> ContactStats? {
        guard let database else { return nil }
        let days = periodDays
        let settings = settings
        return await Task.detached {
            try? database.contactStats(chatID: chatID, days: days, workHours: settings.workHours, workTimeOnly: settings.workTimeOnly)
        }.value
    }

    func dismiss(_ chat: PendingChat) async {
        settings.dismissedPending[String(chat.chatID)] = chat.lastMessageDate.timeIntervalSinceReferenceDate
        persist()
        await refresh()
    }

    func restoreDismissed() async {
        settings.dismissedPending = [:]
        persist()
        await refresh()
    }

    func openInWhatsApp() {
        if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "net.whatsapp.WhatsApp") {
            NSWorkspace.shared.openApplication(at: url, configuration: .init())
        }
    }

    // MARK: - Claude Code

    /// Il server MCP sta accanto all'eseguibile dell'app, dentro il bundle.
    var mcpExecutablePath: String {
        Bundle.main.bundleURL.appending(path: "Contents/MacOS/reply-radar-mcp").path
    }

    var mcpExecutableExists: Bool { FileManager.default.isExecutableFile(atPath: mcpExecutablePath) }

    var integrationCommand: String {
        "claude mcp add --scope user --transport stdio reply-radar -- \"\(mcpExecutablePath)\""
    }

    /// Registrato in Claude Code se compare fra i server MCP di ~/.claude.json.
    var isRegisteredInClaudeCode: Bool {
        let url = FileManager.default.homeDirectoryForCurrentUser.appending(path: ".claude.json")
        guard let data = try? Data(contentsOf: url),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let servers = json["mcpServers"] as? [String: Any] else { return false }
        return servers["reply-radar"] != nil
    }

    func copyIntegrationCommand() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(integrationCommand, forType: .string)
    }

    func persist() {
        try? settings.save()
    }
}
