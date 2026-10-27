import Foundation

public enum ChatKind: String, Codable, Sendable {
    case direct, group

    /// `ZSESSIONTYPE`: 0 chat singola, 1 gruppo. Stati, liste broadcast e community restano fuori.
    init?(sessionType: Int) {
        switch sessionType {
        case 0: self = .direct
        case 1: self = .group
        default: return nil
        }
    }
}

public struct ChatSummary: Codable, Identifiable, Hashable, Sendable {
    public let id: Int64
    public let name: String
    public let kind: ChatKind
    public let lastMessageDate: Date?
    public let lastMessagePreview: String?
    /// -1 quando la chat è stata segnata come da leggere a mano.
    public let unreadCount: Int
    public let archived: Bool
}

public struct ChatMessage: Codable, Identifiable, Hashable, Sendable {
    public let id: Int64
    public let chatID: Int64
    public let chatName: String
    public let date: Date
    public let fromMe: Bool
    public let sender: String
    public let text: String?
    public let kind: String
    public let starred: Bool
}

public struct MediaInfo: Codable, Identifiable, Hashable, Sendable {
    public var id: Int64 { messageID }
    public let messageID: Int64
    public let chatName: String
    public let date: Date
    public let fromMe: Bool
    public let kind: String
    public let title: String?
    public let fileName: String?
    public let localPath: String?
    public let fileExists: Bool
    public let fileSize: Int64?
    public let durationSeconds: Int?
}

public struct DatabaseCounts: Codable, Sendable {
    public let chats: Int
    public let groups: Int
    public let messages: Int
    public let firstMessageDate: Date?
    public let lastMessageDate: Date?
}

enum MessageKind {
    /// Tipi di sistema (eventi di gruppo, avvisi di cifratura): non sono messaggi scritti da qualcuno.
    static let systemTypes = [6, 10]

    static func label(_ type: Int) -> String {
        switch type {
        case 0: "testo"
        case 1: "foto"
        case 2: "video"
        case 3: "audio"
        case 4: "contatto"
        case 5: "posizione"
        case 7: "link"
        case 8: "documento"
        case 11: "gif"
        case 14: "eliminato"
        case 15: "sticker"
        default: "altro"
        }
    }
}

extension Date {
    /// WhatsApp salva le date come secondi dal 1° gennaio 2001 (epoca Apple).
    init(whatsApp seconds: Double) {
        self.init(timeIntervalSinceReferenceDate: seconds)
    }
}
