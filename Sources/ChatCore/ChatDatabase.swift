import Foundation
import GRDB

public enum ChatDatabaseError: LocalizedError {
    case notFound(String)
    case permissionDenied(String)
    case incompatibleSchema([String])

    public var errorDescription: String? {
        switch self {
        case .notFound(let path):
            "Database di WhatsApp non trovato in \(path)."
        case .permissionDenied:
            "macOS non permette di leggere il database: serve Accesso completo al disco."
        case .incompatibleSchema(let missing):
            "Il database di WhatsApp ha una struttura diversa da quella prevista (mancano: \(missing.joined(separator: ", "))). Probabilmente WhatsApp è stato aggiornato."
        }
    }
}

/// Accesso in sola lettura a ChatStorage.sqlite.
///
/// Niente `immutable=1`: WhatsApp tiene il database aperto in modalità WAL e scrive lì i messaggi nuovi.
/// Ogni lettura apre una transazione propria, quindi vede l'ultimo stato salvato da WhatsApp ed è coerente al suo interno.
public final class ChatDatabase: Sendable {
    public let path: String
    private let dbQueue: DatabaseQueue
    private let pushNames: [String: String]

    /// Tabelle e colonne usate dalle query: se WhatsApp cambia lo schema ce ne accorgiamo all'apertura.
    static let requiredColumns: [String: [String]] = [
        "ZWAMESSAGE": ["Z_PK", "ZCHATSESSION", "ZMESSAGEDATE", "ZISFROMME", "ZMESSAGETYPE", "ZTEXT", "ZSTARRED", "ZFROMJID", "ZGROUPMEMBER", "ZMEDIAITEM"],
        "ZWACHATSESSION": ["Z_PK", "ZPARTNERNAME", "ZCONTACTJID", "ZSESSIONTYPE", "ZLASTMESSAGEDATE", "ZLASTMESSAGETEXT", "ZUNREADCOUNT", "ZARCHIVED", "ZREMOVED", "ZHIDDEN"],
        "ZWAGROUPMEMBER": ["Z_PK", "ZCONTACTNAME", "ZFIRSTNAME", "ZMEMBERJID"],
        "ZWAMEDIAITEM": ["Z_PK", "ZMEDIALOCALPATH", "ZFILESIZE", "ZMOVIEDURATION", "ZTITLE"],
        "ZWAPROFILEPUSHNAME": ["ZJID", "ZPUSHNAME"],
    ]

    public init(path: String) throws {
        switch DatabaseLocator.access(atPath: path) {
        case .missing: throw ChatDatabaseError.notFound(path)
        case .denied: throw ChatDatabaseError.permissionDenied(path)
        case .readable: break
        }
        var config = Configuration()
        config.readonly = true
        config.busyMode = .timeout(3)
        config.prepareDatabase { db in
            try db.execute(sql: "PRAGMA query_only = 1")
        }
        self.path = path
        dbQueue = try DatabaseQueue(path: path, configuration: config)

        let missing = try dbQueue.read { db in
            try Self.requiredColumns.flatMap { table, columns -> [String] in
                let existing = Set(try String.fetchAll(db, sql: "SELECT name FROM pragma_table_info(?)", arguments: [table]))
                if existing.isEmpty { return [table] }
                return columns.filter { !existing.contains($0) }.map { "\(table).\($0)" }
            }
        }
        guard missing.isEmpty else { throw ChatDatabaseError.incompatibleSchema(missing.sorted()) }

        pushNames = try dbQueue.read { db in
            var names: [String: String] = [:]
            for row in try Row.fetchAll(db, sql: "SELECT ZJID, ZPUSHNAME FROM ZWAPROFILEPUSHNAME WHERE ZJID IS NOT NULL AND ZPUSHNAME IS NOT NULL") {
                names[row[0]] = row[1]
            }
            return names
        }
    }

    func read<T>(_ block: (Database) throws -> T) throws -> T {
        try dbQueue.read(block)
    }

    // MARK: - Conteggi

