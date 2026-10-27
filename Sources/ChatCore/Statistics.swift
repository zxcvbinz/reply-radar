import Foundation
import GRDB

// MARK: - Risultati

/// Numeri di un periodo, confrontabili con il periodo precedente.
public struct PeriodStats: Codable, Sendable {
    public let replyCount: Int
    public let medianReplySeconds: Double?
    /// Il 10% delle risposte più lente arriva dopo questo tempo: la mediana da sola nasconde i ritardi lunghi.
    public let p90ReplySeconds: Double?
    public let withinHourShare: Double?
    public let overDayCount: Int
    public let sent: Int
    public let received: Int
    public let startedByMe: Int
    public let startedByThem: Int
    /// Hai riscritto senza aver ricevuto risposta (dopo almeno un'ora).
    public let nudgesSent: Int
    /// Ti hanno dovuto riscrivere perché non avevi risposto.
    public let nudgesReceived: Int
    /// Quota dei tuoi messaggi inviati fuori dall'orario di lavoro.
    public let afterHoursShare: Double?
    public let voiceSent: Int
    public let voiceReceived: Int

    public var startedByMeShare: Double? {
        let total = startedByMe + startedByThem
        return total > 0 ? Double(startedByMe) / Double(total) : nil
    }
}

public struct HourReply: Codable, Identifiable, Sendable {
    public var id: Int { hour }
    /// Ora in cui ti hanno scritto.
    public let hour: Int
    public let medianSeconds: Double
    public let count: Int
}

/// Un punto dell'andamento: un giorno (periodi fino a un mese) o una settimana.
public struct TrendPoint: Codable, Identifiable, Sendable {
    public var id: Date { start }
    public let start: Date
    public let medianSeconds: Double?
    public let count: Int
}

/// Messaggi inviati da te per giorno della settimana (0 = lunedì) e ora.
public struct HeatCell: Codable, Identifiable, Sendable {
    public var id: Int { weekday * 24 + hour }
    public let weekday: Int
    public let hour: Int
    public let count: Int
}

/// Come rispondi a una persona: tempo tipico, ritardi peggiori e attesa ancora aperta.
public struct PersonStats: Codable, Identifiable, Sendable {
    public var id: Int64 { chatID }
    public let chatID: Int64
    public let name: String
    /// Tue risposte nel periodo.
    public let replies: Int
    public let medianReplySeconds: Double?
    public let slowestReplySeconds: Double?
    /// Risposte arrivate dopo più di un giorno.
    public let slowReplies: Int
    public let sent: Int
    public let received: Int
    /// Se l'ultimo messaggio è il loro (negli ultimi 12 mesi): da quando aspettano.
    public let waitingSince: Date?
    public let lastMessageDate: Date

    /// Il ritardo peggiore: la risposta più lenta del periodo o l'attesa ancora aperta.
    public func worstDelay(now: Date = .now) -> Double {
        max(slowestReplySeconds ?? 0, waitingSince.map { now.timeIntervalSince($0) } ?? 0)
    }
}

public struct SlowReply: Codable, Identifiable, Sendable {
    public var id: Date { askedAt }
    public let askedAt: Date
    public let delaySeconds: Double
}

/// Rapporto in cui le conversazioni le avvia quasi sempre la stessa persona.
public struct BalanceContact: Codable, Identifiable, Sendable {
    public var id: Int64 { chatID }
    public let chatID: Int64
    public let name: String
    public let startedByMe: Int
    public let startedByThem: Int
}

/// Contatto con cui scrivevi spesso e che non senti da più di un mese.
public struct FadingContact: Codable, Identifiable, Sendable {
    public var id: Int64 { chatID }
    public let chatID: Int64
    public let name: String
    public let lastMessageDate: Date
    public let previousMessages: Int
}

public struct PendingChat: Codable, Identifiable, Sendable {
    public var id: Int64 { chatID }
    public let chatID: Int64
    public let name: String
    /// Primo messaggio rimasto senza risposta.
    public let waitingSince: Date
    public let lastMessageDate: Date
    public let lastText: String
    public let messageCount: Int
}

