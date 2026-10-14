import SwiftUI

/// Proje ekranı: büyük başlık, komut düğmeleri, altında projenin terminalleri.
struct ProjectScreen: View {
    @Environment(AppStore.self) private var store
    let project: Project

    var body: some View {
        VStack(spacing: 0) {
            ProjectHero(project: project)
            TerminalArea(title: L("Terminaller", "Terminals"))
        }
        .background(Theme.bg)
    }
}

struct ProjectHero: View {
    @Environment(AppStore.self) private var store
    let project: Project

    var body: some View {
        let running = store.runningCommandCount(project)
        let state = store.state(of: project)

        VStack(alignment: .leading, spacing: 18) {
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .center, spacing: 16) {
                    heroTitle(running: running, state: state)
                    Spacer(minLength: 12)
                    heroActions(running: running)
                }
                VStack(alignment: .leading, spacing: 14) {
                    heroTitle(running: running, state: state)
                    heroActions(running: running)
                }
            }

            CommandButtons(project: project)
        }
        .padding(.horizontal, 32)
        .padding(.top, 30)
        .padding(.bottom, 18)
        .background(Theme.panel)
        .overlay(alignment: .bottom) { Rectangle().fill(Theme.hairline).frame(height: 1) }
    }

    private func heroTitle(running: Int, state: AppStore.ProjectState) -> some View {
        HStack(alignment: .center, spacing: 16) {
                ProjectAvatar(project: project, size: 56)

                VStack(alignment: .leading, spacing: 5) {
                    HStack(spacing: 10) {
                        Text(verbatim: project.name)
                            .font(.system(size: 26, weight: .bold))
                            .foregroundStyle(Theme.textStrong)
                            .lineLimit(1)
                        switch state {
                        case .attention: StatusPill(text: L("Dikkat bekliyor", "Needs attention"), fg: Theme.orange, bg: Theme.orangeBg)
                        case .running:
                            StatusPill(text: running > 0 ? L("\(running) komut çalışıyor", "\(running) commands running") : L("Ajan çalışıyor", "Agent running"),
                                       fg: Theme.green, bg: Theme.greenBg)
                        case .crashed: StatusPill(text: L("Hata", "Error"), fg: Theme.red, bg: Theme.redBg)
                        case .idle: StatusPill(text: L("Durdu", "Stopped"), fg: Color(hex: 0xA7AAB2), bg: Color(hex: 0x202126))
                        }
                    }
                    HStack(spacing: 14) {
                        Text(verbatim: project.path.abbreviatingHome)
                            .font(Theme.mono(12))
                            .lineLimit(1)
                            .truncationMode(.middle)
                        if let branch = store.projectBranches[project.id] {
                            Label { Text(verbatim: branch) } icon: { Image(systemName: "arrow.triangle.branch") }
                        }
                        if let stack = stackLabel {
                            Text(verbatim: stack)
                        }
                    }
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.secondary)
                }

        }
    }

    /// Eylem düğmeleri tek parça: asla ezilmez, sığmazsa başlığın altına iner
    private func heroActions(running: Int) -> some View {
        HStack(spacing: 10) {

                Menu {
                    Button { store.quickNew(.claude, projectID: project.id) } label: {
                        Label("Claude", systemImage: SessionKind.claude.symbol)
                    }
                    Button { store.quickNew(.codex, projectID: project.id) } label: {
                        Label("Codex", systemImage: SessionKind.codex.symbol)
                    }
                    Button { store.quickNew(.shell, projectID: project.id) } label: {
                        Label("Terminal", systemImage: SessionKind.shell.symbol)
                    }
                    Divider()
                    Button(L("Gelişmiş… (worktree, çoklu ajan, görev)", "Advanced… (worktree, multiple agents, task)")) {
                        store.requestNewSession(kind: .claude, projectID: project.id)
                    }
                } label: {
                    Label(L("Yeni", "New"), systemImage: "plus")
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
                .padding(.horizontal, 12)
                .frame(height: 40)
                .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Theme.raised))
                .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(Color(hex: 0x2A2B30)))
                .help(L("Claude, Codex ya da terminal aç", "Open Claude, Codex or a terminal"))

                Button { store.openInXcode(path: project.path) } label: {
                    Label("Xcode", systemImage: "hammer")
                }
                .buttonStyle(GhostButtonStyle(height: 40))
                .help(L("Xcode'da aç (⇧⌘X)", "Open in Xcode (⇧⌘X)"))

                Menu {
                    Button { store.revealInFinder(path: project.path) } label: {
                        Label(L("Finder'da Göster", "Show in Finder"), systemImage: "folder")
                    }
                    Button { store.openInExternalTerminal(path: project.path) } label: {
                        Label(L("\(Launcher.preferredTerminal.name)'de Aç", "Open in \(Launcher.preferredTerminal.name)"), systemImage: "terminal")
                    }
                    Divider()
                    ForEach(Launcher.installedEditors.filter { $0.id != Launcher.xcode.id }) { app in
                        Button { store.open(with: app, path: project.path) } label: {
                            Label(app.name, systemImage: app.symbol)
                        }
                    }
                    Divider()
                    Button(L("Yolu Kopyala", "Copy Path")) { Launcher.copyPath(project.path) }
                } label: {
                    Image(systemName: "arrow.up.forward.app")
                }
                .menuStyle(.borderlessButton)
                .menuIndicator(.hidden)
                .fixedSize()
                .frame(width: 40, height: 40)
                .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Theme.raised))
                .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(Color(hex: 0x2A2B30)))
                .help(L("Başka uygulamada aç", "Open in another app"))

                if !project.commands.isEmpty {
                    PrimaryRunButton(running: running > 0, color: project.accent, height: 44) {
                        if running > 0 { store.stopProject(project) } else { store.startProject(project) }
                    }
                    .help(running > 0 ? L("Çalışan komutları durdur (⌥⌘.)", "Stop running commands (⌥⌘.)") : L("İşaretli komutları başlat (⌥⌘R)", "Start checked commands (⌥⌘R)"))
                }
        }
        .fixedSize()
    }

    /// "pnpm · docker" gibi kısa yığın etiketi
    private var stackLabel: String? {
        var tools: [String] = []
        for c in project.commands {
            guard let first = c.command.split(separator: " ").first.map(String.init) else { continue }
            let tool: String
            switch first {
            case "npm", "pnpm", "yarn", "bun", "make", "cargo", "go", "swift", "flutter", "dart": tool = first
            case "docker": tool = "docker"
            case "python", "python3": tool = "python"
            case "bin/rails", "bin/dev": tool = "rails"
            default: continue
            }
            if !tools.contains(tool) { tools.append(tool) }
        }
        return tools.isEmpty ? nil : tools.prefix(3).joined(separator: " · ")
    }
}

