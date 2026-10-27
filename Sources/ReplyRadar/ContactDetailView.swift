import ChatCore
import SwiftUI

/// Il rapporto con un contatto nel periodo scelto: tu da una parte, loro dall'altra.
struct ContactDetailView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    let contact: ContactRef
    @State private var stats: ContactStats?
    @State private var loaded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(contact.name).font(.title.bold()).lineLimit(1)
                    Text("Ultimi \(model.periodDays) giorni").foregroundStyle(.secondary)
                }
                Spacer()
                Button("Chiudi") { dismiss() }.keyboardShortcut(.cancelAction)
            }

            if let since = stats?.waitingSince {
                Label("Aspetta una tua risposta da \(Format.duration(Date.now.timeIntervalSince(since))) (dal \(since.formatted(date: .abbreviated, time: .shortened)))", systemImage: "hourglass")
                    .foregroundStyle(.orange)
                    .font(.callout.weight(.medium))
            }

            if let stats, stats.sent + stats.received > 0 {
                Grid(alignment: .leading, horizontalSpacing: 24, verticalSpacing: 12) {
                    GridRow {
                        Text("")
                        Text("Tu").font(.headline)
                        Text("Loro").font(.headline)
                    }
                    Divider().gridCellUnsizedAxes(.horizontal)
                    row("Messaggi", "\(stats.sent)", "\(stats.received)")
                    row("Tempo di risposta", stats.myMedianReplySeconds.map(Format.duration) ?? "–", stats.theirMedianReplySeconds.map(Format.duration) ?? "–")
                    row("Risposte", "\(stats.myReplies)", "\(stats.theirReplies)")
                    row("Conversazioni avviate", "\(stats.startedByMe)", "\(stats.startedByThem)")
                    row("Riscritto senza risposta", "\(stats.nudgesSent)", "\(stats.nudgesReceived)")
                    row("Lunghezza media", stats.averageLengthMine.map { "\(Int($0)) caratteri" } ?? "–", stats.averageLengthTheirs.map { "\(Int($0)) caratteri" } ?? "–")
                    row("Vocali", "\(stats.voiceSent)", "\(stats.voiceReceived)")
                }
                .padding(16)
                .background(.quaternary.opacity(0.4), in: .rect(cornerRadius: 12))

                BalanceBar(mine: stats.sent, theirs: stats.received)

                if !stats.slowestReplies.isEmpty {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Le tue risposte più lente").font(.headline)
                        ForEach(stats.slowestReplies) { reply in
                            HStack {
                                Text("Messaggio del \(reply.askedAt.formatted(date: .abbreviated, time: .shortened))")
                                    .foregroundStyle(.secondary)
                                Spacer()
                                Text(Format.duration(reply.delaySeconds)).monospacedDigit()
                            }
                            .font(.callout)
                        }
                    }
                }

                if let summary = Self.summary(stats) {
                    Label(summary, systemImage: "lightbulb")
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            } else if loaded {
                Text(stats?.lastMessageDate.map { "Nessun messaggio nel periodo. L'ultimo è \($0.formatted(.relative(presentation: .named)))." }
                     ?? "Nessun messaggio nel periodo.")
                    .foregroundStyle(.secondary)
            } else {
                ProgressView().frame(maxWidth: .infinity)
            }
            Spacer(minLength: 0)
        }
        .padding(24)
        .frame(width: 540, height: 680)
        .task {
            stats = await model.contactStats(chatID: contact.id)
            loaded = true
        }
    }

    private func row(_ title: String, _ mine: String, _ theirs: String) -> some View {
        GridRow {
            Text(title).foregroundStyle(.secondary)
            Text(mine).monospacedDigit()
            Text(theirs).monospacedDigit()
        }
    }

    /// Una frase sola, scritta con regole semplici: niente AI.
    static func summary(_ stats: ContactStats) -> String? {
        if let mine = stats.myMedianReplySeconds, let theirs = stats.theirMedianReplySeconds, stats.myReplies >= 3, stats.theirReplies >= 3 {
            if mine > theirs * 3 && mine > 600 {
                return "Rispondi molto più lentamente di quanto rispondono a te (\(Format.duration(mine)) contro \(Format.duration(theirs)))."
            }
            if theirs > mine * 3 && theirs > 600 {
                return "Rispondi tu molto più in fretta di loro (\(Format.duration(mine)) contro \(Format.duration(theirs)))."
            }
        }
        let starts = stats.startedByMe + stats.startedByThem
        if starts >= 4 {
            let share = Double(stats.startedByMe) / Double(starts)
            if share >= 0.75 { return "Le conversazioni le avvii quasi sempre tu." }
            if share <= 0.25 { return "Le conversazioni le avviano quasi sempre loro." }
        }
        if stats.nudgesReceived >= 3 {
            return "Ti hanno dovuto riscrivere \(stats.nudgesReceived) volte perché non rispondevi."
        }
        return nil
    }
}

private struct BalanceBar: View {
    let mine: Int
    let theirs: Int

    var body: some View {
        let total = max(mine + theirs, 1)
        VStack(alignment: .leading, spacing: 6) {
            Text("Chi scrive di più").font(.headline)
            GeometryReader { proxy in
                HStack(spacing: 2) {
                    Rectangle().fill(Color.accentColor).frame(width: proxy.size.width * CGFloat(mine) / CGFloat(total))
                    Rectangle().fill(Color.secondary.opacity(0.35))
                }
                .clipShape(.rect(cornerRadius: 5))
            }
            .frame(height: 10)
            HStack {
                Text("Tu \(Format.percent(Double(mine) / Double(total)))")
                Spacer()
                Text("Loro \(Format.percent(Double(theirs) / Double(total)))")
            }
            .font(.caption).foregroundStyle(.secondary)
        }
    }
}