public struct Overview: Codable, Sendable {
    public let days: Int
    public let generatedAt: Date
    /// Tempi di risposta contati solo in orario di lavoro.
    public let workTimeOnly: Bool
    public let current: PeriodStats
    public let previous: PeriodStats
    public let byHour: [HourReply]
    /// Andamento nel periodo, dal punto più vecchio.
    public let trend: [TrendPoint]
    /// Vero se ogni punto è un giorno, falso se è una settimana.
    public let trendIsDaily: Bool
    public let heatmap: [HeatCell]
    /// Chi ha scritto o aspetta una risposta, dal ritardo peggiore.
    public let people: [PersonStats]
    public let unbalanced: [BalanceContact]
    public let fading: [FadingContact]
    /// L'ultimo messaggio è dell'altra persona, negli ultimi 12 mesi (indipendente dal periodo).
    public let waitingOnMe: [PendingChat]
    /// L'ultimo messaggio è tuo, fra 1 e 30 giorni fa, e non ha avuto risposta.
    public let waitingOnThem: [PendingChat]
}

public struct ContactStats: Codable, Sendable {
    public let chatID: Int64
    public let name: String
    public let days: Int
    public let sent: Int
    public let received: Int
    public let myMedianReplySeconds: Double?
    /// Le tue 5 risposte più lente nel periodo.
    public let slowestReplies: [SlowReply]
    /// Se l'ultimo messaggio è il loro: da quando aspettano.
    public let waitingSince: Date?
    public let theirMedianReplySeconds: Double?
    public let myReplies: Int
    public let theirReplies: Int
    public let startedByMe: Int
    public let startedByThem: Int
    public let averageLengthMine: Double?
    public let averageLengthTheirs: Double?
    public let nudgesSent: Int
    public let nudgesReceived: Int
    public let voiceSent: Int
    public let voiceReceived: Int
    public let firstMessageDate: Date?
    public let lastMessageDate: Date?
}

/// Orario di lavoro usato per i messaggi "fuori orario" e, se richiesto, per i tempi di risposta.
public struct WorkHours: Codable, Equatable, Sendable {
    public var startHour = 9
    public var endHour = 19
    public var includesSaturday = false

    public init() {}

    func isWorkday(_ date: Date, calendar: Calendar) -> Bool {
        // weekday: 1 domenica … 7 sabato.
        switch calendar.component(.weekday, from: date) {
        case 1: false
        case 7: includesSaturday
        default: true
        }
    }

    func contains(_ date: Date, calendar: Calendar) -> Bool {
        let hour = calendar.component(.hour, from: date)
        return isWorkday(date, calendar: calendar) && hour >= startHour && hour < endHour
    }

    /// Secondi lavorativi fra due istanti: le notti e i weekend non contano.
    func workingSeconds(from start: Date, to end: Date, calendar: Calendar) -> Double {
        guard end > start else { return 0 }
        var total = 0.0
        var day = calendar.startOfDay(for: start)
        // Limite di sicurezza: oltre un anno di attesa il dettaglio non serve.
        for _ in 0..<400 where day < end {
            if isWorkday(day, calendar: calendar),
               let open = calendar.date(bySettingHour: startHour, minute: 0, second: 0, of: day),
               let close = calendar.date(bySettingHour: endHour, minute: 0, second: 0, of: day) {
                let from = max(open, start), to = min(close, end)
                if to > from { total += to.timeIntervalSince(from) }
            }
            guard let next = calendar.date(byAdding: .day, value: 1, to: day) else { break }
            day = next
        }
        return total
    }
}

// MARK: - Calcolo

extension ChatDatabase {
    /// Pausa oltre la quale un messaggio apre una nuova conversazione.
    static let conversationGap: TimeInterval = 8 * 3600
    /// Pausa oltre la quale un secondo messaggio senza risposta conta come sollecito.
    static let nudgeGap: TimeInterval = 3600
    static let voiceType = 3

