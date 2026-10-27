import Charts
import ChatCore
import SwiftUI

enum DashboardTab: String, CaseIterable, Identifiable {
    case summary = "Riepilogo"
    case todo = "Da fare"
    case people = "Persone"
    case habits = "Abitudini"

    var id: Self { self }
}

struct DashboardView: View {
    @Environment(AppModel.self) private var model
    @State private var tab: DashboardTab = .summary

    var body: some View {
        @Bindable var model = model
        Group {
            if let overview = model.overview {
                switch tab {
                case .summary: SummaryTab(overview: overview, tab: $tab)
                case .todo: TodoTab(overview: overview)
                case .people: PeopleTab(people: overview.people)
                case .habits: HabitsTab(overview: overview)
                }
            } else if let error = model.databaseError {
                Label(error, systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .toolbar {
            ToolbarItem(placement: .principal) {
                Picker("Sezione", selection: $tab) {
                    ForEach(DashboardTab.allCases) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .fixedSize()
            }
            ToolbarItem(placement: .primaryAction) {
                // Su macOS 26 i menu in toolbar mostrano solo l'icona: il controllo segmentato mostra il testo.
                Picker("Periodo", selection: $model.periodDays) {
                    Text("7 giorni").tag(7)
                    Text("30 giorni").tag(30)
                    Text("90 giorni").tag(90)
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .fixedSize()
                .disabled(tab == .todo)
                .help(tab == .todo ? "Le cose da fare guardano sempre gli ultimi 12 mesi." : "Periodo delle statistiche")
            }
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            DatabaseFooter()
        }
        .onChange(of: model.periodDays) { Task { await model.refresh() } }
        .sheet(item: $model.selectedContact) { contact in
            ContactDetailView(contact: contact)
                .environment(model)
        }
    }
}

// MARK: - Riepilogo

private struct SummaryTab: View {
    let overview: Overview
    @Binding var tab: DashboardTab

    var body: some View {
        TabPage {
            KeyFigures(overview: overview)
            TrendChart(overview: overview)
            // Solo ciò che è successo nel periodo: le attese più vecchie stanno in "Da fare" e "Persone".
            let start = overview.generatedAt.addingTimeInterval(-Double(overview.days) * 86400)
            let slowest = Array(overview.people
                .filter { $0.periodWorst(since: start) > 0 }
                .sorted { $0.periodWorst(since: start) > $1.periodWorst(since: start) }
                .prefix(6))
            Card(title: "Chi fai aspettare di più", subtitle: "Negli ultimi \(overview.days) giorni: la tua risposta più lenta, oppure da quanto aspettano se ti hanno scritto nel periodo.") {
                if slowest.isEmpty {
                    Text("Nessuna risposta lenta nel periodo.").foregroundStyle(.secondary)
                }
                VStack(spacing: 0) {
                    ForEach(slowest) { person in
                        PersonRow(person: person, since: start)
                        if person.id != slowest.last?.id { Divider() }
                    }
                }
                Button("Vedi tutte le persone, anche le attese più vecchie") { tab = .people }.buttonStyle(.link)
            }
        }
    }
}

private struct KeyFigures: View {
    @Environment(AppModel.self) private var model
    let overview: Overview

    var body: some View {
        let now = overview.current
        let before = overview.previous
        let oldest = overview.waitingOnMe.min { $0.waitingSince < $1.waitingSince }
        let workHours = model.settings.workHours
        VStack(alignment: .leading, spacing: 8) {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 220), spacing: 12)], spacing: 12) {
                Tile(
                    title: "Risposta tipica",
                    value: now.medianReplySeconds.map(Format.duration) ?? "–",
                    caption: "Metà delle tue risposte arriva entro questo tempo",
                    delta: .relative(now.medianReplySeconds, before.medianReplySeconds, lowerIsBetter: true)
                )
                Tile(
                    title: "Il 10% più lento",
                    value: now.p90ReplySeconds.map(Format.duration) ?? "–",
                    caption: "Una risposta su dieci arriva dopo questo tempo · \(now.overDayCount) oltre un giorno",
                    delta: .relative(now.p90ReplySeconds, before.p90ReplySeconds, lowerIsBetter: true)
                )
                Tile(
                    title: "Aspettano te",
                    value: "\(overview.waitingOnMe.count)",
                    caption: oldest.map { "Ultimi 12 mesi, qualunque periodo. Da più tempo: \($0.name), da \(Format.duration(Date.now.timeIntervalSince($0.waitingSince)))" } ?? "Nessuno negli ultimi 12 mesi",
                    delta: nil
                )
                Tile(
                    title: "Entro un'ora",
                    value: Format.percent(now.withinHourShare),
                    caption: "Delle tue \(now.replyCount.formatted()) risposte nel periodo",
                    delta: .points(now.withinHourShare, before.withinHourShare, lowerIsBetter: false)
                )
                Tile(
                    title: "Ti hanno riscritto",
                    value: "\(now.nudgesReceived)",
                    caption: "Volte in cui ti hanno scritto di nuovo perché non rispondevi",
                    delta: .relative(Double(now.nudgesReceived), Double(before.nudgesReceived), lowerIsBetter: true)
                )
                Tile(
                    title: "Fuori orario",
                    value: Format.percent(now.afterHoursShare),
                    caption: "Dei tuoi messaggi, fuori dalle \(workHours.startHour)–\(workHours.endHour) \(workHours.includesSaturday ? "lun–sab" : "lun–ven")",
                    delta: .points(now.afterHoursShare, before.afterHoursShare, lowerIsBetter: true)
                )
            }
            Text("Chat singole, gruppi esclusi\(overview.workTimeOnly ? ", tempi contati in orario di lavoro" : ""). Le frecce confrontano con i \(overview.days) giorni precedenti.")
                .font(.caption).foregroundStyle(.secondary)
        }
    }
}

private struct TrendChart: View {
    let overview: Overview

