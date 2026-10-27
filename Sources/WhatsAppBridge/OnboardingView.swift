import ChatCore
import SwiftUI

struct OnboardingView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        VStack(spacing: 0) {
            StepIndicator(current: model.step)
                .padding(.top, 28)
                .padding(.bottom, 8)
            Group {
                switch model.step {
                case .diskAccess: DiskAccessStep()
                case .database: DatabaseStep()
                case .verify: VerifyStep()
                }
            }
            .frame(maxWidth: 620, maxHeight: .infinity)
            .padding(.horizontal, 32)
            .padding(.bottom, 28)
        }
        .frame(maxWidth: .infinity)
    }
}

private struct StepIndicator: View {
    let current: AppModel.Step

    var body: some View {
        HStack(spacing: 10) {
            ForEach(AppModel.Step.allCases, id: \.self) { step in
                HStack(spacing: 6) {
                    ZStack {
                        Circle()
                            .fill(step.rawValue <= current.rawValue ? Color.accentColor : Color.secondary.opacity(0.2))
                            .frame(width: 22, height: 22)
                        if step.rawValue < current.rawValue {
                            Image(systemName: "checkmark").font(.caption.bold()).foregroundStyle(.white)
                        } else {
                            Text("\(step.rawValue + 1)").font(.caption.bold())
                                .foregroundStyle(step == current ? .white : .secondary)
                        }
                    }
                    Text(step.title)
                        .font(.callout)
                        .foregroundStyle(step == current ? .primary : .secondary)
                }
                if step != AppModel.Step.allCases.last {
                    Rectangle().fill(Color.secondary.opacity(0.25)).frame(width: 28, height: 1)
                }
            }
        }
    }
}

private struct StepHeader: View {
    var symbol: String?
    let title: String
    let message: String

    var body: some View {
        VStack(spacing: 10) {
            if let symbol {
                Image(systemName: symbol)
                    .font(.system(size: 40, weight: .regular))
                    .foregroundStyle(Color.accentColor)
            }
            Text(title).font(.title2.bold())
            Text(message)
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.top, 24)
    }
}

// MARK: - 1. Accesso completo al disco

private struct DiskAccessStep: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        VStack(spacing: 22) {
            StepHeader(
                symbol: "lock.shield",
                title: "Consenti l'accesso al disco",
                message: "WhatsApp salva le chat in una cartella protetta di macOS. Per leggerle serve l'Accesso completo al disco. L'app legge soltanto: non scrive, non invia niente e non manda dati in rete."
            )

            VStack(alignment: .leading, spacing: 10) {
                Instruction(number: 1, text: "Apri Impostazioni di Sistema con il pulsante qui sotto.")
                Instruction(number: 2, text: "Attiva l'interruttore accanto a WhatsApp Bridge. Se non c'è, premi + e scegli l'app.")
                Instruction(number: 3, text: "Torna qui: l'app se ne accorge da sola.")
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.quaternary.opacity(0.5), in: .rect(cornerRadius: 10))

            Button("Apri Impostazioni di Sistema") { model.openFullDiskAccessSettings() }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)

            HStack(spacing: 8) {
                ProgressView().controlSize(.small)
                Text("In attesa del permesso…").foregroundStyle(.secondary)
            }

            Spacer()

            VStack(spacing: 4) {
                Text("Hai già attivato il permesso ma l'app non lo vede?")
                    .font(.callout).foregroundStyle(.secondary)
                Button("Riapri l'app") { model.relaunch() }
                    .buttonStyle(.link)
            }
        }
        .task { await model.waitForDiskAccess() }
    }
}

private struct Instruction: View {
    let number: Int
    let text: String

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text("\(number)").font(.callout.bold()).foregroundStyle(Color.accentColor)
            Text(text).fixedSize(horizontal: false, vertical: true)
        }
    }
}

// MARK: - 2. Database

private struct DatabaseStep: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        VStack(spacing: 22) {
            StepHeader(
                symbol: "externaldrive",
                title: "Trova il database di WhatsApp",
                message: "Cerco il file in cui WhatsApp Desktop salva le conversazioni già sincronizzate su questo Mac."
            )