    /// Statistiche delle chat singole negli ultimi `days` giorni, confrontate con i `days` giorni prima.
    /// Solo conteggi e tempi: nessuna AI, niente esce dal Mac.
    public func overview(
        days: Int,
        now: Date = .now,
        dismissed: [String: Double] = [:],
        workHours: WorkHours = WorkHours(),
        workTimeOnly: Bool = false
    ) throws -> Overview {
        let calendar = Calendar.current
        let day = 86400.0
        let start = now.addingTimeInterval(-Double(days) * day)
        let previousStart = now.addingTimeInterval(-2 * Double(days) * day)
        // Serve abbastanza storia per il periodo precedente, le 12 settimane e i contatti che si raffreddano.
        // Le attese aperte si cercano negli ultimi 12 mesi, qualunque sia il periodo.
        let horizon = now.addingTimeInterval(-max(2 * Double(days), 365) * day)
        let pendingHorizon = now.addingTimeInterval(-365 * day)
        let chats = try loadChats(since: horizon)
        let analyses = chats.mapValues { ChatAnalysis($0.items, workHours: workHours, workTimeOnly: workTimeOnly, calendar: calendar) }

        let current = periodStats(chats: chats, analyses: analyses, from: start, to: now, workHours: workHours, calendar: calendar)
        let previous = periodStats(chats: chats, analyses: analyses, from: previousStart, to: start, workHours: workHours, calendar: calendar)

        // Velocità per ora e per contatto, nel periodo scelto.
        var delaysByHour: [Int: [Double]] = [:]
        var unbalanced: [BalanceContact] = []
        for (chatID, analysis) in analyses {
            let replies = analysis.myReplies.filter { $0.date >= start && $0.date < now }
            for reply in replies {
                delaysByHour[calendar.component(.hour, from: reply.askedAt), default: []].append(reply.delay)
            }
            let starts = analysis.starts.filter { $0.date >= start && $0.date < now }
            let mine = starts.filter(\.fromMe).count
            if starts.count >= 4, mine * 4 >= starts.count * 3 || mine * 4 <= starts.count {
                unbalanced.append(BalanceContact(chatID: chatID, name: chats[chatID]!.name, startedByMe: mine, startedByThem: starts.count - mine))
            }
        }
        // Le ore con meno di 3 risposte darebbero barre casuali.
        let byHour = delaysByHour.compactMap { hour, values in
            values.count < 3 ? nil : Self.median(values).map { HourReply(hour: hour, medianSeconds: $0, count: values.count) }
        }.sorted { $0.hour < $1.hour }

        // Andamento nel periodo: un punto al giorno fino a un mese, poi uno a settimana.
        let trendIsDaily = days <= 31
        let unit: Calendar.Component = trendIsDaily ? .day : .weekOfYear
        let buckets = trendIsDaily ? days : Int((Double(days) / 7).rounded(.up))
        var trend: [TrendPoint] = []
        if let current = calendar.dateInterval(of: unit, for: now)?.start {
            for offset in (0..<buckets).reversed() {
                guard let bucketStart = calendar.date(byAdding: unit, value: -offset, to: current),
                      let bucketEnd = calendar.date(byAdding: unit, value: 1, to: bucketStart) else { continue }
                let delays = analyses.values.flatMap { $0.myReplies.filter { $0.date >= bucketStart && $0.date < bucketEnd }.map(\.delay) }
                trend.append(TrendPoint(start: bucketStart, medianSeconds: delays.count >= 3 ? Self.median(delays) : nil, count: delays.count))
            }
        }

        var heat = Array(repeating: 0, count: 7 * 24)
        for chat in chats.values {
            for item in chat.items where item.fromMe && item.date >= start && item.date < now {
                let weekday = (calendar.component(.weekday, from: item.date) + 5) % 7
                heat[weekday * 24 + calendar.component(.hour, from: item.date)] += 1
            }
        }
        let heatmap = heat.enumerated().map { HeatCell(weekday: $0.offset / 24, hour: $0.offset % 24, count: $0.element) }

        // Contatti che si raffreddano: almeno 20 messaggi fra 6 e 1 mese fa, nessuno nell'ultimo mese.
        let monthAgo = now.addingTimeInterval(-30 * day)
        let fading = chats.compactMap { chatID, chat -> FadingContact? in
            guard !chat.archived, let last = chat.items.last, last.date < monthAgo else { return nil }
            let previous = chat.items.filter { $0.date >= now.addingTimeInterval(-180 * day) }.count
            return previous >= 20 ? FadingContact(chatID: chatID, name: chat.name, lastMessageDate: last.date, previousMessages: previous) : nil
        }

        // Cose in sospeso: si guarda chi ha scritto per ultimo.
        var waitingOnMe: [PendingChat] = []
        var waitingOnThem: [PendingChat] = []
        for (chatID, chat) in chats where !chat.archived {
            let turns = Self.turns(chat.items)
            guard let last = turns.last, let lastMessage = last.last, lastMessage.date >= pendingHorizon,
                  dismissed[String(chatID)] != lastMessage.date.timeIntervalSinceReferenceDate else { continue }
            let pending = PendingChat(
                chatID: chatID, name: chat.name, waitingSince: last[0].date,
                lastMessageDate: lastMessage.date, lastText: lastMessage.preview, messageCount: last.count
            )
            let age = now.timeIntervalSince(lastMessage.date)
            if !lastMessage.fromMe {
                waitingOnMe.append(pending)
            } else if turns.count > 1, age > day, age < 30 * day {
                waitingOnThem.append(pending)
            }
        }

        // Persone: chi ha scritto nel periodo o aspetta ancora una tua risposta.
        let waitingByChat = Dictionary(uniqueKeysWithValues: waitingOnMe.map { ($0.chatID, $0.waitingSince) })
        let people = chats.compactMap { chatID, chat -> PersonStats? in
            let items = chat.items.filter { $0.date >= start && $0.date < now }
            let waitingSince = waitingByChat[chatID]
            guard let lastItem = chat.items.last, !items.isEmpty || waitingSince != nil else { return nil }
            let delays = analyses[chatID]!.myReplies.filter { $0.date >= start && $0.date < now }.map(\.delay)
            return PersonStats(
                chatID: chatID, name: chat.name, replies: delays.count,
                medianReplySeconds: Self.median(delays), slowestReplySeconds: delays.max(),
                slowReplies: delays.filter { $0 > day }.count,
                sent: items.filter(\.fromMe).count, received: items.filter { !$0.fromMe }.count,
                waitingSince: waitingSince, lastMessageDate: lastItem.date
            )
        }

        return Overview(
            days: days,
            generatedAt: now,
            workTimeOnly: workTimeOnly,
            current: current,
            previous: previous,
            byHour: byHour,
            trend: trend,
            trendIsDaily: trendIsDaily,
            heatmap: heatmap,
            people: people.sorted { $0.worstDelay(now: now) > $1.worstDelay(now: now) },
            unbalanced: Array(unbalanced.sorted { ($0.startedByMe + $0.startedByThem) > ($1.startedByMe + $1.startedByThem) }.prefix(6)),
            fading: Array(fading.sorted { $0.previousMessages > $1.previousMessages }.prefix(6)),
            waitingOnMe: waitingOnMe.sorted { $0.lastMessageDate > $1.lastMessageDate },
            waitingOnThem: waitingOnThem.sorted { $0.lastMessageDate > $1.lastMessageDate }
        )
    }

