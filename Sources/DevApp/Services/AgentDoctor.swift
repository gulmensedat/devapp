import Foundation

/// Claude Code ve Codex'in kurulu, oturum açılmış ve kullanılıyor olduğunu doğrular.
///
/// - Kurulum: kullanıcının giriş kabuğunda (`$SHELL -ilc`) `command -v` ve `--version`; böylece
///   nvm / Homebrew / ~/.local/bin gibi .zshrc'de tanımlı PATH'ler de görülür.
/// - Oturum: Claude için Anahtar Zinciri'ndeki "Claude Code-credentials" kaydının varlığı (şifre
///   okunmaz, izin istemez) ya da `~/.claude/.credentials.json`; Codex için `~/.codex/auth.json`.
/// - Etkinlik: kullanım kayıtlarındaki son zaman (UsageService'ten).
enum AgentKind: String, CaseIterable, Identifiable, Sendable {
    case claude, codex
    var id: String { rawValue }

    var title: String { self == .claude ? "Claude Code" : "Codex" }
    var sessionKind: SessionKind { self == .claude ? .claude : .codex }

    /// Ayarlardaki komutun ilk kelimesi (ör. "claude --model opus" → "claude")
    var executable: String {
        let cmd = self == .claude ? AppSettings.claudeCommand : AppSettings.codexCommand
        return cmd.split(separator: " ").first.map(String.init) ?? rawValue
    }

    var installCommand: String {
        self == .claude ? "npm install -g @anthropic-ai/claude-code" : "npm install -g @openai/codex"
    }

    /// Oturum açmak için çalıştırılacak komut (Claude ilk açılışta giriş ister; Codex'in ayrı komutu var)
    var loginCommand: String {
        self == .claude ? executable : "\(executable) login"
    }

    var docsURL: URL {
        URL(string: self == .claude
            ? "https://docs.anthropic.com/en/docs/claude-code/setup"
            : "https://github.com/openai/codex")!
    }
}

struct AgentHealth: Equatable, Sendable {
    enum Install: Equatable, Sendable {
        case checking
        case missing
        case found(path: String, version: String?)
    }

    enum Auth: Equatable, Sendable {
        case checking
        /// detail: hesap e-postası ya da giriş türü (ör. "API anahtarı")
        case signedIn(detail: String?)
        case signedOut
        /// Giriş bilgisi bulunamadı ama son günlerde kullanım kaydı var (ör. başka bir anahtar deposu)
        case unverified
    }

    var install: Install = .checking
    var auth: Auth = .checking
    var lastActivity: Date?
    var checkedAt: Date?

    var isChecking: Bool { install == .checking || auth == .checking }

    var isInstalled: Bool {
        if case .found = install { return true }
        return false
    }

    var isSignedIn: Bool {
        switch auth {
        case .signedIn, .unverified: return true
        default: return false
        }
    }

    var isReady: Bool { isInstalled && isSignedIn }
}

enum AgentDoctor {
    /// Tüm denetimler; ana iş parçacığını bloklamamak için arka planda çalışır.
    static func check(_ agent: AgentKind, lastActivity: Date?) async -> AgentHealth {
        let exe = agent.executable
        let shell = AppSettings.shellPath
        return await Task.detached(priority: .utility) {
            var h = AgentHealth()
            h.install = AgentDoctor.installStatus(executable: exe, shell: shell)
            h.auth = AgentDoctor.authStatus(agent, lastActivity: lastActivity)
            h.lastActivity = lastActivity
            h.checkedAt = Date()
            return h
        }.value
    }

    // MARK: Kurulum

    private static func installStatus(executable: String, shell: String) -> AgentHealth.Install {
        let q = executable.shellQuoted
        // Etkileşimli kabuk istem/uyarı basabilir; işaretli satırları ayıkla.
        let script = """
        p=$(command -v \(q) 2>/dev/null); printf '__DEVAPP_PATH__%s\\n' "$p"; \
        if [ -n "$p" ]; then v=$(\(q) --version 2>/dev/null | head -n 1); printf '__DEVAPP_VER__%s\\n' "$v"; fi
        """
        guard let out = run(shell, ["-ilc", script], timeout: 12) else { return .missing }
        var path = "", version = ""
        for line in out.split(whereSeparator: \.isNewline) {
            if let r = line.range(of: "__DEVAPP_PATH__") { path = String(line[r.upperBound...]) }
            if let r = line.range(of: "__DEVAPP_VER__") { version = String(line[r.upperBound...]) }
        }
        path = path.trimmingCharacters(in: .whitespaces)
        guard !path.isEmpty else { return .missing }
        version = version.trimmingCharacters(in: .whitespaces)
        return .found(path: path.abbreviatingHome, version: version.isEmpty ? nil : version)
    }

    // MARK: Oturum

    private static func authStatus(_ agent: AgentKind, lastActivity: Date?) -> AgentHealth.Auth {
        let recent = lastActivity.map { Date().timeIntervalSince($0) < 7 * 86_400 } ?? false
        switch agent {
        case .claude:
            if let auth = claudeAuth() { return auth }
        case .codex:
            if let auth = codexAuth() { return auth }
        }
        return recent ? .unverified : .signedOut
    }

