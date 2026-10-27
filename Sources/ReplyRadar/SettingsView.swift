import ChatCore
import SwiftUI

struct SettingsView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var model = model
        Form {
            Section("Database di WhatsApp") {
                LabeledContent("Percorso") {
                    Text(model.databasePath ?? "Non trovato")
                        .font(.callout.monospaced())
                        .textSelection(.enabled)
                        .lineLimit(2)
                        .truncationMode(.middle)
                }
                if let info = model.databaseInfo {
                    LabeledContent("Ultimo aggiornamento", value: info.modified.formatted(.relative(presentation: .named)))
                }
                if let error = model.databaseError {
                    Text(error).foregroundStyle(.orange)
                }
                HStack {
                    Button("Trova automaticamente") {
                        model.settings.databasePath = nil
                        model.locateDatabase()
                        Task { await model.refresh() }
                    }
                    Button("Scegli…") {
                        model.chooseDatabaseManually()
                        Task { await model.refresh() }
                    }
                }
            }

            Section("Permessi") {
                LabeledContent("Accesso completo al disco") {
                    Label(model.hasDiskAccess ? "Attivo" : "Non attivo",
                          systemImage: model.hasDiskAccess ? "checkmark.circle.fill" : "xmark.circle.fill")
                        .foregroundStyle(model.hasDiskAccess ? .green : .orange)
                }
                Button("Apri Impostazioni di Sistema") { model.openFullDiskAccessSettings() }
            }

            Section {
                LabeledContent("Stato") {
                    if model.isRegisteredInClaudeCode {
                        Label("Collegato", systemImage: "checkmark.circle.fill").foregroundStyle(.green)
                    } else if !model.mcpExecutableExists {
                        Label("Server MCP mancante: ricompila l'app", systemImage: "exclamationmark.triangle.fill").foregroundStyle(.orange)
                    } else {
                        Text("Non collegato").foregroundStyle(.secondary)
                    }
                }
                Text(model.integrationCommand)
                    .font(.caption.monospaced())
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
                Button("Copia il comando") { model.copyIntegrationCommand() }
            } header: {
                Text("Claude Code")
            } footer: {
                Text("Incolla il comando nel Terminale. Claude Code avvia il collegamento dal Terminale: anche il Terminale deve avere l'Accesso completo al disco.")
            }

            Section {
                Toggle("Claude può leggere i gruppi", isOn: $model.settings.allowGroupsInMCP)
                Stepper(value: $model.settings.maxMessagesPerRequest, in: 20...500, step: 20) {
                    LabeledContent("Massimo messaggi per richiesta", value: "\(model.settings.maxMessagesPerRequest)")
                }
            } header: {
                Text("Privacy con Claude Code")
            } footer: {
                Text("Valgono subito, senza riavviare Claude Code. I messaggi non vengono copiati né salvati altrove.")
            }

            Section {
                Picker("Inizio", selection: $model.settings.workHours.startHour) {
                    ForEach(0..<24, id: \.self) { Text("\($0):00").tag($0) }
                }
                Picker("Fine", selection: $model.settings.workHours.endHour) {
                    ForEach(1..<25, id: \.self) { Text("\($0):00").tag($0) }
                }
                Toggle("Lavoro anche il sabato", isOn: $model.settings.workHours.includesSaturday)
                Toggle("Conta i tempi di risposta solo in orario di lavoro", isOn: $model.settings.workTimeOnly)
            } header: {
                Text("Orario di lavoro")
            } footer: {
                Text("Serve per i messaggi \"fuori orario\". Se conti solo l'orario di lavoro, un messaggio arrivato venerdì sera e risposto lunedì alle 9 vale come risposta immediata.")
            }

            Section("Cose in sospeso") {
                LabeledContent("Chat ignorate", value: "\(model.settings.dismissedPending.count)")
                Button("Ripristina le chat ignorate") { Task { await model.restoreDismissed() } }
                    .disabled(model.settings.dismissedPending.isEmpty)
            }

            Section {
                Button("Rifai la configurazione guidata") { model.restartOnboarding() }
            }
        }
        .formStyle(.grouped)
        .frame(width: 520)
        .frame(minHeight: 640)
        .onChange(of: model.settings) { old, new in
            model.persist()
            if old.workHours != new.workHours || old.workTimeOnly != new.workTimeOnly {
                Task { await model.refresh() }
            }
        }
        .onAppear { model.hasDiskAccess = DatabaseLocator.hasFullDiskAccess }
    }
}