    /// Il rapporto con un solo contatto negli ultimi `days` giorni.
    public func contactStats(chatID: Int64, days: Int, now: Date = .now, workHours: WorkHours = WorkHours(), workTimeOnly: Bool = false) throws -> ContactStats? {
        let start = now.addingTimeInterval(-Double(days) * 86400)
        // Si carica almeno un anno per sapere se c'è un'attesa aperta anche fuori dal periodo.
        let horizon = min(start, now.addingTimeInterval(-365 * 86400))
        guard let summary = try self.chat(id: chatID), summary.kind == .direct else { return nil }
        let chat = try loadChats(since: horizon, chatID: chatID)[chatID]
        let all = chat?.items ?? []
        let analysis = ChatAnalysis(all, workHours: workHours, workTimeOnly: workTimeOnly, calendar: .current)
        func inPeriod(_ date: Date) -> Bool { date >= start && date < now }
        let items = all.filter { inPeriod($0.date) }
        let mine = items.filter(\.fromMe)
        let theirs = items.filter { !$0.fromMe }
        let myReplies = analysis.myReplies.filter { inPeriod($0.date) }
        let theirReplies = analysis.theirReplies.filter { inPeriod($0.date) }
        let starts = analysis.starts.filter { inPeriod($0.date) }
        let nudges = analysis.nudges.filter { inPeriod($0.date) }
        let lastTurn = Self.turns(all).last
        func averageLength(_ items: [Item]) -> Double? {
            let lengths = items.map(\.length).filter { $0 > 0 }
            return lengths.isEmpty ? nil : Double(lengths.reduce(0, +)) / Double(lengths.count)
        }
        return ContactStats(
            chatID: chatID,
            name: chat?.name ?? summary.name,
            days: days,
            sent: mine.count,
            received: theirs.count,
            myMedianReplySeconds: Self.median(myReplies.map(\.delay)),
            slowestReplies: Array(myReplies.sorted { $0.delay > $1.delay }.prefix(5).map { SlowReply(askedAt: $0.askedAt, delaySeconds: $0.delay) }),
            waitingSince: lastTurn.flatMap { $0[0].fromMe ? nil : $0[0].date },
            theirMedianReplySeconds: Self.median(theirReplies.map(\.delay)),
            myReplies: myReplies.count,
            theirReplies: theirReplies.count,
            startedByMe: starts.filter(\.fromMe).count,
            startedByThem: starts.filter { !$0.fromMe }.count,
            averageLengthMine: averageLength(mine),
            averageLengthTheirs: averageLength(theirs),
            nudgesSent: nudges.filter(\.fromMe).count,
            nudgesReceived: nudges.filter { !$0.fromMe }.count,
            voiceSent: mine.filter { $0.type == Self.voiceType }.count,
            voiceReceived: theirs.filter { $0.type == Self.voiceType }.count,
            firstMessageDate: items.first?.date,
            lastMessageDate: all.last?.date ?? summary.lastMessageDate
        )
    }

