import AppKit
import SwiftUI
import WidgetKit
import UniformTypeIdentifiers

/// Uygulamanın tek durum kaynağı: projeler, terminal oturumları, yerleşim, odak.
@MainActor
@Observable
final class AppStore {
    static let shared = AppStore()

    var projects: [Project] = []
    var sessions: [TerminalSession] = []

    var selection: SidebarItem? = .all
    /// nil = tüm projelerin terminalleri
    var filterProjectID: UUID?
    var focusedSessionID: UUID?
    var layout: LayoutMode = .grid
    /// 0 = otomatik
    var gridColumns: Int = 0

    var showBroadcast = false
    var broadcastText = ""
    var newSessionRequest: NewSessionRequest?
    var commandsEditRequest: CommandsEditRequest?
    /// Ana alanda gösterilen ekran (pano / tüm terminaller / proje)
    var screen: Screen = .dashboard
    var dashboardFilter: DashboardFilter = .all
    var searchText = ""
    var projectBranches: [UUID: String] = [:]
    /// Projelerin logoları (projeden otomatik bulunan ya da kullanıcının seçtiği)
    var projectIcons: [UUID: NSImage] = [:]
    @ObservationIgnored private var iconSources: [UUID: String] = [:]
    @ObservationIgnored private var widgetIconsWritten: [UUID: String] = [:]
    /// Claude / Codex kullanım özeti (dakikada bir tazelenir)
    var claudeUsage: ProviderUsage?
    var codexUsage: ProviderUsage?
    /// Claude Code / Codex kurulum ve oturum durumu (Ayarlar › Ajanlar)
    var agentHealth: [AgentKind: AgentHealth] = [:]
    @ObservationIgnored private var agentCheckRunning = false
    @ObservationIgnored private var lastPublished: WidgetSnapshot?
    /// Widget verisi yazma durumu (Ayarlar'da gösterilir)
    var widgetWriteError: String?
    var widgetLastWrite: Date?
    @ObservationIgnored private var lastWidgetReload: Date = .distantPast
    /// Şu an dinlenen (açık) yerel portlar — proje komutlarının portları için izlenir
    var listeningPorts: Set<Int> = []
    var errorMessage: String?
    /// Arttığında odaktaki terminal klavye odağını alır.
    var focusToken = 0

    @ObservationIgnored private var timer: Timer?
    @ObservationIgnored private var mouseMonitor: Any?
    @ObservationIgnored private var tickCount = 0

    private init() {
        load()
        startTimer()
        installMouseMonitor()
    }

    // MARK: Türetilmiş değerler

    var visibleSessions: [TerminalSession] {
        guard let pid = filterProjectID else { return sessions }
        return sessions.filter { $0.projectID == pid }
    }

    var focusedSession: TerminalSession? {
        guard let id = focusedSessionID else { return nil }
        return sessions.first { $0.id == id }
    }

    func session(_ id: UUID) -> TerminalSession? { sessions.first { $0.id == id } }
    func project(_ id: UUID) -> Project? { projects.first { $0.id == id } }
    func sessions(in projectID: UUID) -> [TerminalSession] { sessions.filter { $0.projectID == projectID } }

    /// Yeni oturumların ve "Aç" komutlarının hedef projesi.
    var currentProject: Project? {
        if let pid = filterProjectID, let p = project(pid) { return p }
        if let s = focusedSession, let p = project(s.projectID) { return p }
        return projects.first
    }

    /// "Xcode'da aç" vb. için klasör: odaktaki terminalin klasörü (worktree olabilir) ya da proje.
    var targetPath: String? {
        if let s = focusedSession, visibleSessions.contains(where: { $0 === s }) { return s.directory }
        return currentProject?.path
    }

    var attentionCount: Int { sessions.filter(\.needsAttention).count }
    var busyCount: Int { sessions.filter { $0.status == .busy }.count }

    var broadcastTargets: [TerminalSession] {
        visibleSessions.filter { $0.broadcastSelected && $0.isRunning }
    }

    func effectiveColumns(for count: Int) -> Int {
        if gridColumns > 0 { return min(gridColumns, max(count, 1)) }
        switch count {
        case 0, 1: return 1
        case 2...4: return 2
        case 5...9: return 3
        default: return 4
        }
    }

    // MARK: Projeler