/// Projenin komutları büyük düğmeler halinde.
/// Monorepo'da (web/, api/, apps/x …) alt projelere göre gruplanır; her grup kendi portlarıyla.
struct CommandButtons: View {
    @Environment(AppStore.self) private var store
    let project: Project

    private struct Group_: Identifiable {
        let id: String
        let title: String?
        let commands: [RunCommand]
    }

    private var groups: [Group_] {
        var order: [String] = []
        var map: [String: [RunCommand]] = [:]
        for c in project.commands {
            let key = c.subdirectory?.nonEmpty ?? ""
            if map[key] == nil { order.append(key) }
            map[key, default: []].append(c)
        }
        return order.map { Group_(id: $0, title: $0.isEmpty ? nil : $0, commands: map[$0] ?? []) }
    }

    var body: some View {
        let groups = groups
        let conflicts = store.conflictCount(in: project)

        VStack(alignment: .leading, spacing: 14) {
            if groups.count <= 1 {
                FlowLayout(spacing: 10, lineSpacing: 10) {
                    ForEach(project.commands) { cmd in
                        CommandButton(project: project, command: cmd)
                    }
                    editButton
                }
            } else {
                ForEach(groups) { g in
                    VStack(alignment: .leading, spacing: 8) {
                        groupHeader(g)
                        FlowLayout(spacing: 10, lineSpacing: 10) {
                            ForEach(g.commands) { cmd in
                                CommandButton(project: project, command: cmd, grouped: g.title != nil)
                            }
                        }
                    }
                }
                editButton
            }

            if conflicts > 0 {
                HStack(spacing: 10) {
                    Image(systemName: "exclamationmark.triangle.fill")
                    Text(verbatim: L("\(conflicts) komut aynı portu kullanıyor; birlikte çalışırsa biri açılamaz.", "\(conflicts) commands share a port; if they run together, one will fail."))
                        .font(.system(size: 12.5))
                    Button(L("Boş portlara taşı", "Move to free ports")) { store.resolvePortConflicts(in: project) }
                        .buttonStyle(.plain)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Color(hex: 0x1A1206))
                        .padding(.horizontal, 10)
                        .frame(height: 26)
                        .background(RoundedRectangle(cornerRadius: 7).fill(Theme.orange))
                        .fixedSize()
                }
                .foregroundStyle(Theme.orange)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(RoundedRectangle(cornerRadius: 10).fill(Theme.orangeBg))
            }
        }
    }

    private func groupHeader(_ g: Group_) -> some View {
        let ports = g.commands.compactMap(\.effectivePort).uniqued()
        return HStack(spacing: 8) {
            Image(systemName: g.title == nil ? "folder" : "folder.fill")
                .font(.system(size: 11))
                .foregroundStyle(project.accent)
            Text(verbatim: g.title.map { "\($0)/" } ?? L("kök", "root"))
                .font(Theme.mono(12, weight: .semibold))
                .foregroundStyle(Color(hex: 0xC9CBD1))
            if !ports.isEmpty {
                Text(verbatim: ports.map { ":\($0)" }.joined(separator: " "))
                    .font(Theme.mono(11))
                    .foregroundStyle(Theme.tertiary)
            }
            if let sub = g.title {
                Button {
                    store.openInXcode(path: URL(fileURLWithPath: project.path).appendingPathComponent(sub).path)
                } label: {
                    Image(systemName: "hammer").font(.system(size: 10.5))
                }
                .buttonStyle(.plain)
                .foregroundStyle(Theme.tertiary)
                .help(L("Bu alt projeyi Xcode'da aç", "Open this sub-project in Xcode"))
                Button {
                    store.openInExternalTerminal(path: URL(fileURLWithPath: project.path).appendingPathComponent(sub).path)
                } label: {
                    Image(systemName: "terminal").font(.system(size: 10.5))
                }
                .buttonStyle(.plain)
                .foregroundStyle(Theme.tertiary)
                .help(L("Bu alt klasörde harici terminal aç", "Open an external terminal in this subfolder"))
            }
        }
    }

    private var editButton: some View {
        Button { store.editCommands(project) } label: {
            HStack(spacing: 8) {
                Image(systemName: project.commands.isEmpty ? "plus" : "slider.horizontal.3")
                    .font(.system(size: 12, weight: .semibold))
                Text(project.commands.isEmpty ? L("Komut ekle", "Add command") : L("Düzenle", "Edit"))
                    .font(.system(size: 13))
            }
            .foregroundStyle(Theme.secondary)
            .padding(.horizontal, 14)
            .frame(height: 44)
            .background(RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(Color(hex: 0x34363D), style: StrokeStyle(lineWidth: 1, dash: [4, 3])))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .fixedSize()
        .help(L("Komutları düzenle (⌥⌘E)", "Edit commands (⌥⌘E)"))
    }
}