    private static var home: URL { FileManager.default.homeDirectoryForCurrentUser }

    private static func claudeAuth() -> AgentHealth.Auth? {
        let env = ProcessInfo.processInfo.environment
        if env["ANTHROPIC_API_KEY"]?.isEmpty == false { return .signedIn(detail: L("API anahtarı", "API key")) }

        var configDirs: [URL] = []
        if let dir = env["CLAUDE_CONFIG_DIR"], !dir.isEmpty {
            configDirs += dir.split(separator: ",").map { URL(fileURLWithPath: String($0).trimmingCharacters(in: .whitespaces)) }
        }
        configDirs.append(home.appendingPathComponent(".claude"))

        // Anahtar Zinciri kaydı var mı? (-w yok: şifre okunmaz, izin penceresi açılmaz)
        let keychain = run("/usr/bin/security", ["find-generic-password", "-s", "Claude Code-credentials"], timeout: 5) != nil
        let file = configDirs.contains { FileManager.default.fileExists(atPath: $0.appendingPathComponent(".credentials.json").path) }
        guard keychain || file else { return nil }
        return .signedIn(detail: claudeAccountEmail(configDirs: configDirs))
    }

    /// ~/.claude.json → oauthAccount.emailAddress (yalnızca Ayarlar'da gösterilir, hiçbir yere gönderilmez)
    private static func claudeAccountEmail(configDirs: [URL]) -> String? {
        let candidates = [home.appendingPathComponent(".claude.json")] + configDirs.map { $0.appendingPathComponent(".claude.json") }
        for url in candidates {
            guard let data = try? Data(contentsOf: url),
                  let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let account = obj["oauthAccount"] as? [String: Any] else { continue }
            if let email = account["emailAddress"] as? String, !email.isEmpty { return email }
        }
        return nil
    }

    private static func codexAuth() -> AgentHealth.Auth? {
        let env = ProcessInfo.processInfo.environment
        let dir = env["CODEX_HOME"].flatMap { $0.isEmpty ? nil : URL(fileURLWithPath: $0) }
            ?? home.appendingPathComponent(".codex")
        guard let data = try? Data(contentsOf: dir.appendingPathComponent("auth.json")),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            if env["OPENAI_API_KEY"]?.isEmpty == false { return .signedIn(detail: L("API anahtarı", "API key")) }
            return nil
        }
        if let tokens = obj["tokens"] as? [String: Any], !tokens.isEmpty {
            let email = (tokens["id_token"] as? String).flatMap(jwtEmail)
            return .signedIn(detail: email ?? "ChatGPT")
        }
        if let key = obj["OPENAI_API_KEY"] as? String, !key.isEmpty {
            return .signedIn(detail: L("API anahtarı", "API key"))
        }
        return nil
    }

    /// JWT gövdesindeki "email" alanı (imza doğrulanmaz; yalnızca gösterim için)
    private static func jwtEmail(_ jwt: String) -> String? {
        let parts = jwt.split(separator: ".")
        guard parts.count >= 2 else { return nil }
        var b64 = String(parts[1]).replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
        while b64.count % 4 != 0 { b64 += "=" }
        guard let data = Data(base64Encoded: b64),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        return obj["email"] as? String
    }

    // MARK: Süreç

    private final class Buffer: @unchecked Sendable { var data = Data() }

    /// Komutu çalıştırır; başarılıysa (ya da işaretli çıktı verdiyse) çıktıyı döndürür.
    /// Zaman aşımında süreci sonlandırır.
    private static func run(_ executable: String, _ args: [String], timeout: TimeInterval) -> String? {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: executable)
        p.arguments = args
        p.standardInput = FileHandle.nullDevice
        let pipe = Pipe()
        p.standardOutput = pipe
        p.standardError = FileHandle.nullDevice
        var env = ProcessInfo.processInfo.environment
        env["TERM"] = "dumb"
        p.environment = env

        let done = DispatchSemaphore(value: 0)
        p.terminationHandler = { _ in done.signal() }
        do { try p.run() } catch { return nil }

        // Çıktıyı ayrı okuyalım ki dolan boru süreci kilitlemesin
        let buffer = Buffer()
        let readDone = DispatchSemaphore(value: 0)
        let handle = pipe.fileHandleForReading
        DispatchQueue.global(qos: .utility).async {
            buffer.data = handle.readDataToEndOfFile()
            readDone.signal()
        }
        if done.wait(timeout: .now() + timeout) == .timedOut {
            p.terminate()
            _ = done.wait(timeout: .now() + 1)
        }
        _ = readDone.wait(timeout: .now() + 1)
        guard !p.isRunning, p.terminationReason == .exit else { return nil }
        let text = String(decoding: buffer.data, as: UTF8.self)
        if p.terminationStatus == 0 { return text }
        return text.contains("__DEVAPP_") ? text : nil
    }
}