    public func counts() throws -> DatabaseCounts {
        try read { db in
            let chats = try Row.fetchOne(db, sql: """
                SELECT SUM(ZSESSIONTYPE = 0), SUM(ZSESSIONTYPE = 1) FROM ZWACHATSESSION
                WHERE ZSESSIONTYPE IN (0, 1) AND COALESCE(ZREMOVED, 0) = 0
                """)
            let messages = try Row.fetchOne(db, sql: """
                SELECT COUNT(*), MIN(m.ZMESSAGEDATE), MAX(m.ZMESSAGEDATE)
                FROM ZWAMESSAGE m JOIN ZWACHATSESSION s ON s.Z_PK = m.ZCHATSESSION
                WHERE \(Self.baseConditions(includeGroups: true)) AND m.ZMESSAGEDATE > 0
                """)
            return DatabaseCounts(
                chats: chats?[0] ?? 0,
                groups: chats?[1] ?? 0,
                messages: messages?[0] ?? 0,
                firstMessageDate: (messages?[1] as Double?).map(Date.init(whatsApp:)),
                lastMessageDate: (messages?[2] as Double?).map(Date.init(whatsApp:))
            )
        }
    }

    // MARK: - Chat

    public func chats(nameContains query: String? = nil, kind: ChatKind? = nil, unreadOnly: Bool = false, includeGroups: Bool = true, limit: Int = 30) throws -> [ChatSummary] {
        var conditions = ["ZSESSIONTYPE IN (0, 1)", "COALESCE(ZREMOVED, 0) = 0", "COALESCE(ZHIDDEN, 0) = 0"]
        var arguments: [(any DatabaseValueConvertible)?] = []
        if !includeGroups || kind == .direct { conditions.append("ZSESSIONTYPE = 0") }
        if kind == .group { conditions.append("ZSESSIONTYPE = 1") }
        if let query, !query.isEmpty {
            conditions.append("ZPARTNERNAME LIKE ? ESCAPE '\\'")
            arguments.append(Self.likePattern(query))
        }
        if unreadOnly { conditions.append("ZUNREADCOUNT != 0") }
        arguments.append(limit)
        return try read { db in
            try Row.fetchAll(db, sql: """
                SELECT Z_PK, ZPARTNERNAME, ZCONTACTJID, ZSESSIONTYPE, ZLASTMESSAGEDATE, ZLASTMESSAGETEXT, ZUNREADCOUNT, ZARCHIVED
                FROM ZWACHATSESSION WHERE \(conditions.joined(separator: " AND "))
                ORDER BY ZLASTMESSAGEDATE DESC LIMIT ?
                """, arguments: StatementArguments(arguments)).compactMap(Self.chat(from:))
        }
    }

    public func chat(id: Int64) throws -> ChatSummary? {
        try read { db in
            try Row.fetchOne(db, sql: """
                SELECT Z_PK, ZPARTNERNAME, ZCONTACTJID, ZSESSIONTYPE, ZLASTMESSAGEDATE, ZLASTMESSAGETEXT, ZUNREADCOUNT, ZARCHIVED
                FROM ZWACHATSESSION WHERE Z_PK = ? AND COALESCE(ZREMOVED, 0) = 0
                """, arguments: [id]).flatMap(Self.chat(from:))
        }
    }

    // MARK: - Messaggi

    public struct MessageFilter: Sendable {
        public var text: String?
        public var chatID: Int64?
        public var chatName: String?
        public var fromMe: Bool?
        public var since: Date?
        public var until: Date?
        /// Messaggi più vecchi di questo (paginazione all'indietro).
        public var beforeMessageID: Int64?
        public var includeGroups = true
        public var limit = 50

        public init() {}
    }