    var body: some View {
        let points = overview.trend.filter { $0.medianSeconds != nil }
        let unit: Calendar.Component = overview.trendIsDaily ? .day : .weekOfYear
        let step = overview.trendIsDaily ? "giorno per giorno" : "settimana per settimana"
        Card(title: "Stai migliorando?", subtitle: "Risposta tipica \(step) negli ultimi \(overview.days) giorni (contano \(overview.trendIsDaily ? "i giorni" : "le settimane") con almeno 3 risposte). La linea tratteggiata è la risposta tipica del periodo. Più basso è meglio.") {
            if points.count < 2 {
                Text("Servono almeno due \(overview.trendIsDaily ? "giorni" : "settimane") con qualche risposta.").foregroundStyle(.secondary)
            } else {
                Chart {
                    ForEach(points) { point in
                        LineMark(x: .value("Data", point.start, unit: unit), y: .value("Minuti", point.medianSeconds! / 60))
                        PointMark(x: .value("Data", point.start, unit: unit), y: .value("Minuti", point.medianSeconds! / 60))
                            .annotation(position: .top) {
                                // Con tanti punti le etichette si sovrappongono.
                                if points.count <= 14 {
                                    Text(Format.duration(point.medianSeconds!)).font(.caption2).foregroundStyle(.secondary)
                                }
                            }
                    }
                    .foregroundStyle(Color.accentColor)
                    if let median = overview.current.medianReplySeconds {
                        RuleMark(y: .value("Tipica", median / 60))
                            .foregroundStyle(.secondary)
                            .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 4]))
                    }
                }
                .chartXAxis {
                    AxisMarks(values: .automatic(desiredCount: 7)) { _ in
                        AxisGridLine()
                        AxisValueLabel(format: .dateTime.day().month(.abbreviated))
                    }
                }
                .chartYAxisLabel("minuti")
                .frame(height: 170)
            }
        }
    }
}

private struct PersonRow: View {
    let person: PersonStats
    let since: Date

    var body: some View {
        HStack {
            ContactButton(id: person.chatID, name: person.name) {
                Text(person.name).lineLimit(1)
            }
            Spacer()
            if let waiting = person.waitingSince, waiting >= since, Date.now.timeIntervalSince(waiting) >= (person.slowestReplySeconds ?? 0) {
                Text("aspetta da").font(.callout).foregroundStyle(.secondary)
                Text(Format.duration(Date.now.timeIntervalSince(waiting)))
                    .font(.body.weight(.medium)).monospacedDigit().foregroundStyle(.orange)
                    .frame(minWidth: 90, alignment: .trailing)
            } else if let slowest = person.slowestReplySeconds {
                Text("risposta più lenta").font(.callout).foregroundStyle(.secondary)
                Text(Format.duration(slowest))
                    .font(.body.weight(.medium)).monospacedDigit()
                    .frame(minWidth: 90, alignment: .trailing)
            }
        }
        .padding(.vertical, 6)
    }
}