    // MARK: - Supporto

    struct Item {
        let date: Date
        let fromMe: Bool
        let type: Int
        let preview: String
        /// Caratteri del testo, 0 per gli allegati.
        let length: Int
    }

    struct ChatItems {
        let name: String
        let archived: Bool
        var items: [Item]
    }

    /// Eventi di una chat calcolati una volta sola su tutta la storia caricata, poi filtrati per periodo.
    struct ChatAnalysis {
        struct Reply {
            /// Quando è arrivata la risposta.
            let date: Date
            /// Primo messaggio rimasto senza risposta.
            let askedAt: Date
            let delay: Double
        }

        struct Event {
            let date: Date
            let fromMe: Bool
        }

        var myReplies: [Reply] = []
        var theirReplies: [Reply] = []
        var starts: [Event] = []
        var nudges: [Event] = []

        init(_ items: [Item], workHours: WorkHours, workTimeOnly: Bool, calendar: Calendar) {
            var previous: Item?
            for item in items {
                if previous.map({ item.date.timeIntervalSince($0.date) > ChatDatabase.conversationGap }) ?? true {
                    starts.append(Event(date: item.date, fromMe: item.fromMe))
                }
                previous = item
            }
            let turns = ChatDatabase.turns(items)
            // Un sollecito per turno al massimo: il primo messaggio scritto dopo un'ora di silenzio senza risposta.
            for turn in turns {
                if let nudge = zip(turn, turn.dropFirst()).first(where: { $1.date.timeIntervalSince($0.date) >= ChatDatabase.nudgeGap })?.1 {
                    nudges.append(Event(date: nudge.date, fromMe: nudge.fromMe))
                }
            }
            // Il tempo di risposta parte dal primo messaggio del turno dell'altro.
            for (asked, answer) in zip(turns, turns.dropFirst()) {
                let delay = workTimeOnly
                    ? workHours.workingSeconds(from: asked[0].date, to: answer[0].date, calendar: calendar)
                    : answer[0].date.timeIntervalSince(asked[0].date)
                let reply = Reply(date: answer[0].date, askedAt: asked[0].date, delay: delay)
                if answer[0].fromMe { myReplies.append(reply) } else { theirReplies.append(reply) }
            }
        }
    }