    /// Messaggi dal più recente al più vecchio.
    public func messages(_ filter: MessageFilter) throws -> [ChatMessage] {
        var conditions = [Self.baseConditions(includeGroups: filter.includeGroups)]
        var arguments: [(any DatabaseValueConvertible)?] = []
        if let text = filter.text, !text.isEmpty {
            conditions.append("m.ZTEXT LIKE ? ESCAPE '\\'")
            arguments.append(Self.likePattern(text))
        }
        if let chatID = filter.chatID {
            conditions.append("m.ZCHATSESSION = ?")
            arguments.append(chatID)
        }
        if let name = filter.chatName, !name.isEmpty {
            conditions.append("s.ZPARTNERNAME LIKE ? ESCAPE '\\'")
            arguments.append(Self.likePattern(name))
        }
        if let fromMe = filter.fromMe {
            conditions.append("m.ZISFROMME = ?")
            arguments.append(fromMe ? 1 : 0)
        }
        if let since = filter.since {
            conditions.append("m.ZMESSAGEDATE >= ?")
            arguments.append(since.timeIntervalSinceReferenceDate)
        }
        if let until = filter.until {
            conditions.append("m.ZMESSAGEDATE < ?")
            arguments.append(until.timeIntervalSinceReferenceDate)
        }
        if let before = filter.beforeMessageID {
            conditions.append("""
                (m.ZMESSAGEDATE < (SELECT ZMESSAGEDATE FROM ZWAMESSAGE WHERE Z_PK = ?)
                 OR (m.ZMESSAGEDATE = (SELECT ZMESSAGEDATE FROM ZWAMESSAGE WHERE Z_PK = ?) AND m.Z_PK < ?))
                """)
            arguments.append(contentsOf: [before, before, before])
        }
        arguments.append(filter.limit)
        return try read { db in
            try Row.fetchAll(db, sql: """
                \(Self.messageSelect)
                WHERE \(conditions.joined(separator: " AND "))
                ORDER BY m.ZMESSAGEDATE DESC, m.Z_PK DESC LIMIT ?
                """, arguments: StatementArguments(arguments)).map(message(from:))
        }
    }

    public struct UnreadChat: Codable, Sendable {
        public let chat: ChatSummary
        /// In ordine cronologico.
        public let messages: [ChatMessage]
    }

    /// Chat con messaggi non letti e gli ultimi messaggi ricevuti in ognuna.
    public func unread(maxChats: Int, perChat: Int, includeGroups: Bool) throws -> [UnreadChat] {
        try chats(unreadOnly: true, includeGroups: includeGroups, limit: maxChats).map { chat in
            // -1 = segnata come da leggere a mano: mostriamo qualche messaggio di contesto.
            let count = chat.unreadCount > 0 ? min(chat.unreadCount, perChat) : min(5, perChat)
            var filter = MessageFilter()
            filter.chatID = chat.id
            filter.fromMe = false
            filter.includeGroups = includeGroups
            filter.limit = count
            return UnreadChat(chat: chat, messages: try messages(filter).reversed())
        }
    }

    // MARK: - Allegati

    public func media(messageID: Int64? = nil, chatID: Int64? = nil, includeGroups: Bool = true, limit: Int = 20) throws -> [MediaInfo] {
        var conditions = [Self.baseConditions(includeGroups: includeGroups), "m.ZMESSAGETYPE IN (1, 2, 3, 4, 5, 8, 11, 15)"]
        var arguments: [(any DatabaseValueConvertible)?] = []
        if let messageID {
            conditions.append("m.Z_PK = ?")
            arguments.append(messageID)
        }
        if let chatID {
            conditions.append("m.ZCHATSESSION = ?")
            arguments.append(chatID)
        }
        arguments.append(limit)
        let root = DatabaseLocator.mediaRoot(forDatabase: path)
        return try read { db in
            try Row.fetchAll(db, sql: """
                SELECT m.Z_PK, m.ZMESSAGEDATE, m.ZISFROMME, m.ZMESSAGETYPE, s.ZPARTNERNAME, s.ZCONTACTJID,
                       mi.ZMEDIALOCALPATH, mi.ZFILESIZE, mi.ZMOVIEDURATION, mi.ZTITLE
                FROM ZWAMESSAGE m
                JOIN ZWACHATSESSION s ON s.Z_PK = m.ZCHATSESSION
                LEFT JOIN ZWAMEDIAITEM mi ON mi.Z_PK = m.ZMEDIAITEM
                WHERE \(conditions.joined(separator: " AND "))
                ORDER BY m.ZMESSAGEDATE DESC LIMIT ?
                """, arguments: StatementArguments(arguments)).map { row in
                let relative: String? = row["ZMEDIALOCALPATH"]
                let url = relative.map { root.appending(path: $0) }
                let duration: Int? = row["ZMOVIEDURATION"]
                let size: Int64? = row["ZFILESIZE"]
                return MediaInfo(
                    messageID: row["Z_PK"],
                    chatName: Self.displayName(partner: row["ZPARTNERNAME"], jid: row["ZCONTACTJID"]),
                    date: Date(whatsApp: row["ZMESSAGEDATE"]),
                    fromMe: (row["ZISFROMME"] as Int?) == 1,
                    kind: MessageKind.label(row["ZMESSAGETYPE"]),
                    title: row["ZTITLE"],
                    fileName: url?.lastPathComponent,
                    localPath: url?.path,
                    fileExists: url.map { FileManager.default.fileExists(atPath: $0.path) } ?? false,
                    fileSize: size.flatMap { $0 > 0 ? $0 : nil },
                    durationSeconds: duration.flatMap { $0 > 0 ? $0 : nil }
                )
            }
        }
    }

