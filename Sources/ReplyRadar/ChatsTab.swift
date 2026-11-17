import AppKit
import ChatCore
import SwiftUI

/// Scheda "Chat": scegli quali chat vede Claude, trascrivi le note vocali e copia tutto per incollarlo in Claude.
struct ChatsTab: View {
    @Environment(AppModel.self) private var model
    @State private var chats: [ChatSummary] = []
    @State private var query = ""
    @State private var selection: Int64?

    private var filtered: [ChatSummary] {
        query.isEmpty ? chats : chats.filter { $0.name.localizedCaseInsensitiveContains(query) }
    }

    var body: some View {
        @Bindable var model = model
        HStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 0) {
                VStack(alignment: .leading, spacing: 6) {
                    Toggle("Claude vede solo le chat spuntate", isOn: $model.settings.mcpOnlySelectedChats)
                    Text(model.settings.mcpOnlySelectedChats
                         ? "Chat condivise con Claude: \(model.settings.mcpAllowedChats.count)"
                         : "Ora Claude può leggere tutte le chat\(model.settings.allowGroupsInMCP ? "" : " singole").")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    TextField("Cerca una chat", text: $query)
                        .textFieldStyle(.roundedBorder)
                }
                .padding(12)
                List(filtered, selection: $selection) { chat in
                    ChatRow(chat: chat).tag(chat.id)
                }
                .overlay {
                    if filtered.isEmpty, !chats.isEmpty { ContentUnavailableView.search(text: query) }
                }
            }
            .frame(width: 300)
            Divider()
            if let id = selection, let chat = chats.first(where: { $0.id == id }) {
                TranscriptPane(chat: chat).id(chat.id)
            } else {
                ContentUnavailableView(
                    "Scegli una chat",
                    systemImage: "waveform",
                    description: Text("Puoi trascrivere le note vocali sul Mac e copiare tutta la conversazione per incollarla in Claude.")
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .onChange(of: model.settings.mcpOnlySelectedChats) { model.persist() }
        .task { chats = await model.allChats() }
    }
}

private struct ChatRow: View {
    @Environment(AppModel.self) private var model
    let chat: ChatSummary