    func addProjectsViaPanel() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = true
        panel.prompt = L("Ekle", "Add")
        panel.message = L("Projeye ait klasörleri seçin", "Choose project folders")
        guard panel.runModal() == .OK else { return }
        addProjects(panel.urls)
    }

    func addProjects(_ urls: [URL]) {
        var last: Project?
        for url in urls {
            var isDir: ObjCBool = false
            guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir), isDir.boolValue else { continue }
            if let existing = projects.first(where: { $0.path == url.path }) {
                last = existing
                continue
            }
            // Çalıştırma komutlarını otomatik bul (package.json, Makefile, compose…)
            let p = Project(name: url.lastPathComponent, path: url.path,
                            commands: CommandDetector.detect(in: url.path))
            projects.append(p)
            last = p
        }
        if let last { selection = .project(last.id) }
        save()
        refreshBranches()
        refreshIcons()
    }

    func removeProject(_ p: Project) {
        let related = sessions(in: p.id)
        if related.contains(where: \.isRunning) {
            guard confirm(L("\"\(p.name)\" kaldırılsın mı?", "Remove \"\(p.name)\"?"),
                          L("Bu projedeki \(related.count) terminal kapatılacak. Klasördeki dosyalara dokunulmaz.", "\(related.count) terminal(s) in this project will be closed. Files in the folder are not touched."),
                          action: L("Kaldır", "Remove")) else { return }
        }
        related.forEach { $0.terminate() }
        sessions.removeAll { $0.projectID == p.id }
        projects.removeAll { $0.id == p.id }
        if filterProjectID == p.id || screen == .project(p.id) { openDashboard() }
        if let f = focusedSessionID, session(f) == nil { focusedSessionID = visibleSessions.first?.id }
        save()
    }

    // MARK: Proje komutları (tek tıkla çalıştır)

    func commandSession(_ commandID: UUID) -> TerminalSession? {
        sessions.first { $0.commandID == commandID }
    }

    func isCommandRunning(_ commandID: UUID) -> Bool {
        commandSession(commandID)?.isRunning == true
    }

    func projectHasRunningCommands(_ p: Project) -> Bool {
        p.commands.contains { isCommandRunning($0.id) }
    }

    /// Komutu çalıştırır; zaten çalışıyorsa sadece odaklar, kapanmışsa aynı kutuda yeniden başlatır.
    func run(_ cmd: RunCommand, in project: Project, focusIt: Bool = true, skipPortCheck: Bool = false) {
        let existing = commandSession(cmd.id)
        if let existing, existing.isRunning {
            if focusIt { revealAndFocus(existing) }
            return
        }
        // Port başka bir süreç tarafından tutuluyorsa sor
        if !skipPortCheck, let port = cmd.effectivePort, PortMonitor.isListening(port) {
            Task {
                if await self.resolvePortConflict(port, commandName: cmd.name) {
                    self.run(cmd, in: project, focusIt: focusIt, skipPortCheck: true)
                }
            }
            return
        }
        let spec = SessionSpec(id: existing?.id ?? UUID(), projectID: project.id, name: cmd.name, kind: .custom,
                               command: cmd.launchCommand, directory: cmd.directory(in: project), commandID: cmd.id)
        let index = existing.flatMap { e in sessions.firstIndex { $0 === e } }
        existing?.terminate()
        let s = makeSession(spec, at: index)
        if focusIt { revealAndFocus(s) }
        save()
    }

    /// Kullanıcıya portu tutan süreci gösterir; true dönerse başlatılır.
    private func resolvePortConflict(_ port: Int, commandName: String) async -> Bool {
        let owner = await PortMonitor.owner(of: port)
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = L("Port \(port) zaten kullanımda", "Port \(port) is already in use")
        if let owner {
            alert.informativeText = L("\(owner.name) (pid \(owner.pid)) bu portu dinliyor. \"\(commandName)\" bu haliyle başlatılırsa hata verebilir.", "\(owner.name) (pid \(owner.pid)) is listening on this port. \"\(commandName)\" may fail if started as is.")
            alert.addButton(withTitle: L("Süreci Kapat ve Başlat", "Stop Process and Start"))
        } else {
            alert.informativeText = L("Bu portu başka bir süreç dinliyor. \"\(commandName)\" bu haliyle başlatılırsa hata verebilir.", "Another process is listening on this port. \"\(commandName)\" may fail if started as is.")
        }
        alert.addButton(withTitle: L("Yine de Başlat", "Start Anyway"))
        alert.addButton(withTitle: L("Vazgeç", "Cancel"))
        let response = alert.runModal()

        if let owner {
            switch response {
            case .alertFirstButtonReturn:
                kill(owner.pid, SIGTERM)
                for _ in 0..<30 {
                    if !PortMonitor.isListening(port) { break }
                    try? await Task.sleep(for: .milliseconds(100))
                }
                return true
            case .alertSecondButtonReturn:
                return true
            default:
                return false
            }
        }
        return response == .alertFirstButtonReturn
    }

    /// Komutun portu dinleniyorsa gösterilecek adres.
    func liveURL(for session: TerminalSession) -> String? {
        if let url = session.url { return url }
        guard session.isRunning, let cid = session.commandID, let found = command(cid),
              let port = found.1.effectivePort, listeningPorts.contains(port) else { return nil }
        return "http://localhost:\(port)"
    }

    private func refreshPorts() {
        let ports = Set(projects.flatMap { $0.commands.compactMap(\.effectivePort) })
        guard !ports.isEmpty else {
            if !listeningPorts.isEmpty { listeningPorts = [] }
            return
        }
        Task {
            let open = await PortMonitor.listening(ports)
            if open != self.listeningPorts { self.listeningPorts = open }
        }
    }

    func stop(_ cmd: RunCommand) {
        commandSession(cmd.id)?.stop()
    }

    func toggle(_ cmd: RunCommand, in project: Project, focusIt: Bool = true) {
        if isCommandRunning(cmd.id) { stop(cmd) } else { run(cmd, in: project, focusIt: focusIt) }
    }

    /// "Projeyi Başlat": işaretli komutların hepsini açar ve projeyi gösterir.
    func startProject(_ p: Project, navigate: Bool = true) {
        let cmds = p.startAllCommands.isEmpty ? Array(p.commands.prefix(1)) : p.startAllCommands
        guard !cmds.isEmpty else {
            commandsEditRequest = CommandsEditRequest(projectID: p.id)
            return
        }
        for c in cmds { run(c, in: p, focusIt: false) }
        guard navigate else { return }
        setFilter(p.id)
        if let first = cmds.first.flatMap({ commandSession($0.id) }) {
            focus(first, takeKeyboard: false)
        }
    }

    func stopProject(_ p: Project) {
        sessions(in: p.id).filter { $0.isRunCommand && $0.isRunning }.forEach { $0.stop() }
    }

    func updateCommands(_ commands: [RunCommand], for projectID: UUID) {
        guard let i = projects.firstIndex(where: { $0.id == projectID }) else { return }
        projects[i].commands = commands
        save()
    }

    // MARK: Portlar

    /// Komutun portunu değiştirir (nil = projede bulunan porta dön). Çalışıyorsa yeni portla yeniden başlatır.
    func setPort(_ port: Int?, for commandID: UUID) {
        guard let pi = projects.firstIndex(where: { p in p.commands.contains { $0.id == commandID } }),
              let ci = projects[pi].commands.firstIndex(where: { $0.id == commandID }) else { return }
        var cmd = projects[pi].commands[ci]
        cmd.port = (port == nil || port == cmd.detectedPort) ? nil : port
        projects[pi].commands[ci] = cmd
        save()
        if let s = commandSession(commandID), s.isRunning {
            restart(s)
        }
    }

    /// Aynı portu kullanan diğer komutlar (tüm projelerde; portlar makine genelinde ortaktır)
    func portUsers(_ port: Int, excluding commandID: UUID) -> [(Project, RunCommand)] {
        var result: [(Project, RunCommand)] = []
        for p in projects {
            for c in p.commands where c.id != commandID && c.effectivePort == port {
                result.append((p, c))
            }
        }
        return result
    }

    func portConflict(for cmd: RunCommand) -> Bool {
        guard let port = cmd.effectivePort else { return false }
        return !portUsers(port, excluding: cmd.id).isEmpty
    }

    func conflictCount(in p: Project) -> Int {
        p.commands.filter { portConflict(for: $0) }.count
    }

    /// Kimsenin kullanmadığı ve şu an dinlenmeyen ilk port
    func suggestFreePort(after start: Int, excluding commandID: UUID? = nil) -> Int {
        let used = Set(projects.flatMap { $0.commands }.filter { $0.id != commandID }.compactMap(\.effectivePort))
        var candidate = max(1024, start + 1)
        while candidate < 65_000 {
            if !used.contains(candidate) && !PortMonitor.isListening(candidate) { return candidate }
            candidate += 1
        }
        return start
    }

    /// Projedeki çakışan portları (ilk kullanan hariç) boş portlara taşır
    func resolvePortConflicts(in p: Project) {
        guard let pi = projects.firstIndex(where: { $0.id == p.id }) else { return }
        var restarted: [UUID] = []
        for ci in projects[pi].commands.indices {
            let cmd = projects[pi].commands[ci]
            guard let port = cmd.effectivePort else { continue }
            // Bu komuttan önce gelen biri (bu projede ya da başka projede) aynı portu kullanıyorsa taşı
            let users = portUsers(port, excluding: cmd.id)
            guard !users.isEmpty else { continue }
            let earlierHere = projects[pi].commands[..<ci].contains { $0.effectivePort == port }
            let elsewhere = users.contains { $0.0.id != p.id }
            guard earlierHere || elsewhere else { continue }
            projects[pi].commands[ci].port = suggestFreePort(after: port, excluding: cmd.id)
            if isCommandRunning(cmd.id) { restarted.append(cmd.id) }
        }
        save()
        for id in restarted {
            if let s = commandSession(id) { restart(s) }
        }
    }

    func editCommands(_ p: Project) {
        commandsEditRequest = CommandsEditRequest(projectID: p.id)
    }

    func openURL(_ url: String) {
        guard let u = URL(string: url.hasPrefix("http") ? url : "http://\(url)") else { return }
        NSWorkspace.shared.open(u)
    }

    private func revealAndFocus(_ s: TerminalSession) {
        if let f = filterProjectID, f != s.projectID { setFilter(s.projectID) }
        focus(s, takeKeyboard: false)
    }

    // MARK: Oturumlar

    func requestNewSession(kind: SessionKind, projectID: UUID? = nil) {
        guard !projects.isEmpty else { addProjectsViaPanel(); return }
        newSessionRequest = NewSessionRequest(projectID: projectID ?? currentProject?.id, kind: kind)
    }

    /// Mevcut projede tek tıkla oturum aç.
    func quickNew(_ kind: SessionKind, projectID: UUID? = nil) {
        let explicit = projectID.flatMap { id in projects.first { $0.id == id } }
        guard let target = explicit ?? currentProject else {
            addProjectsViaPanel()
            return
        }
        Task { await createSessions(NewSessionDraft(projectID: target.id, kind: kind)) }
    }

    func createSessions(_ draft: NewSessionDraft) async {
        guard let pid = draft.projectID, let proj = self.project(pid) else { return }
        let count = max(1, draft.count)
        var created: [TerminalSession] = []

        for i in 0..<count {
            var dir = proj.path
            var wtBranch: String?
            if draft.useWorktree, let base = draft.branch.nonEmpty {
                let branch = count > 1 ? "\(base)-\(i + 1)" : base
                do {
                    dir = try await Git.addWorktree(repo: proj.path, branch: branch)
                    wtBranch = branch
                } catch {
                    errorMessage = L("Worktree oluşturulamadı (\(branch)):\n\(error.localizedDescription)", "Couldn’t create worktree (\(branch)):\n\(error.localizedDescription)")
                    break
                }
            }
            let baseName = draft.name.nonEmpty ?? defaultName(for: draft)
            let name = uniqueName(count > 1 ? "\(baseName) \(i + 1)" : baseName)
            let spec = SessionSpec(projectID: proj.id, name: name, kind: draft.kind,
                                   command: draft.kind == .custom ? draft.customCommand.nonEmpty : nil,
                                   directory: dir, worktreeBranch: wtBranch)
            let s = makeSession(spec, prompt: draft.prompt.nonEmpty)
            created.append(s)
        }

        if let first = created.first {
            if screen == .dashboard {
                setFilter(first.projectID)
            } else if let f = filterProjectID, f != first.projectID {
                setFilter(first.projectID)
            }
            focus(first)
        }
        save()
    }

    private func defaultName(for draft: NewSessionDraft) -> String {
        if let prompt = draft.prompt.nonEmpty {
            let words = prompt.split(separator: " ").prefix(4).joined(separator: " ")
            return words.count > 28 ? String(words.prefix(28)) + "…" : words
        }
        if draft.kind == .custom, let cmd = draft.customCommand.nonEmpty {
            return String(cmd.prefix(24))
        }
        return draft.kind.label
    }

    private func uniqueName(_ name: String) -> String {
        let names = Set(sessions.map(\.name))
        guard names.contains(name) else { return name }
        var n = 2
        while names.contains("\(name) (\(n))") { n += 1 }
        return "\(name) (\(n))"
    }

    @discardableResult
    private func makeSession(_ spec: SessionSpec, prompt: String? = nil, resume: Bool = false,
                             at index: Int? = nil) -> TerminalSession {
        let s = TerminalSession(spec: spec)
        s.initialPrompt = prompt
        s.resumeOnStart = resume
        s.onAttention = { [weak self, weak s] in
            guard let self, let s else { return }
            self.attentionRaised(s)
        }
        if let index, sessions.indices.contains(index) {
            sessions[index] = s
        } else {
            sessions.append(s)
        }
        s.start()
        s.refreshBranch()
        return s
    }

    func restart(_ s: TerminalSession) {
        guard let idx = sessions.firstIndex(where: { $0 === s }) else { return }
        // Proje komutu: güncel komut tanımıyla yeniden başlat
        if let cid = s.commandID, let found = command(cid) {
            s.terminate()
            run(found.1, in: found.0, focusIt: focusedSessionID == s.id)
            return
        }
        if s.isRunning, s.kind.isAgent {
            guard confirm(L("\"\(s.name)\" yeniden başlatılsın mı?", "Restart \"\(s.name)\"?"), L("Çalışan süreç sonlandırılıp aynı komut tekrar başlatılacak.", "The running process will be stopped and the same command started again."),
                          action: L("Yeniden Başlat", "Restart")) else { return }
        }
        s.terminate()
        makeSession(s.spec, at: idx)
        if focusedSessionID == s.id { focusToken += 1 }
    }

    func close(_ s: TerminalSession, confirmIfRunning: Bool = true) {
        if confirmIfRunning, s.isRunning, s.kind.isAgent {
            guard confirm(L("\"\(s.name)\" kapatılsın mı?", "Close \"\(s.name)\"?"), L("Bu oturumda çalışan süreç sonlandırılacak.", "The process running in this session will be terminated."),
                          action: L("Kapat", "Close")) else { return }
        }
        let visible = visibleSessions
        let pos = visible.firstIndex { $0 === s }
        s.terminate()
        sessions.removeAll { $0 === s }
        if focusedSessionID == s.id {
            let remaining = visibleSessions
            if let pos, !remaining.isEmpty {
                focus(remaining[min(pos, remaining.count - 1)])
            } else {
                focusedSessionID = remaining.first?.id
            }
        }
        save()
    }

    func rename(_ s: TerminalSession) {
        let alert = NSAlert()
        alert.messageText = L("Yeniden adlandır", "Rename")
        let field = NSTextField(string: s.name)
        field.frame = NSRect(x: 0, y: 0, width: 260, height: 24)
        alert.accessoryView = field
        alert.addButton(withTitle: L("Kaydet", "Save"))
        alert.addButton(withTitle: L("Vazgeç", "Cancel"))
        alert.window.initialFirstResponder = field
        guard alert.runModal() == .alertFirstButtonReturn, let name = field.stringValue.nonEmpty else { return }
        s.name = name
        save()
    }

    // MARK: Odak ve yerleşim

    func focus(_ s: TerminalSession, takeKeyboard: Bool = true) {
        // Panodayken bir terminale odaklanmak terminal ekranına götürür
        if screen == .dashboard { setFilter(filterProjectID) }
        focusedSessionID = s.id
        s.needsAttention = false
        if takeKeyboard { focusToken += 1 }
    }

    /// Ana alanda hangi projenin gösterileceğini değiştirir ve kenar çubuğu seçimini eşler.
    func setFilter(_ projectID: UUID?) {
        filterProjectID = projectID
        let item: SidebarItem = projectID.map { .project($0) } ?? .all
        if selection != item { selection = item }
        let target: Screen = projectID.map { .project($0) } ?? .terminals
        if screen != target { screen = target }
    }

    // MARK: Ekranlar

    func openDashboard() {
        filterProjectID = nil
        screen = .dashboard
    }

    func openTerminals() { setFilter(nil) }

    /// SwiftUI'nin pencere açma eylemi (ContentView ilk göründüğünde yakalanır)
    @ObservationIgnored var openMainWindowAction: (() -> Void)?

    /// Ana pencere kapalıysa açar, açıksa öne getirir.
    func showMainWindow() {
        if let window = NSApp.windows.first(where: { $0.identifier?.rawValue == "main" || $0.title == "DevApp" }),
           window.isVisible || window.isMiniaturized {
            if window.isMiniaturized { window.deminiaturize(nil) }
            window.makeKeyAndOrderFront(nil)
        } else {
            openMainWindowAction?()
        }
    }

    /// Oturumu kendi projesinin ekranında gösterir ve klavye odağını verir.
    func reveal(_ s: TerminalSession) {
        setFilter(s.projectID)
        focus(s)
    }

    func openProject(_ p: Project) {
        setFilter(p.id)
        if focusedSession?.projectID != p.id { focusedSessionID = sessions(in: p.id).first?.id }
    }

    enum ProjectState { case running, attention, crashed, idle }

    func state(of p: Project) -> ProjectState {
        let ss = sessions(in: p.id)
        if ss.contains(where: \.needsAttention) { return .attention }
        if runningCommandCount(p) > 0 || agentCount(p) > 0 { return .running }
        if crashedCommand(in: p) != nil { return .crashed }
        return .idle
    }

    func runningCommandCount(_ p: Project) -> Int {
        p.commands.filter { isCommandRunning($0.id) }.count
    }

    func agentCount(_ p: Project) -> Int {
        sessions(in: p.id).filter { $0.kind.isAgent && $0.isRunning }.count
    }

    /// Hatayla kapanmış (çıkış kodu ≠ 0) ilk proje komutu
    func crashedCommand(in p: Project) -> (command: RunCommand, code: Int32)? {
        for c in p.commands {
            guard let s = commandSession(c.id), case .exited(let exitCode) = s.status,
                  let code = exitCode, code != 0 else { continue }
            return (c, code)
        }
        return nil
    }

    /// Kart önizlemesi için en son çıktı veren oturum
    func previewSession(for p: Project) -> TerminalSession? {
        sessions(in: p.id).max { $0.lastOutputDate < $1.lastOutputDate }
    }

    var dashboardProjects: [Project] {
        let q = searchText.trimmed.lowercased()
        return projects.filter { p in
            let st = state(of: p)
            switch dashboardFilter {
            case .all: break
            case .running: if st != .running && st != .attention { return false }
            case .attention: if st != .attention { return false }
            case .stopped: if st == .running || st == .attention { return false }
            }
            guard !q.isEmpty else { return true }
            if p.name.lowercased().contains(q) || p.path.lowercased().contains(q) { return true }
            return p.commands.contains {
                $0.name.lowercased().contains(q) || $0.command.lowercased().contains(q)
                    || ($0.effectivePort.map { String($0).contains(q) } ?? false)
            }
        }
    }

    func count(for filter: DashboardFilter) -> Int {
        projects.filter { p in
            let st = state(of: p)
            switch filter {
            case .all: return true
            case .running: return st == .running || st == .attention
            case .attention: return st == .attention
            case .stopped: return st != .running && st != .attention
            }
        }.count
    }

    func refreshBranches() {
        for p in projects {
            let id = p.id, path = p.path
            Task {
                let b = await Git.currentBranch(in: path)
                if self.projectBranches[id] != b { self.projectBranches[id] = b }
            }
        }
    }

    // MARK: Kullanım ve widget

    func refreshUsage() {
        let includePlan = AppSettings.claudePlanUsage
        Task {
            let result = await UsageService.shared.snapshot(includeClaudePlan: includePlan)
            if self.claudeUsage != result.claude { self.claudeUsage = result.claude }
            if self.codexUsage != result.codex { self.codexUsage = result.codex }
            self.publishWidget()
            if self.agentHealth.isEmpty { self.checkAgents() }
        }
    }

    // MARK: Ajan bağlantısı

    /// Claude Code ve Codex kurulu mu, oturum açık mı? (arka planda; birkaç saniye sürebilir)
    func checkAgents() {
        guard !agentCheckRunning else { return }
        agentCheckRunning = true
        for agent in AgentKind.allCases where agentHealth[agent] == nil {
            agentHealth[agent] = AgentHealth()
        }
        let claudeActivity = claudeUsage?.lastActivity
        let codexActivity = codexUsage?.lastActivity
        Task {
            async let claude = AgentDoctor.check(.claude, lastActivity: claudeActivity)
            async let codex = AgentDoctor.check(.codex, lastActivity: codexActivity)
            let results = await (claude, codex)
            self.agentHealth[.claude] = results.0
            self.agentHealth[.codex] = results.1
            self.agentCheckRunning = false
        }
    }

    func health(_ agent: AgentKind) -> AgentHealth? { agentHealth[agent] }

    /// Kurulum / giriş komutunu DevApp içinde bir terminalde çalıştırır (proje yoksa panoya kopyalar).
    func runAgentSetup(_ command: String, title: String) {
        guard let target = currentProject ?? projects.first else {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(command, forType: .string)
            errorMessage = L("Henüz proje yok. Komut panoya kopyalandı; bir terminale yapıştırıp çalıştırın:\n\(command)",
                             "No projects yet. The command was copied to the clipboard; paste it into a terminal:\n\(command)")
            showMainWindow()
            return
        }
        let spec = SessionSpec(projectID: target.id, name: uniqueName(title), kind: .custom,
                               command: command, directory: NSHomeDirectory())
        let s = makeSession(spec)
        showMainWindow()
        setFilter(target.id)
        focus(s)
        save()
    }

    // MARK: Dil

    func setLanguage(_ language: AppLanguage) {
        LanguageStore.shared.update(language)
        refreshUsage()                 // kullanım notları yeni dilde gelsin
        publishWidget(force: true)     // widget da aynı dile geçsin
    }

    /// Masaüstü widget'ının okuduğu özet dosyasını yazar; değiştiyse widget'ı yeniler.
    func publishWidget(force: Bool = false) {
        let projectsSnap = projects.map { p -> ProjectSnapshot in
            let st: String
            switch state(of: p) {
            case .running: st = "running"
            case .attention: st = "attention"
            case .crashed: st = "crashed"
            case .idle: st = "idle"
            }
            let ports = p.commands.compactMap(\.effectivePort).filter { listeningPorts.contains($0) }
            return ProjectSnapshot(id: p.id, name: p.name, initials: p.initials, colorHex: p.accentHex,
                                   state: st, runningCommands: runningCommandCount(p),
                                   agents: agentCount(p), ports: Array(Set(ports)).sorted(),
                                   hasIcon: projectIcons[p.id] != nil)
        }
        let snap = WidgetSnapshot(updatedAt: Date(), projects: projectsSnap, attention: attentionCount,
                                  claude: claudeUsage, codex: codexUsage,
                                  language: LanguageStore.shared.resolvedCode)
        // updatedAt hariç değişmediyse yazma
        if !force, var previous = lastPublished {
            previous.updatedAt = snap.updatedAt
            if previous == snap { return }
        }
        lastPublished = snap
        if SharedStore.groupID != nil { writeWidgetIcons() }
        let error = SharedStore.write(snap)
        if widgetWriteError != error { widgetWriteError = error }
        if error == nil { widgetLastWrite = Date() } else { return }

        // Widget yenileme bütçesi sınırlı: en fazla dakikada bir, dikkat değişince hemen
        let attentionChanged = snap.attention != (lastPublishedAttention ?? -1)
        lastPublishedAttention = snap.attention
        if force || attentionChanged || Date().timeIntervalSince(lastWidgetReload) > 60 {
            lastWidgetReload = Date()
            WidgetCenter.shared.reloadAllTimelines()
        }
    }

    @ObservationIgnored private var lastPublishedAttention: Int?

    /// devapp://dashboard · devapp://terminals · devapp://attention · devapp://project/<id>
    func handleURL(_ url: URL) {
        guard url.scheme == "devapp" else { return }
        switch url.host {
        case "terminals": openTerminals()
        case "attention": focusNextAttention()
        case "project":
            if let id = UUID(uuidString: url.lastPathComponent), let p = project(id) { openProject(p) }
        default: openDashboard()
        }
    }

    // MARK: Proje logoları

    func refreshIcons(_ only: [Project]? = nil) {
        for p in only ?? projects {
            let id = p.id, root = p.path
            let custom = p.iconPath, disabled = p.iconDisabled ?? false
            Task {
                let path: String? = await Task.detached(priority: .utility) { () -> String? in
                    if disabled { return nil }
                    if let custom, FileManager.default.fileExists(atPath: custom) { return custom }
                    return ProjectIconFinder.find(in: root)
                }.value
                let image = path.flatMap { NSImage(contentsOfFile: $0) }
                self.iconSources[id] = path
                if self.projectIcons[id] !== image { self.projectIcons[id] = image }
                self.publishWidget(force: true)
            }
        }
    }

    func chooseIcon(for p: Project) {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.image, .icns]
        panel.allowsMultipleSelection = false
        panel.directoryURL = URL(fileURLWithPath: p.path)
        panel.message = L("\(p.name) için logo seçin", "Choose a logo for \(p.name)")
        guard panel.runModal() == .OK, let url = panel.url,
              let i = projects.firstIndex(where: { $0.id == p.id }) else { return }
        projects[i].iconPath = url.path
        projects[i].iconDisabled = false
        save()
        refreshIcons([projects[i]])
    }

    func autoIcon(for p: Project) {
        guard let i = projects.firstIndex(where: { $0.id == p.id }) else { return }
        projects[i].iconPath = nil
        projects[i].iconDisabled = false
        save()
        refreshIcons([projects[i]])
    }

    func removeIcon(for p: Project) {
        guard let i = projects.firstIndex(where: { $0.id == p.id }) else { return }
        projects[i].iconPath = nil
        projects[i].iconDisabled = true
        projectIcons[p.id] = nil
        save()
        publishWidget(force: true)
    }

    /// Widget'ın okuyabilmesi için logoların küçük kopyalarını App Group kabına yazar
    @ObservationIgnored private var agentIconsWritten = false

    private func writeWidgetIcons() {
        if !agentIconsWritten {
            agentIconsWritten = true
            AgentIcons.writeForWidget()
        }
        for (id, image) in projectIcons {
            let source = iconSources[id] ?? ""
            guard widgetIconsWritten[id] != source, let url = SharedStore.iconURL(for: id),
                  let data = ProjectIconFinder.pngData(from: image) else { continue }
            try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            if (try? data.write(to: url, options: .atomic)) != nil { widgetIconsWritten[id] = source }
        }
    }

    func setColor(_ index: Int?, for projectID: UUID) {
        guard let i = projects.firstIndex(where: { $0.id == projectID }) else { return }
        projects[i].colorIndex = index
        save()
    }

    func command(_ id: UUID) -> (Project, RunCommand)? {
        for p in projects {
            if let c = p.commands.first(where: { $0.id == id }) { return (p, c) }
        }
        return nil
    }

    /// Kenar çubuğu seçimi değişince çağrılır.
    func handleSelection(_ item: SidebarItem?) {
        switch item {
        case .all, .none:
            filterProjectID = nil
        case .project(let id):
            filterProjectID = id
            if focusedSession?.projectID != id { focusedSessionID = sessions(in: id).first?.id }
        case .session(let id):
            guard let s = session(id) else { return }
            if let f = filterProjectID, f != s.projectID { setFilter(s.projectID) }
            if focusedSessionID != id { focus(s) }
        case .command(let id):
            guard let s = commandSession(id) else { return }
            if let f = filterProjectID, f != s.projectID { setFilter(s.projectID) }
            if focusedSessionID != s.id { focus(s) }
        }
    }

    func toggleLayout() {
        layout = layout == .grid ? .focus : .grid
        if layout == .focus, focusedSession == nil, let first = visibleSessions.first { focus(first) }
        focusToken += 1
        save()
    }

    func toggleFocusLayout(on s: TerminalSession) {
        focus(s)
        toggleLayout()
    }

    func setGridColumns(_ n: Int) {
        gridColumns = n
        layout = .grid
        save()
    }

    func focusIndex(_ i: Int) {
        let v = visibleSessions
        guard v.indices.contains(i) else { return }
        focus(v[i])
    }

    func focusNext(_ delta: Int) {
        let v = visibleSessions
        guard !v.isEmpty else { return }
        let cur = v.firstIndex { $0.id == focusedSessionID } ?? -1
        let next = ((cur + delta) % v.count + v.count) % v.count
        focus(v[next])
    }

    /// Bir sonraki "dikkat" bekleyen terminale atla.
    func focusNextAttention() {
        if let s = sessions.first(where: \.needsAttention) {
            if let f = filterProjectID, f != s.projectID { setFilter(s.projectID) }
            focus(s)
        }
    }

    // MARK: Toplu gönderim

    func setBroadcastSelection(_ predicate: (TerminalSession) -> Bool) {
        for s in visibleSessions { s.broadcastSelected = predicate(s) }
    }

    func sendBroadcast() {
        let text = broadcastText
        let targets = broadcastTargets
        guard !text.isEmpty, !targets.isEmpty else { return }
        targets.forEach { $0.send(text) }
        // Enter'ı ayrı gönder: TUI ajanları (Claude/Codex) hızlı gelen metni yapıştırma sanıp
        // satır sonunu yeni satır olarak yorumlayabiliyor.
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(80))
            targets.forEach { $0.send("\r") }
        }
        broadcastText = ""
    }

    func sendToBroadcastTargets(raw: String) {
        broadcastTargets.forEach { $0.send(raw) }
    }

    // MARK: Harici uygulamalar

    func openInXcode(path: String? = nil) {
        guard let path = path ?? targetPath else { return }
        if !Launcher.open(path, with: Launcher.xcode) {
            errorMessage = L("Xcode bulunamadı. App Store'dan yükleyin veya xcode-select ile seçin.", "Xcode not found. Install it from the App Store or select it with xcode-select.")
        }
    }

    func open(with app: ExternalApp, path: String? = nil) {
        guard let path = path ?? targetPath else { return }
        if !Launcher.open(path, with: app) { errorMessage = L("\(app.name) bulunamadı.", "\(app.name) not found.") }
    }

    func openInExternalTerminal(path: String? = nil) {
        open(with: Launcher.preferredTerminal, path: path)
    }

    func revealInFinder(path: String? = nil) {
        guard let path = path ?? targetPath else { return }
        Launcher.reveal(path)
    }

    // MARK: Zamanlayıcı, fare, dock

    private func startTimer() {
        let t = Timer(timeInterval: 1.0, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick() }
        }
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    private func tick() {
        let now = Date()
        tickCount += 1
        if tickCount % 2 == 1 { refreshPorts() }
        if tickCount % 30 == 0 { refreshBranches() }
        if tickCount % 60 == 5 { refreshUsage() }
        if tickCount % 900 == 450 { checkAgents() }
        if tickCount % 5 == 0 { publishWidget() }
        let appActive = NSApp.isActive

        // Klavye odağı başka terminale geçtiyse (tıklama/Tab) takip et
        if let tv = NSApp.keyWindow?.firstResponder as? AgentTerminalView,
           let s = sessions.first(where: { $0.terminalView === tv }),
           s.id != focusedSessionID {
            focus(s, takeKeyboard: false)
        }

        for s in sessions {
            let watching = appActive && s.id == focusedSessionID
            s.refresh(now: now, userIsWatching: watching)
            if watching, s.needsAttention, NSApp.keyWindow?.firstResponder === s.terminalView {
                s.needsAttention = false
            }
        }

        let count = attentionCount
        let label: String? = count > 0 ? "\(count)" : nil
        if NSApp.dockTile.badgeLabel != label { NSApp.dockTile.badgeLabel = label }
    }

    private func attentionRaised(_ s: TerminalSession) {
        if !NSApp.isActive { NSApp.requestUserAttention(.informationalRequest) }
    }

    /// Terminale tıklanınca o oturumu odakla (SwiftTerm'in becomeFirstResponder'ı override edilemiyor).
    private func installMouseMonitor() {
        mouseMonitor = NSEvent.addLocalMonitorForEvents(matching: .leftMouseDown) { [weak self] event in
            MainActor.assumeIsolated {
                guard let self, let content = event.window?.contentView else { return }
                let point = content.convert(event.locationInWindow, from: nil)
                var view = content.hitTest(point)
                while let v = view, !(v is AgentTerminalView) { view = v.superview }
                if let tv = view as? AgentTerminalView,
                   let s = self.sessions.first(where: { $0.terminalView === tv }),
                   s.id != self.focusedSessionID {
                    self.focus(s, takeKeyboard: false)
                }
            }
            return event
        }
    }

    // MARK: Kalıcılık

    private var stateURL: URL {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("DevApp", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("state.json")
    }

    func save() {
        let state = PersistedState(projects: projects, sessions: sessions.map(\.spec),
                                   layout: layout, gridColumns: gridColumns)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? encoder.encode(state) else { return }
        do {
            try data.write(to: stateURL, options: .atomic)
            // Yedek: ana dosya bozulursa buradan yüklenir
            try data.write(to: backupURL, options: .atomic)
        } catch {
            NSLog("DevApp: durum kaydedilemedi: \(error)")
        }
    }

    var dataFolderURL: URL { stateURL.deletingLastPathComponent() }

    private var backupURL: URL {
        stateURL.deletingLastPathComponent().appendingPathComponent("state.backup.json")
    }

    private func load() {
        let decoder = JSONDecoder()
        let candidates = [stateURL, backupURL]
        guard let state = candidates.lazy.compactMap({ url -> PersistedState? in
            guard let data = try? Data(contentsOf: url) else { return nil }
            return try? decoder.decode(PersistedState.self, from: data)
        }).first else { return }
        projects = state.projects
        // Komutu olmayan (eski sürümde eklenmiş) projeler için komutları bul
        for i in projects.indices {
            let found = CommandDetector.detect(in: projects[i].path)
            if projects[i].commands.isEmpty {
                projects[i].commands = found
                continue
            }
            // Mevcut komutların bulunan portlarını tazele (kullanıcının verdiği port korunur)
            for j in projects[i].commands.indices {
                let c = projects[i].commands[j]
                if let match = found.first(where: { $0.command == c.command && $0.subdirectory == c.subdirectory }) {
                    projects[i].commands[j].detectedPort = match.detectedPort
                }
            }
        }
        layout = state.layout
        gridColumns = state.gridColumns

        guard AppSettings.restoreSessions else { return }
        let fm = FileManager.default
        for var spec in state.sessions {
            guard let p = project(spec.projectID) else { continue }
            if let cid = spec.commandID {
                // Komut silinmişse oturumu geri yükleme; varsa güncel tanımı kullan
                guard let cmd = p.commands.first(where: { $0.id == cid }) else { continue }
                spec.name = cmd.name
                spec.command = cmd.launchCommand
                spec.directory = cmd.directory(in: p)
            }
            if !fm.fileExists(atPath: spec.directory) {
                spec.directory = p.path
                spec.worktreeBranch = nil
            }
            makeSession(spec, resume: AppSettings.resumeAgents && spec.kind.isAgent)
        }
        focusedSessionID = sessions.first?.id
        refreshBranches()
        refreshIcons()
        refreshUsage()
        save()
    }

    // MARK: Çıkış

    func confirmQuit() -> Bool {
        let running = sessions.filter { $0.isRunning && $0.kind != .shell }
        guard !running.isEmpty else { return true }
        return confirm(L("DevApp kapatılsın mı?", "Quit DevApp?"),
                       L("\(running.count) ajan/komut hâlâ çalışıyor. Çıkarsanız sonlandırılacak.", "\(running.count) agent(s)/command(s) still running. They will be terminated if you quit."),
                       action: L("Çık", "Quit"))
    }

    func shutdown() {
        save()
        sessions.forEach { $0.terminate() }
    }

    private func confirm(_ title: String, _ text: String, action: String) -> Bool {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = text
        alert.alertStyle = .warning
        alert.addButton(withTitle: action)
        alert.addButton(withTitle: L("Vazgeç", "Cancel"))
        return alert.runModal() == .alertFirstButtonReturn
    }
}
