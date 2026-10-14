import AppKit
import SwiftUI
import SwiftTerm

/// SwiftTerm terminal görünümü; çıktı ve zil (bell) olaylarını dışarı bildirir.
final class AgentTerminalView: LocalProcessTerminalView {
    var onOutput: (() -> Void)?
    var onBell: (() -> Void)?
    /// Yalnızca ihtiyaç olduğunda (ör. localhost adresi aranırken) ayarlanır.
    var onText: ((String) -> Void)?

    override func dataReceived(slice: ArraySlice<UInt8>) {
        super.dataReceived(slice: slice)
        onOutput?()
        if let onText { onText(String(decoding: slice, as: UTF8.self)) }
    }

    /// Bip sesi yerine oturumu "dikkat" durumuna alır (Claude/Codex beklerken zil çalar).
    override func bell(source: Terminal) {
        onBell?()
    }
}

enum TerminalTheme {
    static let background = NSColor(calibratedRed: 0.106, green: 0.110, blue: 0.122, alpha: 1)
    static let foreground = NSColor(calibratedWhite: 0.88, alpha: 1)
    static var backgroundColor: SwiftUI.Color { SwiftUI.Color(nsColor: background) }
}

/// Bir terminal oturumu: kendi PTY sürecine ve kalıcı NSView'ine sahiptir.
/// Görünüm yerleşimi değişse de (ızgara/odak) aynı NSView yeniden kullanılır, süreç ölmez.
@MainActor
@Observable
final class TerminalSession: Identifiable {
    let id: UUID
    let projectID: UUID
    var name: String
    let kind: SessionKind
    let customCommand: String?
    let directory: String
    let worktreeBranch: String?
    /// Proje komutu çalıştıran oturumlarda komutun id'si
    let commandID: UUID?

    /// Programın OSC ile bildirdiği başlık (Claude Code burada yaptığı işi yazar).
    var title: String = ""
    var branch: String?
    var status: SessionStatus = .starting
    var needsAttention = false
    var broadcastSelected = false
    /// Çıktıda görülen yerel adres (ör. http://localhost:3000)
    var url: String?
    /// Son birkaç çıktı satırı (pano kartlarındaki canlı önizleme), saniyede bir tazelenir
    var previewLines: [String] = []

    @ObservationIgnored let terminalView: AgentTerminalView
    @ObservationIgnored var onAttention: (() -> Void)?
    /// Yalnızca ilk başlatmada ajana verilecek görev.
    @ObservationIgnored var initialPrompt: String?
    /// Geri yüklemede önceki konuşmayı sürdür.
    @ObservationIgnored var resumeOnStart = false

    @ObservationIgnored private var lastOutput: Date = .distantPast
    @ObservationIgnored private var busySince: Date?
    @ObservationIgnored private var delegateProxy: SessionProcessDelegate?
    @ObservationIgnored private var started = false
    @ObservationIgnored private var userStopped = false
    @ObservationIgnored private var tail: [String] = [""]
    @ObservationIgnored private var tailDirty = false
    @ObservationIgnored private var pendingCR = false

    var lastOutputDate: Date { lastOutput }

    init(spec: SessionSpec) {
        id = spec.id
        projectID = spec.projectID
        name = spec.name
        kind = spec.kind
        customCommand = spec.command
        directory = spec.directory
        worktreeBranch = spec.worktreeBranch
        commandID = spec.commandID
        terminalView = AgentTerminalView(frame: NSRect(x: 0, y: 0, width: 640, height: 400))

        applyAppearance()
        terminalView.onOutput = { [weak self] in self?.noteOutput() }
        terminalView.onBell = { [weak self] in self?.raiseAttention() }
        terminalView.onText = { [weak self] text in self?.consumeText(text) }
        let proxy = SessionProcessDelegate(session: self)
        delegateProxy = proxy
        terminalView.processDelegate = proxy
    }

    var spec: SessionSpec {
        SessionSpec(id: id, projectID: projectID, name: name, kind: kind,
                    command: customCommand, directory: directory, worktreeBranch: worktreeBranch,
                    commandID: commandID)
    }

    var isRunning: Bool { status.isRunning }
    var isRunCommand: Bool { commandID != nil }

    func applyAppearance() {
        let size = CGFloat(AppSettings.fontSize)
        terminalView.font = NSFont.monospacedSystemFont(ofSize: size, weight: .regular)
        terminalView.nativeBackgroundColor = TerminalTheme.background
        terminalView.nativeForegroundColor = TerminalTheme.foreground
        terminalView.caretColor = .systemOrange
        terminalView.optionAsMetaKey = AppSettings.optionAsMeta
    }