    // MARK: - Supporto

    static func baseConditions(includeGroups: Bool) -> String {
        let types = MessageKind.systemTypes.map(String.init).joined(separator: ", ")
        let sessions = includeGroups ? "s.ZSESSIONTYPE IN (0, 1)" : "s.ZSESSIONTYPE = 0"
        return "m.ZMESSAGETYPE NOT IN (\(types)) AND \(sessions) AND COALESCE(s.ZREMOVED, 0) = 0"
    }

    static let messageSelect = """
        SELECT m.Z_PK AS id, m.ZCHATSESSION AS chatID, s.ZPARTNERNAME AS partner, s.ZCONTACTJID AS jid,
               s.ZSESSIONTYPE AS sessionType, m.ZMESSAGEDATE AS date, m.ZISFROMME AS fromMe,
               m.ZMESSAGETYPE AS type, m.ZTEXT AS text, m.ZSTARRED AS starred, m.ZFROMJID AS fromJID,
               gm.ZCONTACTNAME AS memberName, gm.ZFIRSTNAME AS memberFirstName, gm.ZMEMBERJID AS memberJID
        FROM ZWAMESSAGE m
        JOIN ZWACHATSESSION s ON s.Z_PK = m.ZCHATSESSION
        LEFT JOIN ZWAGROUPMEMBER gm ON gm.Z_PK = m.ZGROUPMEMBER
        """

    func message(from row: Row) -> ChatMessage {
        let chatName = Self.displayName(partner: row["partner"], jid: row["jid"])
        let fromMe = (row["fromMe"] as Int?) == 1
        let sender: String
        if fromMe {
            sender = "Io"
        } else if (row["sessionType"] as Int?) == 1 {
            let jid: String? = row["memberJID"] ?? row["fromJID"]
            let candidates: [String?] = [row["memberName"], row["memberFirstName"], jid.flatMap { pushNames[$0] }]
            let name = candidates.compactMap { $0 }.first { !$0.isEmpty }
            sender = name ?? Self.displayName(partner: nil, jid: jid)
        } else {
            sender = chatName
        }
        let type: Int = row["type"]
        return ChatMessage(
            id: row["id"],
            chatID: row["chatID"],
            chatName: chatName,
            date: Date(whatsApp: row["date"]),
            fromMe: fromMe,
            sender: sender,
            text: row["text"],
            kind: MessageKind.label(type),
            starred: (row["starred"] as Int?) == 1
        )
    }

    static func chat(from row: Row) -> ChatSummary? {
        guard let kind = ChatKind(sessionType: row["ZSESSIONTYPE"]) else { return nil }
        return ChatSummary(
            id: row["Z_PK"],
            name: displayName(partner: row["ZPARTNERNAME"], jid: row["ZCONTACTJID"]),
            kind: kind,
            lastMessageDate: (row["ZLASTMESSAGEDATE"] as Double?).map(Date.init(whatsApp:)),
            lastMessagePreview: row["ZLASTMESSAGETEXT"],
            unreadCount: (row["ZUNREADCOUNT"] as Int?) ?? 0,
            archived: (row["ZARCHIVED"] as Int?) == 1
        )
    }

    /// Nome della rubrica, altrimenti il numero. Gli identificativi `@lid` non sono numeri di telefono.
    static func displayName(partner: String?, jid: String?) -> String {
        if let partner = partner?.trimmingCharacters(in: .whitespacesAndNewlines), !partner.isEmpty { return partner }
        guard let jid, let at = jid.firstIndex(of: "@") else { return "Sconosciuto" }
        return jid.hasSuffix("@s.whatsapp.net") ? "+\(jid[..<at])" : "Contatto sconosciuto"
    }

    static func likePattern(_ text: String) -> String {
        let escaped = text
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "%", with: "\\%")
            .replacingOccurrences(of: "_", with: "\\_")
        return "%\(escaped)%"
    }
}