            if let path = model.databasePath, model.database != nil {
                VStack(alignment: .leading, spacing: 8) {
                    Label("Database trovato", systemImage: "checkmark.circle.fill")
                        .font(.headline)
                        .foregroundStyle(.green)
                    Text(path)
                        .font(.callout.monospaced())
                        .textSelection(.enabled)
                        .lineLimit(2)
                        .truncationMode(.middle)
                    if let info = model.databaseInfo {
                        Text("\(info.size.formatted(.byteCount(style: .file))) · aggiornato \(info.modified.formatted(.relative(presentation: .named)))")
                            .font(.callout).foregroundStyle(.secondary)
                    }
                }
                .padding(16)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(.quaternary.opacity(0.5), in: .rect(cornerRadius: 10))
            } else if let error = model.databaseError {
                Label(error, systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(16)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(.orange.opacity(0.08), in: .rect(cornerRadius: 10))
            } else {
                ProgressView()
            }

            Spacer()

            HStack {
                Button("Scegli il file a mano…") { model.chooseDatabaseManually() }
                if model.database == nil {
                    Button("Cerca di nuovo") { model.locateDatabase() }
                }
                Spacer()
                Button("Continua") { Task { await model.goToVerify() } }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .disabled(model.database == nil)
                    .keyboardShortcut(.defaultAction)
            }
        }
    }
}

// MARK: - 3. Verifica

private struct VerifyStep: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        VStack(spacing: 18) {
            StepHeader(
                title: "Controlla che sia allineato",
                message: "Queste sono le ultime conversazioni lette dal database. Se in WhatsApp vedi le stesse in cima alla lista, è tutto a posto."
            )

            if let counts = model.counts {
                AlignmentBanner(lastMessage: counts.lastMessageDate)
                Text("\(counts.chats.formatted()) chat · \(counts.groups.formatted()) gruppi · \(counts.messages.formatted()) messaggi")
                    .font(.callout).foregroundStyle(.secondary)
            }

            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    PreviewSection(title: "Ultime conversazioni") {
                        ForEach(model.recentChats) { chat in
                            PreviewRow(
                                title: chat.name,
                                detail: chat.lastMessagePreview ?? "",
                                date: chat.lastMessageDate,
                                badge: chat.unreadCount > 0 ? chat.unreadCount : nil
                            )
                        }
                    }
                    PreviewSection(title: "Ultimi messaggi") {
                        ForEach(model.recentMessages) { message in
                            PreviewRow(
                                title: message.fromMe ? "Tu → \(message.chatName)" : message.chatName == message.sender ? message.sender : "\(message.sender) in \(message.chatName)",
                                detail: message.text ?? "[\(message.kind)]",
                                date: message.date,
                                badge: nil
                            )
                        }
                    }
                }
            }
            .overlay { if model.isLoading && model.recentChats.isEmpty { ProgressView() } }

            HStack {
                Button("Indietro") { model.step = .database }
                Button("Ricarica") { Task { await model.loadPreview() } }
                Spacer()
                Button("Tutto ok, inizia") { Task { await model.completeOnboarding() } }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .keyboardShortcut(.defaultAction)
            }
        }
    }
}

private struct AlignmentBanner: View {
    let lastMessage: Date?

    var body: some View {
        let isRecent = lastMessage.map { Date.now.timeIntervalSince($0) < 86400 } ?? false
        Label {
            if let lastMessage {
                Text("Ultimo messaggio nel database: \(lastMessage.formatted(date: .abbreviated, time: .shortened)) (\(lastMessage.formatted(.relative(presentation: .named))))")
            } else {
                Text("Nessun messaggio nel database")
            }
        } icon: {
            Image(systemName: isRecent ? "checkmark.circle.fill" : "clock.badge.exclamationmark")
        }
        .foregroundStyle(isRecent ? .green : .orange)
        .font(.callout.weight(.medium))
        .help(isRecent ? "" : "Apri WhatsApp Desktop per farlo sincronizzare.")
    }
}

private struct PreviewSection<Content: View>: View {
    let title: String
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(title).font(.headline).padding(.bottom, 6)
            VStack(spacing: 0) { content }
                .background(.quaternary.opacity(0.4), in: .rect(cornerRadius: 10))
        }
    }
}

private struct PreviewRow: View {
    let title: String
    let detail: String
    let date: Date?
    let badge: Int?

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.body.weight(.medium)).lineLimit(1)
                Text(detail).font(.callout).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer(minLength: 8)
            VStack(alignment: .trailing, spacing: 4) {
                if let date {
                    Text(date.formatted(.relative(presentation: .named)))
                        .font(.caption).foregroundStyle(.secondary)
                }
                if let badge {
                    Text("\(badge)")
                        .font(.caption2.bold())
                        .padding(.horizontal, 6).padding(.vertical, 2)
                        .background(.green, in: .capsule)
                        .foregroundStyle(.white)
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }
}