// MARK: - Da fare

private struct TodoTab: View {
    let overview: Overview

    var body: some View {
        TabPage {
            Text("Si guarda chi ha scritto per ultimo negli ultimi 12 mesi. Togli una chat con la ✕: torna se arriva un messaggio nuovo.")
                .font(.callout).foregroundStyle(.secondary)
            HStack(alignment: .top, spacing: 16) {
                WaitingOnMe(chats: overview.waitingOnMe)
                Card(title: "Aspetti tu (\(overview.waitingOnThem.count))", subtitle: "Hai scritto per ultimo e non ti rispondono da più di un giorno (ultimo mese).") {
                    PendingRows(chats: overview.waitingOnThem, empty: "Nessuna risposta in sospeso.")
                }
            }
        }
    }
}

/// Raggruppate per età, così le attese vecchie non si perdono in fondo alla lista.
private struct WaitingOnMe: View {
    let chats: [PendingChat]

    var body: some View {
        let week = Date.now.addingTimeInterval(-7 * 86400)
        let month = Date.now.addingTimeInterval(-30 * 86400)
        // In ogni gruppo prima chi aspetta da più tempo.
        let sorted = chats.sorted { $0.waitingSince < $1.waitingSince }
        let groups: [(String, [PendingChat])] = [
            ("Ultima settimana", sorted.filter { $0.waitingSince >= week }),
            ("Da 1 a 4 settimane", sorted.filter { $0.waitingSince < week && $0.waitingSince >= month }),
            ("Da più di un mese", sorted.filter { $0.waitingSince < month }),
        ]
        Card(title: "Aspettano te (\(chats.count))", subtitle: "L'ultimo messaggio è il loro.") {
            if chats.isEmpty {
                Text("Nessuno aspetta una tua risposta.").foregroundStyle(.secondary)
            }
            ForEach(groups.filter { !$0.1.isEmpty }, id: \.0) { title, items in
                VStack(alignment: .leading, spacing: 2) {
                    Text("\(title) · \(items.count)").font(.headline).padding(.top, 4)
                    PendingRows(chats: items, empty: "")
                }
            }
        }
    }
}

private struct PendingRows: View {
    @Environment(AppModel.self) private var model
    let chats: [PendingChat]
    let empty: String
    @State private var showsAll = false

    var body: some View {
        if chats.isEmpty {
            if !empty.isEmpty { Text(empty).foregroundStyle(.secondary) }
        } else {
            VStack(spacing: 0) {
                ForEach(showsAll ? chats : Array(chats.prefix(5))) { chat in
                    HStack(alignment: .top, spacing: 10) {
                        ContactButton(id: chat.chatID, name: chat.name) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(chat.name).font(.body.weight(.medium)).lineLimit(1)
                                Text(chat.lastText).font(.callout).foregroundStyle(.secondary).lineLimit(1)
                            }
                        }
                        Spacer(minLength: 6)
                        Text(Format.duration(Date.now.timeIntervalSince(chat.waitingSince)))
                            .font(.callout).foregroundStyle(.secondary).monospacedDigit()
                        Button {
                            Task { await model.dismiss(chat) }
                        } label: {
                            Image(systemName: "xmark.circle.fill").foregroundStyle(.tertiary)
                        }
                        .buttonStyle(.plain)
                        .help("Togli dalla lista. Torna se arriva un messaggio nuovo.")
                    }
                    .padding(.vertical, 7)
                    Divider()
                }
            }
            if chats.count > 5 {
                Button(showsAll ? "Mostra meno" : "Mostra tutte (\(chats.count))") { showsAll.toggle() }
                    .buttonStyle(.link)
            }
        }
    }
}

// MARK: - Persone

private struct PeopleTab: View {
    @Environment(AppModel.self) private var model
    let people: [PersonStats]
    @State private var query = ""
    @State private var selection: PersonStats.ID?
    @State private var sortOrder = [KeyPathComparator(\PersonStats.sortWorst, order: .reverse)]

