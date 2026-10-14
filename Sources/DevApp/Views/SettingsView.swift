import AppKit
import SwiftUI

struct SettingsView: View {
    @AppStorage(SettingsKey.claudeCommand) private var claudeCommand = "claude"
    @AppStorage(SettingsKey.codexCommand) private var codexCommand = "codex"
    @AppStorage(SettingsKey.shellPath) private var shellPath = ""
    @AppStorage(SettingsKey.fontSize) private var fontSize = 13.0
    @AppStorage(SettingsKey.optionAsMeta) private var optionAsMeta = false
    @AppStorage(SettingsKey.restoreSessions) private var restoreSessions = true
    @AppStorage(SettingsKey.resumeAgents) private var resumeAgents = false
    @AppStorage(SettingsKey.claudePlanUsage) private var claudePlanUsage = false

    var body: some View {
        Form {
            Section {
                TextField("Claude", text: $claudeCommand)
                TextField("Codex", text: $codexCommand)
            } header: {
                Text("Ajan komutları")
            } footer: {
                Text("Örn: claude --model opus · codex --full-auto. Yeni açılan oturumlarda geçerlidir.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Terminal") {
                TextField("Kabuk", text: $shellPath, prompt: Text(AppSettings.defaultShell))
                Stepper("Yazı boyutu: \(Int(fontSize))", value: $fontSize, in: 9...24)
                Toggle("Option tuşu Meta olarak çalışsın", isOn: $optionAsMeta)
                Text("Türkçe klavyede Option ile @, #, { gibi karakterler yazıldığından kapalı tutun.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Oturumlar") {
                Toggle("Açılışta oturumları geri yükle", isOn: $restoreSessions)
                Toggle("Geri yüklerken ajan konuşmasını sürdür", isOn: $resumeAgents)
                    .disabled(!restoreSessions)
                Text("claude --continue / codex resume --last ile açılır. Aynı klasörde birden fazla ajan varsa hepsi son konuşmayı açar; worktree kullanın.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Kullanım") {
                Toggle("Claude plan limitini göster (5 saat / haftalık %)", isOn: $claudePlanUsage)
                Text("Claude Code'un oturum anahtarı Anahtar Zinciri'nden okunur; ilk seferde macOS izin ister (\"Her Zaman İzin Ver\" seçin). Kapalıyken yalnızca yerel kayıtlardan token sayısı gösterilir. Codex limitleri ~/.codex kayıtlarından otomatik okunur.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .onChange(of: claudePlanUsage) { _, _ in AppStore.shared.refreshUsage() }

            Section("Veriler") {
                LabeledContent("Konum") {
                    Text(AppStore.shared.dataFolderURL.path.abbreviatingHome)
                        .font(.caption.monospaced())
                        .textSelection(.enabled)
                }
                Text("Projeler, komutlar, portlar ve açık oturumlar bu klasördeki state.json'a (ve yedeğine) her değişiklikte yazılır; bilgisayar yeniden başlasa da kalır.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Button("Finder'da Göster") {
                    NSWorkspace.shared.open(AppStore.shared.dataFolderURL)
                }
            }
        }
        .formStyle(.grouped)
        .frame(width: 500)
        .onChange(of: fontSize) { _, _ in applyAppearance() }
        .onChange(of: optionAsMeta) { _, _ in applyAppearance() }
    }

    private func applyAppearance() {
        AppStore.shared.sessions.forEach { $0.applyAppearance() }
    }
}
