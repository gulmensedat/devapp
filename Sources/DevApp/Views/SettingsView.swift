import AppKit
import SwiftUI

/// Ayarlar penceresi: Genel · Ajanlar · Oturumlar · Widget · Veriler
struct SettingsView: View {
    @State private var tab: SettingsTab = .general

    var body: some View {
        TabView(selection: $tab) {
            GeneralSettings()
                .tabItem { Label(L("Genel", "General"), systemImage: "gearshape") }
                .tag(SettingsTab.general)
            AgentSettings()
                .tabItem { Label(L("Ajanlar", "Agents"), systemImage: "sparkles") }
                .tag(SettingsTab.agents)
            SessionSettings()
                .tabItem { Label(L("Oturumlar", "Sessions"), systemImage: "rectangle.stack") }
                .tag(SettingsTab.sessions)
            WidgetSettings()
                .tabItem { Label(L("Widget", "Widgets"), systemImage: "square.grid.2x2") }
                .tag(SettingsTab.widget)
            DataSettings()
                .tabItem { Label(L("Veriler", "Data"), systemImage: "externaldrive") }
                .tag(SettingsTab.data)
        }
        .frame(width: 640)
    }
}

enum SettingsTab: Hashable {
    case general, agents, sessions, widget, data
}

/// Ayar sekmelerindeki açıklama satırı
private struct Caption: View {
    let text: String
    init(_ text: String) { self.text = text }

    var body: some View {
        Text(verbatim: text)
            .font(.caption)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
    }
}

// MARK: - Genel

private struct GeneralSettings: View {
    @AppStorage(SettingsKey.shellPath) private var shellPath = ""
    @AppStorage(SettingsKey.fontSize) private var fontSize = 13.0
    @AppStorage(SettingsKey.optionAsMeta) private var optionAsMeta = false

    private var language: Binding<AppLanguage> {
        Binding(get: { LanguageStore.shared.language },
                set: { AppStore.shared.setLanguage($0) })
    }

    var body: some View {
        Form {
            Section {
                Picker(L("Arayüz dili", "Language"), selection: language) {
                    ForEach(AppLanguage.allCases) { Text(verbatim: $0.title).tag($0) }
                }
                .pickerStyle(.segmented)
                Caption(L("Sistem seçeneği Mac'in dilini izler. Pencereler, Dock menüsü ve widget'lar hemen değişir; menü çubuğundaki bazı başlıklar uygulama yeniden açılınca güncellenir.",
                          "System follows your Mac's language. Windows, the Dock menu and widgets switch right away; some menu bar titles update after DevApp is reopened."))
            } header: {
                Text(L("Dil", "Language"))
            }

            Section {
                TextField(L("Kabuk", "Shell"), text: $shellPath, prompt: Text(verbatim: AppSettings.defaultShell))
                LabeledContent(L("Yazı boyutu", "Font size")) {
                    HStack(spacing: 10) {
                        Text(verbatim: "\(Int(fontSize)) pt")
                            .font(.system(size: 12).monospacedDigit())
                            .foregroundStyle(.secondary)
                        Stepper("", value: $fontSize, in: 9...24).labelsHidden()
                    }
                }
                Text(verbatim: "~/projects $ npm run dev")
                    .font(.system(size: fontSize, design: .monospaced))
                    .foregroundStyle(Color(hex: 0xE9E9EC))
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Color(hex: 0x0E0F11)))
                Toggle(L("Option tuşu Meta olarak çalışsın", "Use Option as Meta key"), isOn: $optionAsMeta)
                Caption(L("Türkçe klavyede Option ile @, #, { gibi karakterler yazıldığından kapalı tutun.",
                          "Keep this off if you type characters such as @, # or { with Option on your keyboard."))
            } header: {
                Text(verbatim: "Terminal")
            }
        }
        .formStyle(.grouped)
        .frame(height: 440)
        .onChange(of: fontSize) { _, _ in applyAppearance() }
        .onChange(of: optionAsMeta) { _, _ in applyAppearance() }
    }

    private func applyAppearance() {
        AppStore.shared.sessions.forEach { $0.applyAppearance() }
    }
}

// MARK: - Ajanlar

private struct AgentSettings: View {
    @AppStorage(SettingsKey.claudeCommand) private var claudeCommand = "claude"
    @AppStorage(SettingsKey.codexCommand) private var codexCommand = "codex"
    @AppStorage(SettingsKey.claudePlanUsage) private var claudePlanUsage = false