    func periodStats(chats: [Int64: ChatItems], analyses: [Int64: ChatAnalysis], from start: Date, to end: Date, workHours: WorkHours, calendar: Calendar) -> PeriodStats {
        func inRange(_ date: Date) -> Bool { date >= start && date < end }
        let items = chats.values.flatMap { $0.items.filter { inRange($0.date) } }
        let mine = items.filter(\.fromMe)
        let delays = analyses.values.flatMap { $0.myReplies.filter { inRange($0.date) }.map(\.delay) }
        let starts = analyses.values.flatMap { $0.starts.filter { inRange($0.date) } }
        let nudges = analyses.values.flatMap { $0.nudges.filter { inRange($0.date) } }
        let afterHours = mine.filter { !workHours.contains($0.date, calendar: calendar) }.count
        return PeriodStats(
            replyCount: delays.count,
            medianReplySeconds: Self.median(delays),
            p90ReplySeconds: Self.percentile(delays, 0.9),
            withinHourShare: delays.isEmpty ? nil : Double(delays.filter { $0 <= 3600 }.count) / Double(delays.count),
            overDayCount: delays.filter { $0 > 86400 }.count,
            sent: mine.count,
            received: items.count - mine.count,
            startedByMe: starts.filter(\.fromMe).count,
            startedByThem: starts.filter { !$0.fromMe }.count,
            nudgesSent: nudges.filter(\.fromMe).count,
            nudgesReceived: nudges.filter { !$0.fromMe }.count,
            afterHoursShare: mine.isEmpty ? nil : Double(afterHours) / Double(mine.count),
            voiceSent: mine.filter { $0.type == Self.voiceType }.count,
            voiceReceived: items.filter { !$0.fromMe && $0.type == Self.voiceType }.count
        )
    }

    /// Messaggi delle chat singole (non nascoste) dal più vecchio, raggruppati per chat.
    func loadChats(since: Date, chatID: Int64? = nil) throws -> [Int64: ChatItems] {
        var sql = """
            SELECT m.ZCHATSESSION AS chatID, m.ZMESSAGEDATE AS date, m.ZISFROMME AS fromMe,
                   m.ZMESSAGETYPE AS type, m.ZTEXT AS text,
                   s.ZPARTNERNAME AS partner, s.ZCONTACTJID AS jid, s.ZARCHIVED AS archived
            FROM ZWAMESSAGE m JOIN ZWACHATSESSION s ON s.Z_PK = m.ZCHATSESSION
            WHERE \(Self.baseConditions(includeGroups: false)) AND COALESCE(s.ZHIDDEN, 0) = 0
              AND m.ZMESSAGEDATE >= ?
            """
        var arguments: [(any DatabaseValueConvertible)?] = [since.timeIntervalSinceReferenceDate]
        if let chatID {
            sql += " AND m.ZCHATSESSION = ?"
            arguments.append(chatID)
        }
        sql += " ORDER BY m.ZCHATSESSION, m.ZMESSAGEDATE"
        let rows = try read { db in try Row.fetchAll(db, sql: sql, arguments: StatementArguments(arguments)) }

        var chats: [Int64: ChatItems] = [:]
        for row in rows {
            let id: Int64 = row["chatID"]
            let type: Int = row["type"]
            let text = (row["text"] as String?).flatMap { $0.isEmpty ? nil : $0 }
            let item = Item(
                date: Date(whatsApp: row["date"]),
                fromMe: (row["fromMe"] as Int?) == 1,
                type: type,
                preview: text ?? "[\(MessageKind.label(type))]",
                length: text?.count ?? 0
            )
            if chats[id] == nil {
                chats[id] = ChatItems(name: Self.displayName(partner: row["partner"], jid: row["jid"]), archived: (row["archived"] as Int?) == 1, items: [])
            }
            chats[id]?.items.append(item)
        }
        return chats
    }

    /// Turni: messaggi consecutivi della stessa persona.
    static func turns(_ items: [Item]) -> [[Item]] {
        var turns: [[Item]] = []
        for item in items {
            if let last = turns.last?.last, last.fromMe == item.fromMe {
                turns[turns.count - 1].append(item)
            } else {
                turns.append([item])
            }
        }
        return turns
    }

    static func percentile(_ values: [Double], _ fraction: Double) -> Double? {
        guard !values.isEmpty else { return nil }
        let sorted = values.sorted()
        return sorted[min(Int((Double(sorted.count - 1) * fraction).rounded()), sorted.count - 1)]
    }

    static func median(_ values: [Double]) -> Double? {
        guard !values.isEmpty else { return nil }
        let sorted = values.sorted()
        let mid = sorted.count / 2
        return sorted.count.isMultiple(of: 2) ? (sorted[mid - 1] + sorted[mid]) / 2 : sorted[mid]
    }
}