    var body: some View {
        let rows = people
            .filter { query.isEmpty || $0.name.localizedCaseInsensitiveContains(query) }
            .sorted(using: sortOrder)
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Persone").font(.title2.bold())
                    Text("Chi ti ha scritto nel periodo o aspetta ancora una risposta. Clicca un'intestazione per ordinare, una riga per il dettaglio.")
                        .font(.callout).foregroundStyle(.secondary)
                }
                Spacer()
                TextField("Cerca", text: $query)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 180)
            }
            Table(rows, selection: $selection, sortOrder: $sortOrder) {
                TableColumn("Nome", value: \.name) { Text($0.name) }
                    .width(min: 140, ideal: 200)
                TableColumn("Risposta tipica", value: \.sortMedian) { person in
                    Text(person.medianReplySeconds.map(Format.duration) ?? "–").monospacedDigit()
                }
                TableColumn("Più lenta", value: \.sortSlowest) { person in
                    Text(person.slowestReplySeconds.map(Format.duration) ?? "–").monospacedDigit()
                }
                TableColumn("Oltre 1 giorno", value: \.slowReplies) { person in
                    Text(person.slowReplies > 0 ? "\(person.slowReplies)" : "–").monospacedDigit()
                }
                TableColumn("Aspetta da", value: \.sortWaiting) { person in
                    if let since = person.waitingSince {
                        Text(Format.duration(Date.now.timeIntervalSince(since))).monospacedDigit().foregroundStyle(.orange)
                    } else {
                        Text("–").foregroundStyle(.secondary)
                    }
                }
                TableColumn("Messaggi", value: \.messages) { person in
                    Text("\(person.messages)").monospacedDigit()
                }
            }
            .onChange(of: selection) {
                guard let id = selection, let person = people.first(where: { $0.id == id }) else { return }
                model.selectedContact = ContactRef(id: person.chatID, name: person.name)
                selection = nil
            }
        }
        .padding(20)
    }
}

extension PersonStats {
    var messages: Int { sent + received }
    var sortMedian: Double { medianReplySeconds ?? -1 }
    var sortSlowest: Double { slowestReplySeconds ?? -1 }
    var sortWaiting: Double { waitingSince.map { Date.now.timeIntervalSince($0) } ?? -1 }
    var sortWorst: Double { worstDelay() }

    /// Ritardo peggiore contando l'attesa aperta solo se è iniziata dopo `since`.
    func periodWorst(since: Date) -> Double {
        let waiting = waitingSince.flatMap { $0 >= since ? Date.now.timeIntervalSince($0) : nil } ?? 0
        return max(slowestReplySeconds ?? 0, waiting)
    }
}

// MARK: - Abitudini

private struct HabitsTab: View {
    let overview: Overview

    var body: some View {
        let now = overview.current
        let before = overview.previous
        TabPage {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 220), spacing: 12)], spacing: 12) {
                Tile(
                    title: "Avviate da te",
                    value: Format.percent(now.startedByMeShare),
                    caption: "Delle conversazioni: \(now.startedByMe) tu, \(now.startedByThem) loro",
                    delta: .points(now.startedByMeShare, before.startedByMeShare, lowerIsBetter: nil)
                )
                Tile(
                    title: "Messaggi",
                    value: "\(now.sent.formatted())",
                    caption: "Inviati · \(now.received.formatted()) ricevuti",
                    delta: .relative(Double(now.sent), Double(before.sent), lowerIsBetter: nil)
                )
                Tile(
                    title: "Vocali",
                    value: "\(now.voiceSent)",
                    caption: "Inviati · \(now.voiceReceived) ricevuti",
                    delta: .relative(Double(now.voiceSent), Double(before.voiceSent), lowerIsBetter: nil)
                )
            }
            ReplyChart(byHour: overview.byHour)
            WritingHeatmap(cells: overview.heatmap, afterHoursShare: now.afterHoursShare)
            HStack(alignment: .top, spacing: 16) {
                Card(title: "Rapporti sbilanciati", subtitle: "Le conversazioni le avvia quasi sempre la stessa persona.") {
                    if overview.unbalanced.isEmpty {
                        Text("Nessuno nel periodo.").foregroundStyle(.secondary)
                    }
                    ForEach(overview.unbalanced) { contact in
                        SimpleRow(
                            id: contact.chatID, name: contact.name,
                            detail: contact.startedByMe > contact.startedByThem ? "tu" : "loro",
                            value: "\(max(contact.startedByMe, contact.startedByThem)) su \(contact.startedByMe + contact.startedByThem)"
                        )
                    }
                }
                Card(title: "Si stanno raffreddando", subtitle: "Li sentivi spesso, ma non vi scrivete da più di un mese.") {
                    if overview.fading.isEmpty {
                        Text("Nessuno.").foregroundStyle(.secondary)
                    }
                    ForEach(overview.fading) { contact in
                        SimpleRow(
                            id: contact.chatID, name: contact.name, detail: "",
                            value: contact.lastMessageDate.formatted(.relative(presentation: .named))
                        )
                    }
                }
            }
        }
    }
}