    var body: some View {
        Form {
            AgentSection(agent: .claude, command: $claudeCommand)
            AgentSection(agent: .codex, command: $codexCommand)

            Section {
                Toggle(L("Claude plan limitini göster (5 saat / haftalık %)", "Show Claude plan limits (5-hour / weekly %)"),
                       isOn: $claudePlanUsage)
                Caption(L("Claude Code'un oturum anahtarı Anahtar Zinciri'nden okunur; ilk seferde macOS izin ister (\"Her Zaman İzin Ver\" seçin). Kapalıyken yalnızca yerel kayıtlardan token sayısı gösterilir. Codex limitleri ~/.codex kayıtlarından otomatik okunur.",
                          "DevApp reads Claude Code's sign-in from the Keychain; macOS asks once (choose \"Always Allow\"). When off, only token counts from local logs are shown. Codex limits are read from ~/.codex logs automatically."))
            } header: {
                Text(L("Kullanım", "Usage"))
            }
            .onChange(of: claudePlanUsage) { _, _ in AppStore.shared.refreshUsage() }
        }
        .formStyle(.grouped)
        .frame(height: 660)
        .onAppear { AppStore.shared.checkAgents() }
    }
}

private struct AgentSection: View {
    let agent: AgentKind
    @Binding var command: String
    @State private var copied = false

    private var health: AgentHealth? { AppStore.shared.agentHealth[agent] }

    var body: some View {
        Section {
            LabeledContent(L("Kurulum", "Installed")) { installValue }
            LabeledContent(L("Oturum", "Signed in")) { authValue }
            LabeledContent(L("Son kullanım", "Last used")) {
                Text(verbatim: lastUsed).foregroundStyle(.secondary)
            }
            TextField(L("Komut", "Command"), text: $command, prompt: Text(verbatim: agent.rawValue))
                .onSubmit { AppStore.shared.checkAgents() }
            actions
        } header: {
            HStack(spacing: 8) {
                AgentLogo(agent: agent, size: 22)
                Text(verbatim: agent.title).font(.headline)
                Spacer()
                AgentStatusBadge(health: health)
            }
        } footer: {
            if agent == .claude {
                Caption(L("Örn: claude --model opus. Yeni açılan oturumlarda geçerlidir.",
                          "E.g. claude --model opus. Applies to new sessions."))
            } else {
                Caption(L("Örn: codex --full-auto. Yeni açılan oturumlarda geçerlidir.",
                          "E.g. codex --full-auto. Applies to new sessions."))
            }
        }
    }

    @ViewBuilder private var installValue: some View {
        switch health?.install ?? .checking {
        case .checking:
            ProgressView().controlSize(.small)
        case .missing:
            Label(L("Bulunamadı", "Not found"), systemImage: "xmark.circle.fill")
                .foregroundStyle(.red)
        case .found(let path, let version):
            VStack(alignment: .trailing, spacing: 2) {
                Text(verbatim: version ?? L("kurulu", "installed"))
                Text(verbatim: path)
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
            }
        }
    }

    @ViewBuilder private var authValue: some View {
        switch health?.auth ?? .checking {
        case .checking:
            ProgressView().controlSize(.small)
        case .signedIn(let detail):
            Label {
                Text(verbatim: detail ?? L("Açık", "Yes"))
            } icon: {
                Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
            }
        case .unverified:
            Label {
                Text(L("Doğrulanamadı, ancak kullanılıyor", "Couldn't verify, but in use"))
            } icon: {
                Image(systemName: "questionmark.circle.fill").foregroundStyle(.orange)
            }
            .help(L("Giriş bilgisi bilinen yerlerde yok, fakat son 7 günde kullanım kaydı var.",
                    "No sign-in found in the usual places, but there is usage in the last 7 days."))
        case .signedOut:
            Label(L("Oturum açılmamış", "Not signed in"), systemImage: "xmark.circle.fill")
                .foregroundStyle(.red)
        }
    }

    private var lastUsed: String {
        guard let last = health?.lastActivity else { return L("kayıt yok", "no activity") }
        return last.formatted(.relative(presentation: .named).locale(Locale(identifier: L("tr_TR", "en_US"))))
    }

    @ViewBuilder private var actions: some View {
        HStack(spacing: 8) {
            if let health, !health.isChecking {
                if !health.isInstalled {
                    Button(L("Kur", "Install")) {
                        AppStore.shared.runAgentSetup(agent.installCommand, title: L("\(agent.title) kurulumu", "Install \(agent.title)"))
                    }
                    .buttonStyle(.borderedProminent)
                    .help(agent.installCommand)
                    Button(copied ? L("Kopyalandı", "Copied") : L("Kurulum Komutunu Kopyala", "Copy Install Command")) {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(agent.installCommand, forType: .string)
                        copied = true
                    }
                } else if !health.isSignedIn {
                    Button(L("Oturum Aç", "Sign In")) {
                        AppStore.shared.runAgentSetup(agent.loginCommand, title: L("\(agent.title) girişi", "\(agent.title) sign-in"))
                    }
                    .buttonStyle(.borderedProminent)
                    .help(agent.loginCommand)
                }
            }
            Button(L("Yeniden Denetle", "Check Again")) { AppStore.shared.checkAgents() }
                .disabled(health?.isChecking ?? false)
            Spacer()
            Link(L("Belgeler", "Docs"), destination: agent.docsURL)
                .font(.callout)
        }
    }
}

