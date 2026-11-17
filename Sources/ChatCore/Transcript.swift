import AVFoundation
import Foundation
import Speech

/// Un messaggio della trascrizione: testo, oppure nota vocale con il percorso del file.
public struct TranscriptLine: Identifiable, Sendable {
    public let message: ChatMessage
    /// Percorso del file audio, se WhatsApp l'ha scaricato sul Mac.
    public let audioPath: String?
    public let durationSeconds: Int?
    public var transcript: String?

    public var id: Int64 { message.id }
    public var isAudio: Bool { message.kind == "audio" }
}

extension ChatDatabase {
    /// Messaggi di una chat in ordine cronologico, con il file di ogni nota vocale. Non trascrive.
    public func transcriptLines(chatID: Int64, since: Date?, audioOnly: Bool, limit: Int) throws -> [TranscriptLine] {
        var filter = MessageFilter()
        filter.chatID = chatID
        filter.since = since
        filter.audioOnly = audioOnly
        filter.limit = limit
        let messages = try messages(filter).reversed()
        let audioIDs = messages.filter { $0.kind == "audio" }.map(\.id)
        let media = audioIDs.isEmpty ? [:] : Dictionary(
            uniqueKeysWithValues: try self.media(messageIDs: audioIDs, limit: audioIDs.count).map { ($0.messageID, $0) }
        )
        return messages.map { message in
            let info = media[message.id]
            return TranscriptLine(
                message: message,
                audioPath: info?.fileExists == true ? info?.localPath : nil,
                durationSeconds: info?.durationSeconds,
                transcript: nil
            )
        }
    }
}

/// Trascrizione sul Mac con il riconoscimento vocale di macOS: l'audio non lascia il computer.
public enum VoiceTranscriber {
    public enum Failure: LocalizedError {
        case unsupportedLanguage

        public var errorDescription: String? {
            "La trascrizione sul Mac non supporta questa lingua."
        }
    }

    /// La prima volta macOS scarica il modello della lingua (una volta sola, gestito dal sistema).
    public static func transcribe(fileAt url: URL, locale: Locale = .current) async throws -> String {
        let fallback = Locale(identifier: "it-IT")
        var supported = await SpeechTranscriber.supportedLocale(equivalentTo: locale)
        if supported == nil { supported = await SpeechTranscriber.supportedLocale(equivalentTo: fallback) }
        guard let supported else { throw Failure.unsupportedLanguage }
        let transcriber = SpeechTranscriber(locale: supported, preset: .transcription)
        if let request = try await AssetInventory.assetInstallationRequest(supporting: [transcriber]) {
            try await request.downloadAndInstall()
        }
        let file = try AVAudioFile(forReading: url)
        let collected = Task {
            try await transcriber.results.reduce(into: "") { $0 += String($1.text.characters) }
        }
        let analyzer = SpeechAnalyzer(modules: [transcriber])
        if let last = try await analyzer.analyzeSequence(from: file) {
            try await analyzer.finalizeAndFinish(through: last)
        } else {
            await analyzer.cancelAndFinishNow()
        }
        return try await collected.value.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Indici delle note vocali scaricate e ancora senza testo.
    public static func pending(_ lines: [TranscriptLine]) -> [Int] {
        lines.indices.filter { lines[$0].isAudio && lines[$0].transcript == nil && lines[$0].audioPath != nil }
    }

    /// Trascrive le note vocali ancora senza testo. Se una non riesce resta "nessuna parola riconosciuta".
    public static func fill(_ lines: [TranscriptLine]) async -> [TranscriptLine] {
        var lines = lines
        for index in pending(lines) {
            if Task.isCancelled { break }
            lines[index].transcript = (try? await transcribe(fileAt: URL(fileURLWithPath: lines[index].audioPath!))) ?? ""
        }
        return lines
    }

    /// Testo pronto da incollare in Claude.
    public static func plainText(chatName: String, lines: [TranscriptLine]) -> String {
        let dateStyle = Date.FormatStyle(date: .numeric, time: .shortened)
        var out = "Chat WhatsApp «\(chatName)»"
        if let first = lines.first?.message.date, let last = lines.last?.message.date {
            out += ", dal \(first.formatted(dateStyle)) al \(last.formatted(dateStyle))"
        }
        out += ".\nLe note vocali [🎤] sono trascritte in automatico e possono contenere errori di riconoscimento.\n\n"
        for line in lines {
            let head = "[\(line.message.date.formatted(dateStyle))] \(line.message.sender)"
            let body: String
            if line.isAudio {
                let length = line.durationSeconds.map { " \($0 / 60):\(String(format: "%02d", $0 % 60))" } ?? ""
                let text: String = switch (line.audioPath, line.transcript) {
                case (nil, _): "(audio non scaricato sul Mac)"
                case (_, nil): "(non trascritta)"
                case (_, ""?): "(nessuna parola riconosciuta)"
                case (_, let text?): text
                }
                body = "🎤\(length): \(text)"
            } else {
                body = line.message.text.map { $0.isEmpty ? "(\(line.message.kind))" : $0 } ?? "(\(line.message.kind))"
            }
            out += "\(head): \(body)\n"
        }
        return out
    }
}