private struct SimpleRow: View {
    let id: Int64
    let name: String
    let detail: String
    let value: String

    var body: some View {
        HStack {
            ContactButton(id: id, name: name) { Text(name).lineLimit(1) }
            Spacer()
            if !detail.isEmpty { Text(detail).font(.callout).foregroundStyle(.secondary) }
            Text(value).font(.callout.weight(.medium)).monospacedDigit()
        }
        .padding(.vertical, 4)
    }
}

private struct ReplyChart: View {
    let byHour: [HourReply]

    var body: some View {
        Card(title: "Velocità di risposta durante la giornata", subtitle: "In base all'ora in cui ti scrivono: minuti prima della tua risposta (tipica, ore con almeno 3 risposte).") {
            if byHour.isEmpty {
                Text("Non ci sono ancora abbastanza risposte nel periodo.").foregroundStyle(.secondary)
            } else {
                Chart(byHour) { item in
                    BarMark(x: .value("Ora", item.hour), y: .value("Minuti", item.medianSeconds / 60))
                        .foregroundStyle(Color.accentColor.gradient)
                }
                .chartXScale(domain: -0.5...23.5)
                .chartXAxis {
                    AxisMarks(values: [0, 3, 6, 9, 12, 15, 18, 21]) { value in
                        AxisGridLine()
                        AxisValueLabel { Text("\(value.as(Int.self) ?? 0):00") }
                    }
                }
                .chartYAxisLabel("minuti")
                .frame(height: 170)
            }
        }
    }
}

private struct WritingHeatmap: View {
    @Environment(AppModel.self) private var model
    let cells: [HeatCell]
    let afterHoursShare: Double?

    private static let days = ["lun", "mar", "mer", "gio", "ven", "sab", "dom"]

    var body: some View {
        let peak = max(cells.map(\.count).max() ?? 0, 1)
        let workHours = model.settings.workHours
        Card(
            title: "Quando scrivi",
            subtitle: "I tuoi messaggi per giorno e ora. Il tratteggio è l'orario di lavoro\(afterHoursShare.map { "; fuori orario: \(Format.percent($0))" } ?? "")."
        ) {
            VStack(alignment: .leading, spacing: 3) {
                ForEach(0..<7, id: \.self) { day in
                    HStack(spacing: 3) {
                        Text(Self.days[day]).font(.caption).foregroundStyle(.secondary).frame(width: 30, alignment: .leading)
                        ForEach(0..<24, id: \.self) { hour in
                            let count = cells[day * 24 + hour].count
                            let isWork = (day < 5 || (day == 5 && workHours.includesSaturday)) && hour >= workHours.startHour && hour < workHours.endHour
                            RoundedRectangle(cornerRadius: 3)
                                .fill(count == 0 ? Color.secondary.opacity(0.08) : Color.accentColor.opacity(0.15 + 0.85 * Double(count) / Double(peak)))
                                .overlay {
                                    if isWork {
                                        RoundedRectangle(cornerRadius: 3).strokeBorder(Color.secondary.opacity(0.35), style: StrokeStyle(lineWidth: 1, dash: [2, 2]))
                                    }
                                }
                                .frame(maxWidth: .infinity, minHeight: 16, maxHeight: 16)
                                .help("\(Self.days[day]) \(hour):00 · \(count) messaggi")
                        }
                    }
                }
                HStack(spacing: 3) {
                    Color.clear.frame(width: 30, height: 1)
                    ForEach(0..<24, id: \.self) { hour in
                        Text(hour.isMultiple(of: 6) ? "\(hour)" : "")
                            .font(.caption2).foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            }
        }
    }
}

// MARK: - Componenti

/// Pagina scorrevole con larghezza massima, uguale per tutte le schede.
private struct TabPage<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) { content }
                .padding(24)
                .frame(maxWidth: 960)
                .frame(maxWidth: .infinity)
        }
    }
}