private struct AgentStatusBadge: View {
    let health: AgentHealth?

    var body: some View {
        let s = state
        HStack(spacing: 5) {
            Circle().fill(s.color).frame(width: 7, height: 7)
            Text(verbatim: s.text).font(.system(size: 11, weight: .semibold))
        }
        .foregroundStyle(s.color)
        .padding(.horizontal, 9)
        .frame(height: 22)
        .background(Capsule().fill(s.color.opacity(0.14)))
    }

    private var state: (text: String, color: Color) {
        guard let health, !health.isChecking else { return (L("Denetleniyor…", "Checking…"), .secondary) }
        if !health.isInstalled { return (L("Kurulu değil", "Not installed"), .red) }
        if !health.isSignedIn { return (L("Oturum açılmamış", "Not signed in"), .orange) }
        return (L("Bağlı", "Connected"), .green)
    }
}

// MARK: - Oturumlar

private struct SessionSettings: View {
    @AppStorage(SettingsKey.restoreSessions) private var restoreSessions = true
    @AppStorage(SettingsKey.resumeAgents) private var resumeAgents = false

    var body: some View {
        Form {
            Section {
                Toggle(L("Açılışta oturumları geri yükle", "Restore sessions at launch"), isOn: $restoreSessions)
                Toggle(L("Geri yüklerken ajan konuşmasını sürdür", "Resume agent conversations when restoring"), isOn: $resumeAgents)
                    .disabled(!restoreSessions)
                Caption(L("claude --continue / codex resume --last ile açılır. Aynı klasörde birden fazla ajan varsa hepsi son konuşmayı açar; worktree kullanın.",
                          "Uses claude --continue / codex resume --last. If several agents share a folder they all open the latest conversation, so use worktrees."))
            } header: {
                Text(L("Geri yükleme", "Restore"))
            }
        }
        .formStyle(.grouped)
        .frame(height: 240)
    }
}

// MARK: - Widget

private struct WidgetSettings: View {
    var body: some View {
        Form {
            Section {
                WidgetStatusView()
            } header: {
                Text(L("Masaüstü widget'ları", "Desktop widgets"))
            } footer: {
                Caption(L("Masaüstüne sağ tık › Widget'ları Düzenle › DevApp. Widget'lar yalnızca ./scripts/xcode.sh build ile kurulan sürümde çalışır.",
                          "Right-click the desktop › Edit Widgets › DevApp. Widgets only work in the build installed with ./scripts/xcode.sh build."))
            }
        }
        .formStyle(.grouped)
        .frame(height: 300)
    }
}

struct WidgetStatusView: View {
    private var store: AppStore { AppStore.shared }

    var body: some View {
        if let error = store.widgetWriteError {
            Label(error, systemImage: "exclamationmark.triangle")
                .foregroundStyle(.orange)
                .font(.callout)
        } else if let last = store.widgetLastWrite {
            Label {
                Text(verbatim: L("Veri yazılıyor · son: ", "Writing data · last: ") + last.formatted(date: .omitted, time: .standard))
            } icon: {
                Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
            }
            .font(.callout)
        } else {
            Text(L("Henüz veri yazılmadı", "No data written yet")).foregroundStyle(.secondary)
        }
        if let dir = SharedStore.containerURL {
            LabeledContent(L("Klasör", "Folder")) {
                Text(verbatim: dir.path.abbreviatingHome)
                    .font(.caption.monospaced())
                    .textSelection(.enabled)
            }
        }
        Button(L("Widget'ları Şimdi Yenile", "Refresh Widgets Now")) {
            store.refreshUsage()
            store.publishWidget(force: true)
        }
    }
}

// MARK: - Veriler

private struct DataSettings: View {
    var body: some View {
        Form {
            Section {
                LabeledContent(L("Konum", "Location")) {
                    Text(verbatim: AppStore.shared.dataFolderURL.path.abbreviatingHome)
                        .font(.caption.monospaced())
                        .textSelection(.enabled)
                }
                Caption(L("Projeler, komutlar, portlar ve açık oturumlar bu klasördeki state.json'a (ve yedeğine) her değişiklikte yazılır; bilgisayar yeniden başlasa da kalır.",
                          "Projects, commands, ports and open sessions are written to state.json (plus a backup) in this folder on every change, so they survive a restart."))
                Button(L("Finder'da Göster", "Show in Finder")) {
                    NSWorkspace.shared.open(AppStore.shared.dataFolderURL)
                }
            } header: {
                Text(L("Uygulama verisi", "App data"))
            }
        }
        .formStyle(.grouped)
        .frame(height: 240)
    }
}