    var body: some View {
        HStack {
            Image(systemName: chat.kind == .group ? "person.3.fill" : "person.fill")
                .foregroundStyle(.secondary)
                .frame(width: 22)
            VStack(alignment: .leading) {
                Text(chat.name).lineLimit(1)
                if let date = chat.lastMessageDate {
                    Text(date, format: .relative(presentation: .named))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
            if model.settings.mcpOnlySelectedChats {
                Toggle("Claude", isOn: Binding(
                    get: { model.settings.mcpAllowedChats.contains(chat.id) },
                    set: { model.setClaudeAccess(chat.id, $0) }
                ))
                .toggleStyle(.checkbox)
                .labelsHidden()
                .help("Claude può leggere questa chat")
            }
        }
    }
}

private struct TranscriptPane: View {
    @Environment(AppModel.self) private var model
    let chat: ChatSummary

    @State private var days = 30
    @State private var audioOnly = false
    @State private var lines: [TranscriptLine] = []
    @State private var loading = true
    @State private var progress: (done: Int, total: Int)?
    @State private var copied = false
    @State private var work: Task<Void, Never>?

    private var pendingAudio: Int { VoiceTranscriber.pending(lines).count }
    private var audioCount: Int { lines.filter(\.isAudio).count }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                VStack(alignment: .leading) {
                    Text(chat.name).font(.title3.bold()).lineLimit(1)
                    Text("\(lines.count) messaggi, \(audioCount) audio").font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Picker("Periodo", selection: $days) {
                    Text("7 gg").tag(7)
                    Text("30 gg").tag(30)
                    Text("90 gg").tag(90)
                    Text("1 anno").tag(365)
                }
                .labelsHidden()
                .fixedSize()
                Toggle("Solo audio", isOn: $audioOnly)
                    .toggleStyle(.checkbox)
            }
            .padding(12)

            HStack {
                if let progress {
                    ProgressView(value: Double(progress.done), total: Double(max(progress.total, 1)))
                        .frame(width: 160)
                    Text("Trascrivo \(progress.done) di \(progress.total)…").font(.callout).monospacedDigit()
                    Button("Annulla") { work?.cancel() }
                } else if pendingAudio > 0 {
                    Button("Trascrivi \(pendingAudio) audio", systemImage: "waveform") { transcribe(thenCopy: false) }
                }
                Spacer()
                Button(copied ? "Copiato" : (pendingAudio > 0 ? "Trascrivi e copia" : "Copia per Claude"),
                       systemImage: copied ? "checkmark" : "doc.on.doc") {
                    pendingAudio > 0 ? transcribe(thenCopy: true) : copy()
                }
                .buttonStyle(.borderedProminent)
                .disabled(lines.isEmpty || progress != nil)
                .keyboardShortcut("c", modifiers: [.command, .shift])
            }
            .padding(.horizontal, 12)
            .padding(.bottom, 10)
            Divider()

            if loading {
                ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if lines.isEmpty {
                ContentUnavailableView(
                    audioOnly ? "Nessun audio" : "Nessun messaggio",
                    systemImage: "tray",
                    description: Text("Niente in questo periodo. Prova un periodo più lungo.")
                )
            } else {
                List(lines) { line in LineRow(line: line) }
                    .listStyle(.inset)
            }
        }
        .task(id: "\(days)-\(audioOnly)") { await load() }
        .onDisappear { work?.cancel() }
    }

    private func load() async {
        loading = true
        lines = await model.transcriptLines(chatID: chat.id, days: days, audioOnly: audioOnly)
        loading = false
    }

    private func transcribe(thenCopy: Bool) {
        let todo = VoiceTranscriber.pending(lines)
        work = Task {
            // Una nota alla volta: ognuna compare appena è pronta.
            for (done, index) in todo.enumerated() {
                progress = (done, todo.count)
                guard !Task.isCancelled, let path = lines[index].audioPath else { break }
                lines[index].transcript = (try? await VoiceTranscriber.transcribe(fileAt: URL(fileURLWithPath: path))) ?? ""
                model.remember([lines[index]])
            }
            progress = nil
            if thenCopy, !Task.isCancelled { copy() }
        }
    }

    private func copy() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(VoiceTranscriber.plainText(chatName: chat.name, lines: lines), forType: .string)
        copied = true
        Task {
            try? await Task.sleep(for: .seconds(2))
            copied = false
        }
    }
}

private struct LineRow: View {
    let line: TranscriptLine

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 6) {
                Text(line.message.sender).font(.caption.bold())
                Text(line.message.date, format: .dateTime.day().month().hour().minute())
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if line.isAudio {
                    Label(line.durationSeconds.map { "\($0 / 60):\(String(format: "%02d", $0 % 60))" } ?? "audio", systemImage: "mic.fill")
                        .font(.caption)
                        .foregroundStyle(.tint)
                }
            }
            if line.isAudio {
                switch (line.audioPath, line.transcript) {
                case (nil, _): Text("Audio non scaricato sul Mac: aprilo in WhatsApp per scaricarlo.").foregroundStyle(.secondary).italic()
                case (_, nil): Text("Da trascrivere").foregroundStyle(.secondary).italic()
                case (_, ""?): Text("Nessuna parola riconosciuta").foregroundStyle(.secondary).italic()
                case (_, let text?): Text(text).textSelection(.enabled)
                }
            } else {
                Text(line.message.text ?? "(\(line.message.kind))")
                    .foregroundStyle(line.message.text == nil ? .secondary : .primary)
                    .textSelection(.enabled)
            }
        }
        .padding(.vertical, 2)
    }
}