struct CommandButton: View {
    @Environment(AppStore.self) private var store
    let project: Project
    let command: RunCommand
    /// Grup başlığı altında: adın başındaki "web: " önekini gösterme
    var grouped = false

    var body: some View {
        let session = store.commandSession(command.id)
        let running = session?.isRunning == true
        let crashed: Bool = {
            if case .exited(let exitCode) = session?.status, let code = exitCode, code != 0 { return true }
            return false
        }()

        HStack(spacing: 10) {
            PlayStopButton(running: running, size: 32) { store.toggle(command, in: project) }

            Button {
                if let session, running { store.focus(session) } else { store.run(command, in: project) }
            } label: {
                VStack(alignment: .leading, spacing: 1) {
                    Text(verbatim: grouped ? command.shortName : command.name)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Color(hex: 0xEDEDF0))
                    Text(verbatim: command.command)
                        .font(Theme.mono(10.5))
                        .foregroundStyle(Color(hex: 0x7E818A))
                        .truncationMode(.middle)
                }
                .lineLimit(1)
                .frame(maxWidth: 240, alignment: .leading)
            }
            .buttonStyle(.plain)
            .help(running ? L("Terminaline git", "Go to its terminal") : L("Çalıştır: \(command.command)", "Run: \(command.command)"))

            PortChip(project: project, command: command)

            if session?.needsAttention == true {
                Image(systemName: "bell.badge.fill").foregroundStyle(Theme.orange)
            }
        }
        .padding(.leading, 6)
        .padding(.trailing, 12)
        .frame(height: 44)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous)
            .fill(running ? Color(hex: 0x16241C) : (crashed ? Color(hex: 0x241616) : Color(hex: 0x17181B))))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous)
            .strokeBorder(running ? Color(hex: 0x2C5A3E) : (crashed ? Color(hex: 0x5A2E22) : Color(hex: 0x26272C))))
        .contextMenu { CommandMenuItems(project: project, command: command) }
    }
}