/// Variazione rispetto al periodo precedente. `isBetter` nil = né meglio né peggio.
struct Delta {
    let text: String
    let isBetter: Bool?

    static func relative(_ current: Double?, _ previous: Double?, lowerIsBetter: Bool?) -> Delta? {
        guard let current, let previous, previous > 0 else { return nil }
        let change = (current - previous) / previous
        if abs(change) < 0.03 { return Delta(text: "stabile", isBetter: nil) }
        return Delta(
            text: "\(change < 0 ? "▼" : "▲") \(abs(change).formatted(.percent.precision(.fractionLength(0))))",
            isBetter: lowerIsBetter.map { (change < 0) == $0 }
        )
    }

    static func points(_ current: Double?, _ previous: Double?, lowerIsBetter: Bool?) -> Delta? {
        guard let current, let previous else { return nil }
        let points = Int(((current - previous) * 100).rounded())
        if points == 0 { return Delta(text: "stabile", isBetter: nil) }
        return Delta(
            text: "\(points < 0 ? "▼" : "▲") \(abs(points)) \(abs(points) == 1 ? "punto" : "punti")",
            isBetter: lowerIsBetter.map { (points < 0) == $0 }
        )
    }
}

private struct Tile: View {
    let title: String
    let value: String
    let caption: String
    let delta: Delta?

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.callout).foregroundStyle(.secondary)
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(value).font(.system(size: 30, weight: .semibold, design: .rounded)).monospacedDigit()
                if let delta {
                    Text(delta.text)
                        .font(.callout.weight(.medium))
                        .foregroundStyle(delta.isBetter.map { $0 ? Color.green : Color.orange } ?? .secondary)
                }
            }
            Text(caption).font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
        }
        .padding(16)
        .frame(maxWidth: .infinity, minHeight: 120, alignment: .topLeading)
        .background(.quaternary.opacity(0.5), in: .rect(cornerRadius: 12))
    }
}

/// Apre il dettaglio del contatto.
private struct ContactButton<Label: View>: View {
    @Environment(AppModel.self) private var model
    let id: Int64
    let name: String
    @ViewBuilder let label: Label

    var body: some View {
        Button {
            model.selectedContact = ContactRef(id: id, name: name)
        } label: {
            label.contentShape(.rect)
        }
        .buttonStyle(.plain)
        .help("Dettaglio del rapporto con \(name)")
    }
}

private struct DatabaseFooter: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        HStack(spacing: 6) {
            Circle().fill(model.database != nil ? .green : .orange).frame(width: 8, height: 8)
            if let counts = model.counts {
                Text("\(counts.messages.formatted()) messaggi · ultimo \(counts.lastMessageDate?.formatted(.relative(presentation: .named)) ?? "–")")
            } else {
                Text("Database non collegato")
            }
            if model.isLoading { ProgressView().controlSize(.mini) }
            Spacer()
        }
        .font(.caption)
        .foregroundStyle(.secondary)
        .padding(.horizontal, 16)
        .padding(.vertical, 6)
        .background(.bar)
    }
}

struct Card<Content: View>: View {
    let title: String
    let subtitle: String
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.title3.bold())
                Text(subtitle).font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
            content
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.quaternary.opacity(0.35), in: .rect(cornerRadius: 12))
    }
}

enum Format {
    /// "45 s", "12 min", "3 h 20 min", "2 g 4 h".
    static func duration(_ seconds: Double) -> String {
        let s = Int(max(seconds, 0))
        switch s {
        case ..<60: return "\(s) s"
        case ..<3600: return "\(s / 60) min"
        case ..<86400:
            let minutes = (s % 3600) / 60
            return minutes == 0 ? "\(s / 3600) h" : "\(s / 3600) h \(minutes) min"
        case ..<(30 * 86400):
            let hours = (s % 86400) / 3600
            return hours == 0 ? "\(s / 86400) g" : "\(s / 86400) g \(hours) h"
        default:
            return "\(s / 86400) giorni"
        }
    }

    static func percent(_ share: Double?) -> String {
        share.map { $0.formatted(.percent.precision(.fractionLength(0))) } ?? "–"
    }
}
