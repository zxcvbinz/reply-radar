import ChatCore
import SwiftUI

@main
struct ReplyRadarApp: App {
    @State private var model = AppModel()

    init() {
        // `ReplyRadar --check`: verifica da terminale senza finestra. Stampa solo conteggi e date, mai messaggi.
        if CommandLine.arguments.contains("--check") {
            Self.checkAndExit()
        }
    }

    var body: some Scene {
        WindowGroup("Reply Radar") {
            RootView()
                .environment(model)
                .frame(minWidth: 760, minHeight: 600)
                .task { await model.start() }
                .task { await model.autoRefresh() }
        }
        .defaultSize(width: 900, height: 820)
        .windowResizability(.contentMinSize)

        Settings {
            SettingsView()
                .environment(model)
        }
    }

    private static func checkAndExit() -> Never {
        print("accesso completo al disco: \(DatabaseLocator.hasFullDiskAccess ? "sì" : "no")")
        guard let path = BridgeSettings.load().resolvedDatabasePath else {
            print("database: non trovato")
            exit(1)
        }
        print("database: \(path) (\(DatabaseLocator.access(atPath: path)))")
        do {
            let db = try ChatDatabase(path: path)
            let counts = try db.counts()
            print("chat: \(counts.chats), gruppi: \(counts.groups), messaggi: \(counts.messages)")
            print("ultimo messaggio: \(counts.lastMessageDate?.formatted() ?? "-")")
            let overview = try db.overview(days: 30)
            print("risposte (30 gg): \(overview.current.replyCount), aspettano te: \(overview.waitingOnMe.count), aspetti tu: \(overview.waitingOnThem.count)")
            exit(0)
        } catch {
            print("errore: \(error.localizedDescription)")
            exit(1)
        }
    }
}

struct RootView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        Group {
            if model.showsOnboarding {
                OnboardingView()
            } else {
                DashboardView()
            }
        }
        .animation(.default, value: model.showsOnboarding)
    }
}