    // MARK: Süreç

    func start() {
        guard !started else { return }
        started = true

        let shell = AppSettings.shellPath
        var command: String?
        if kind == .custom {
            command = customCommand?.nonEmpty
        } else if resumeOnStart, let resume = AppSettings.resumeCommand(for: kind) {
            command = resume
        } else if let base = AppSettings.baseCommand(for: kind) {
            command = base
            if let prompt = initialPrompt?.nonEmpty {
                command = base + " " + prompt.shellQuoted
            }
        }
        initialPrompt = nil

        var args = ["-l"]
        if isRunCommand, let command {
            // Proje komutu: bitince kabuğa düşme; çıktı ekranda kalır, ▶ ile yeniden başlatılır.
            args = ["-l", "-i", "-c", command]
        } else if let command {
            // Komut bittiğinde terminal kapanmasın: aynı klasörde etkileşimli kabuğa düş.
            args = ["-l", "-i", "-c", "\(command); exec \(shell.shellQuoted) -l"]
        }

        terminalView.startProcess(
            executable: shell,
            args: args,
            environment: Self.environment(sessionID: id),
            execName: nil,
            currentDirectory: directory
        )
    }

    func terminate() {
        terminalView.processDelegate = nil
        terminalView.onOutput = nil
        terminalView.onBell = nil
        if terminalView.process?.running == true {
            terminalView.terminate()
        }
    }

    /// Önce Ctrl-C ile nazikçe durdurur, 3 sn içinde kapanmazsa süreci sonlandırır.
    func stop() {
        guard isRunning else { return }
        userStopped = true
        terminalView.send(txt: "\u{03}")
        Task { [weak self] in
            try? await Task.sleep(for: .seconds(3))
            guard let self, self.isRunning, self.terminalView.process?.running == true else { return }
            self.terminalView.terminate()
        }
    }

    /// Terminale klavyeden yazılmış gibi metin gönderir.
    func send(_ text: String) {
        guard isRunning else { return }
        terminalView.send(txt: text)
    }

    func makeKeyboardFocus() {
        terminalView.window?.makeFirstResponder(terminalView)
    }

    // MARK: Durum takibi

    private func noteOutput() {
        let now = Date()
        if busySince == nil { busySince = now }
        lastOutput = now
        if status == .starting { status = .busy }
    }

    func raiseAttention() {
        guard !needsAttention else { return }
        needsAttention = true
        onAttention?()
    }

    /// Store'daki zamanlayıcı her saniye çağırır.
    func refresh(now: Date, userIsWatching: Bool) {
        if tailDirty {
            tailDirty = false
            let lines = tail.map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
            let last = Array(lines.suffix(5))
            if last != previewLines { previewLines = last }
        }
        guard isRunning else { return }
        if isRunCommand {
            // Dev server vb.: çıktı patlamalarında "dikkat" üretme, sadece ayakta olduğunu göster
            if status != .running { status = .running }
            return
        }
        guard status != .starting else { return }
        if now.timeIntervalSince(lastOutput) < 1.5 {
            if status != .busy { status = .busy }
        } else {
            if let since = busySince {
                // 4 saniyeden uzun süren bir iş bitti ve kullanıcı bakmıyorsa haber ver.
                if lastOutput.timeIntervalSince(since) > 4, !userIsWatching {
                    raiseAttention()
                }
                busySince = nil
            }
            if status != .idle { status = .idle }
        }
    }

    fileprivate func processExited(_ code: Int32?) {
        status = .exited(code)
        busySince = nil
        // Kullanıcı durdurduysa uyarma; komut kendi kendine kapandıysa (çöktü/bitti) haber ver
        if !userStopped { raiseAttention() }
    }

    fileprivate func directoryChanged(_ dir: String?) {
        guard var dir else { return }
        // OSC 7 genellikle "file://host/yol" biçiminde gelir
        if dir.hasPrefix("file://"), let url = URL(string: dir) { dir = url.path }
        let target = dir
        Task { [weak self] in
            let b = await Git.currentBranch(in: target)
            self?.branch = b
        }
    }

    private static let urlRegex = try? NSRegularExpression(
        pattern: #"https?://(?:localhost|127\.0\.0\.1|0\.0\.0\.0|\[::1\]|[A-Za-z0-9.-]+\.local):\d{2,5}[^\s\x1b\"'<>]*"#)

    private static let ansiRegex = try? NSRegularExpression(pattern: #"\x1b\[[0-9;?]*[A-Za-z]"#)
    /// CSI, OSC ve diğer kaçış dizileri
    private static let escapeRegex = try? NSRegularExpression(
        pattern: #"\x1b\[[0-9;?<>=!]*[ -/]*[@-~]|\x1b\][^\x07\x1b]*(?:\x07|\x1b\\)|\x1b[()][A-Za-z0-9]|\x1b[=>78DEHMNOZc]"#)

    private func consumeText(_ raw: String) {
        if isRunCommand, url == nil { scanForURL(raw) }
        appendTail(raw)
    }

    /// Ham çıktıdan okunabilir satırlar çıkarır (renk kodları ve \r ile yeniden çizimler temizlenir).
    private func appendTail(_ raw: String) {
        var text = raw
        if let re = Self.escapeRegex {
            text = re.stringByReplacingMatches(in: raw, range: NSRange(location: 0, length: (raw as NSString).length),
                                               withTemplate: "")
        }
        // Not: "\r\n" Swift'te tek Character'dır; bu yüzden unicode skalerleri üzerinde yürünür.
        var current = tail.removeLast()
        for scalar in text.unicodeScalars {
            switch scalar.value {
            case 0x0A: // \n
                tail.append(current)
                current = ""
                pendingCR = false
            case 0x0D: // \r — satır başına dön; sonraki yazı satırı ezer (ilerleme çubukları)
                pendingCR = true
            default:
                guard scalar.value >= 0x20 || scalar.value == 0x09 else { continue }
                if pendingCR {
                    current = ""
                    pendingCR = false
                }
                if current.unicodeScalars.count < 240 { current.unicodeScalars.append(scalar) }
            }
        }
        tail.append(current)
        if tail.count > 40 { tail.removeFirst(tail.count - 40) }
        tailDirty = true
    }

    private func scanForURL(_ raw: String) {
        guard url == nil, let regex = Self.urlRegex else { return }
        // Vite gibi araçlar portu renk kodlarıyla yazar: "localhost:\e[1m5173\e[22m"
        var text = raw
        if let ansi = Self.ansiRegex {
            text = ansi.stringByReplacingMatches(in: raw, range: NSRange(location: 0, length: (raw as NSString).length),
                                                 withTemplate: "")
        }
        let ns = text as NSString
        guard let m = regex.firstMatch(in: text, range: NSRange(location: 0, length: ns.length)) else { return }
        var found = ns.substring(with: m.range)
        while let last = found.last, ".,);".contains(last) { found.removeLast() }
        url = found.replacingOccurrences(of: "0.0.0.0", with: "localhost")
    }

    func refreshBranch() {
        let dir = directory
        Task { [weak self] in
            let b = await Git.currentBranch(in: dir)
            self?.branch = b
        }
    }

    private static func environment(sessionID: UUID) -> [String] {
        var env = ProcessInfo.processInfo.environment
        // Xcode'dan çalıştırıldığında sızan değişkenleri temizle
        for key in env.keys where key.hasPrefix("DYLD_") || key.hasPrefix("__XCODE") || key == "OS_ACTIVITY_DT_MODE" {
            env.removeValue(forKey: key)
        }
        env["TERM"] = "xterm-256color"
        env["COLORTERM"] = "truecolor"
        env["TERM_PROGRAM"] = "DevApp"
        env["DEVAPP_SESSION_ID"] = sessionID.uuidString
        if env["LANG"] == nil { env["LANG"] = "en_US.UTF-8" }
        if env["LC_CTYPE"] == nil { env["LC_CTYPE"] = "UTF-8" }
        return env.map { "\($0.key)=\($0.value)" }
    }
}

/// SwiftTerm süreç delegesi → oturuma köprü.
final class SessionProcessDelegate: LocalProcessTerminalViewDelegate {
    weak var session: TerminalSession?

    init(session: TerminalSession) {
        self.session = session
    }

    func sizeChanged(source: LocalProcessTerminalView, newCols: Int, newRows: Int) {}

    func setTerminalTitle(source: LocalProcessTerminalView, title: String) {
        MainActor.assumeIsolated {
            session?.title = title.trimmed
        }
    }

    func hostCurrentDirectoryUpdate(source: TerminalView, directory: String?) {
        MainActor.assumeIsolated {
            session?.directoryChanged(directory)
        }
    }

    func processTerminated(source: TerminalView, exitCode: Int32?) {
        MainActor.assumeIsolated {
            session?.processExited(exitCode)
        }
    }
}
