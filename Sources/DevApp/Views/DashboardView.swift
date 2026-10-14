import SwiftUI

/// Açılış ekranı: her proje renkli bir kart.
struct DashboardView: View {
    @Environment(AppStore.self) private var store
    @FocusState private var searchFocused: Bool

    var body: some View {
        @Bindable var store = store

        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    header(searchText: $store.searchText)
                    UsageStrip()
                        .padding(.horizontal, 36)
                        .padding(.top, 16)
                    filters
                    grid
                }
            }
            StatusFooter()
        }
        .background(Theme.bg)
    }

    // MARK: Başlık

    private func header(searchText: Binding<String>) -> some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .center, spacing: 16) {
                titleBlock
                Spacer(minLength: 16)
                searchField(searchText)
                addButton
            }
            VStack(alignment: .leading, spacing: 14) {
                titleBlock
                HStack(spacing: 12) {
                    searchField(searchText)
                    addButton
                }
            }
        }
        .padding(.horizontal, 36)
        .padding(.top, 34)
        .padding(.bottom, 8)
    }

    private var titleBlock: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Projeler")
                .font(.system(size: 28, weight: .bold))
                .foregroundStyle(Theme.textStrong)
            Text(verbatim: summary)
                .font(.system(size: 13))
                .foregroundStyle(Theme.secondary)
                .lineLimit(1)
        }
        .fixedSize()
    }

    private func searchField(_ searchText: Binding<String>) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(Theme.tertiary)
            TextField("Proje, komut ya da port ara…", text: searchText)
                .textFieldStyle(.plain)
                .font(.system(size: 13))
                .foregroundStyle(Theme.text)
                .focused($searchFocused)
            Text(verbatim: "⌘F")
                .font(Theme.mono(11))
                .foregroundStyle(Theme.secondary)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(RoundedRectangle(cornerRadius: 5).fill(Color(hex: 0x222328)))
        }
        .padding(.horizontal, 14)
        .frame(minWidth: 220, idealWidth: 280, maxWidth: 280, minHeight: 40, maxHeight: 40)
        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Color(hex: 0x17181B)))
        .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(Color(hex: 0x26272C)))
        .background(
            Button("") { searchFocused = true }
                .keyboardShortcut("f", modifiers: .command)
                .opacity(0)
        )
    }

    private var addButton: some View {
        Button { store.addProjectsViaPanel() } label: {
            HStack(spacing: 8) {
                Image(systemName: "plus").font(.system(size: 13, weight: .bold))
                Text("Proje Ekle").font(.system(size: 13, weight: .semibold)).lineLimit(1)
            }
            .foregroundStyle(Theme.ink)
            .padding(.horizontal, 16)
            .frame(height: 40)
            .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Theme.accent))
        }
        .buttonStyle(.plain)
        .fixedSize()
    }

    private var summary: String {
        let running = store.projects.reduce(0) { $0 + store.runningCommandCount($1) }
        let agents = store.sessions.filter { $0.kind.isAgent && $0.isRunning }.count
        var parts = ["\(store.projects.count) proje"]
        if running > 0 { parts.append("\(running) komut çalışıyor") }
        if agents > 0 { parts.append("\(agents) ajan") }
        if store.attentionCount > 0 { parts.append("\(store.attentionCount) dikkat bekliyor") }
        return parts.joined(separator: " · ")
    }

    // MARK: Filtreler

    private var filters: some View {
        FlowLayout(spacing: 8, lineSpacing: 8) {
            ForEach(DashboardFilter.allCases) { f in
                let active = store.dashboardFilter == f
                Button { store.dashboardFilter = f } label: {
                    HStack(spacing: 8) {
                        Circle().fill(dot(f)).frame(width: 7, height: 7)
                        Text(f.label).font(.system(size: 13, weight: .medium))
                        Text(verbatim: "\(store.count(for: f))")
                            .font(Theme.mono(11))
                            .foregroundStyle(Theme.secondary)
                    }
                    .foregroundStyle(active ? Color(hex: 0xE3E6FF) : Color(hex: 0xC9CBD1))
                    .padding(.horizontal, 14)
                    .frame(height: 34)
                    .background(Capsule().fill(active ? Theme.accentSoft : Theme.card))
                    .overlay(Capsule().strokeBorder(active ? Color(hex: 0x4A5190) : Color(hex: 0x26272C)))
                }
                .buttonStyle(.plain)
                .fixedSize()
            }
        }
        .padding(.horizontal, 36)
        .padding(.top, 14)
        .padding(.bottom, 20)
    }

    private func dot(_ f: DashboardFilter) -> Color {
        switch f {
        case .all: return Color(hex: 0x8E9BFF)
        case .running: return Theme.green
        case .attention: return Theme.orange
        case .stopped: return Theme.tertiary
        }
    }

    // MARK: Kartlar

    private var grid: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 330), spacing: 20, alignment: .top)],
                  alignment: .leading, spacing: 20) {
            ForEach(store.dashboardProjects) { project in
                ProjectCard(project: project)
            }
            if store.dashboardFilter == .all, store.searchText.trimmed.isEmpty {
                AddProjectCard()
            }
        }
        .padding(.horizontal, 36)
        .padding(.bottom, 28)
        .animation(.snappy(duration: 0.25), value: store.dashboardProjects.map(\.id))
    }
}

// MARK: - Proje kartı

struct ProjectCard: View {
    @Environment(AppStore.self) private var store
    let project: Project
    @State private var hovering = false

    var body: some View {
        let state = store.state(of: project)
        let running = store.runningCommandCount(project) > 0

        VStack(alignment: .leading, spacing: 16) {
            // Üst satır
            HStack(spacing: 12) {
                ProjectAvatar(project: project, size: 46)
                VStack(alignment: .leading, spacing: 2) {
                    Button { store.openProject(project) } label: {
                        Text(project.name)
                            .font(.system(size: 17, weight: .semibold))
                            .foregroundStyle(Theme.textStrong)
                            .lineLimit(1)
                    }
                    .buttonStyle(.plain)
                    Text(verbatim: project.path.abbreviatingHome)
                        .font(Theme.mono(11))
                        .foregroundStyle(Color(hex: 0x8B8E96))
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                Spacer(minLength: 4)
                pill(for: state)
            }

            preview

            commandList

            if let crash = store.crashedCommand(in: project), !running {
                HStack(spacing: 10) {
                    Image(systemName: "exclamationmark.triangle")
                        .font(.system(size: 13, weight: .semibold))
                    Text(verbatim: "\(crash.command.name) hatayla kapandı (çıkış \(crash.code))")
                        .font(.system(size: 12.5))
                        .lineLimit(1)
                    Spacer(minLength: 4)
                    Button("Yeniden başlat") { store.run(crash.command, in: project, focusIt: false) }
                        .buttonStyle(.plain)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Color(hex: 0x1A0E0A))
                        .padding(.horizontal, 10)
                        .frame(height: 28)
                        .background(RoundedRectangle(cornerRadius: 8).fill(Color(hex: 0xFF8A6A)))
                }
                .foregroundStyle(Color(hex: 0xFFB4A0))
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .background(RoundedRectangle(cornerRadius: 10).fill(Color(hex: 0x2A1A16)))
                .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Color(hex: 0x5A2E22)))
            }

            footer(running: running)
        }
        .padding(20)
        .background(
            // Tıklama yalnızca boş alanda: içteki ▶/■ ve diğer düğmeleri engellemez
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Theme.card)
                .onTapGesture { store.openProject(project) }
        )
        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(border(state), lineWidth: 1))
        .shadow(color: state == .running ? project.accent.opacity(0.10) : .clear, radius: 14)
        .onHover { hovering = $0 }
        .contextMenu { ProjectMenu(project: project) }
    }

    private func border(_ state: AppStore.ProjectState) -> Color {
        switch state {
        case .attention: return Color(hex: 0x6A4520)
        case .running: return project.accent.opacity(0.35)
        case .crashed: return Color(hex: 0x5A2E22)
        case .idle: return hovering ? Color(hex: 0x34363D) : Theme.border
        }
    }

    @ViewBuilder
    private func pill(for state: AppStore.ProjectState) -> some View {
        switch state {
        case .attention: StatusPill(text: "Dikkat", fg: Theme.orange, bg: Theme.orangeBg)
        case .running: StatusPill(text: "Çalışıyor", fg: Theme.green, bg: Theme.greenBg)
        case .crashed: StatusPill(text: "Hata", fg: Theme.red, bg: Theme.redBg)
        case .idle: StatusPill(text: "Durdu", fg: Color(hex: 0xA7AAB2), bg: Color(hex: 0x202126))
        }
    }

    /// Son çıktı satırları
    private var preview: some View {
        let session = store.previewSession(for: project)
        let lines = session?.previewLines ?? []
        return VStack(alignment: .leading, spacing: 3) {
            if lines.isEmpty {
                Text(project.commands.isEmpty ? "Henüz çıktı yok · komut eklemek için kartı açın"
                                              : "Henüz çıktı yok · ▶ ile bir komut başlatın")
                    .foregroundStyle(Theme.tertiary)
            } else {
                ForEach(Array(lines.enumerated()), id: \.offset) { _, line in
                    Text(verbatim: line)
                        .foregroundStyle(LineTint.color(for: line))
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
            }
            Spacer(minLength: 0)
        }
        .font(Theme.mono(11.5))
        .frame(maxWidth: .infinity, alignment: .leading)
        .frame(height: 92, alignment: .top)
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Theme.rail))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(Theme.hairline))
        .clipped()
    }

    private var commandList: some View {
        let shown = Array(project.commands.prefix(3))
        return VStack(spacing: 6) {
            ForEach(shown) { cmd in
                CardCommandRow(project: project, command: cmd)
            }
            if project.commands.count > shown.count {
                Button { store.openProject(project) } label: {
                    Text(verbatim: "+\(project.commands.count - shown.count) komut daha")
                        .font(.system(size: 12))
                        .foregroundStyle(Theme.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.leading, 6)
                }
                .buttonStyle(.plain)
            }
            if project.commands.isEmpty {
                Button { store.editCommands(project) } label: {
                    Label("Komut ekle", systemImage: "plus")
                        .font(.system(size: 12.5, weight: .medium))
                        .foregroundStyle(Theme.secondary)
                        .frame(maxWidth: .infinity, minHeight: 36)
                        .background(RoundedRectangle(cornerRadius: 10).strokeBorder(Color(hex: 0x2E3036), style: StrokeStyle(lineWidth: 1, dash: [4, 3])))
                }
                .buttonStyle(.plain)
            }
        }
    }

    /// Alt kısım iki satır: bilgiler (kısalabilir) + düğmeler (asla ezilmez)
    private func footer(running: Bool) -> some View {
        let agents = store.agentCount(project)
        return VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                if let branch = store.projectBranches[project.id] {
                    Label { Text(verbatim: branch).lineLimit(1).truncationMode(.middle) } icon: {
                        Image(systemName: "arrow.triangle.branch")
                    }
                    .font(.system(size: 12))
                    .foregroundStyle(Color(hex: 0xA7AAB2))
                }
                Label { Text(verbatim: agents > 0 ? "\(agents) ajan" : "ajan yok").lineLimit(1) } icon: {
                    Image(systemName: "sparkles")
                }
                .font(.system(size: 12))
                .foregroundStyle(agents > 0 ? Theme.orange : Color(hex: 0xA7AAB2))
                .fixedSize()
                Spacer(minLength: 0)
            }

            HStack(spacing: 8) {
                Button { store.openInXcode(path: project.path) } label: {
                    Image(systemName: "hammer").font(.system(size: 14))
                }
                .buttonStyle(GhostButtonStyle(height: 36))
                .fixedSize()
                .help("Xcode'da aç")

                Button { store.quickNew(.claude, projectID: project.id) } label: {
                    Image(systemName: "sparkles").font(.system(size: 14))
                }
                .buttonStyle(GhostButtonStyle(height: 36))
                .fixedSize()
                .help("Bu projede Claude başlat")

                Spacer(minLength: 8)

                if !project.commands.isEmpty {
                    PrimaryRunButton(running: running, color: project.accent) {
                        if running { store.stopProject(project) } else { store.startProject(project, navigate: false) }
                    }
                }
            }
        }
    }
}

/// Kart içindeki komut satırı
struct CardCommandRow: View {
    @Environment(AppStore.self) private var store
    let project: Project
    let command: RunCommand

    var body: some View {
        let running = store.isCommandRunning(command.id)
        HStack(spacing: 10) {
            PlayStopButton(running: running) { store.toggle(command, in: project, focusIt: false) }
            Text(verbatim: command.name)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(Theme.text)
                .lineLimit(1)
                .layoutPriority(1)
            Text(verbatim: command.command)
                .font(Theme.mono(11))
                .foregroundStyle(Color(hex: 0x7E818A))
                .lineLimit(1)
                .truncationMode(.tail)
            Spacer(minLength: 4)
            PortChip(project: project, command: command)
        }
        .padding(.leading, 4)
        .padding(.trailing, 6)
        .frame(height: 36)
        .background(RoundedRectangle(cornerRadius: 10).fill(running ? Color(hex: 0x1B1D22) : .clear))
        .contextMenu { CommandMenuItems(project: project, command: command) }
    }
}

struct AddProjectCard: View {
    @Environment(AppStore.self) private var store
    @State private var hovering = false

    var body: some View {
        Button { store.addProjectsViaPanel() } label: {
            VStack(spacing: 12) {
                Image(systemName: "plus")
                    .font(.system(size: 20, weight: .bold))
                    .foregroundStyle(Color(hex: 0xAEB6FF))
                    .frame(width: 52, height: 52)
                    .background(RoundedRectangle(cornerRadius: 16).fill(Color(hex: 0x1A1B1F)))
                Text("Proje klasörü ekle")
                    .font(.system(size: 14))
                    .foregroundStyle(Color(hex: 0x8B8E96))
                Text("ya da klasörü buraya sürükleyin")
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.tertiary)
            }
            .frame(maxWidth: .infinity, minHeight: 360)
            .background(RoundedRectangle(cornerRadius: 18).fill(hovering ? Color(hex: 0x131417) : .clear))
            .overlay(RoundedRectangle(cornerRadius: 18)
                .strokeBorder(Color(hex: 0x2E3036), style: StrokeStyle(lineWidth: 1.5, dash: [6, 4])))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
    }
}

/// Alt durum çubuğu: çalışanlar, bekleyenler, açık portlar
struct StatusFooter: View {
    @Environment(AppStore.self) private var store

    var body: some View {
        let running = store.projects.reduce(0) { $0 + store.runningCommandCount($1) }
        let ports = store.listeningPorts.sorted()
        HStack(spacing: 18) {
            HStack(spacing: 8) {
                Circle().fill(running > 0 ? Color(hex: 0x3DDC84) : Theme.tertiary).frame(width: 7, height: 7)
                Text(verbatim: running > 0 ? "\(running) komut çalışıyor" : "Çalışan komut yok")
            }
            if store.attentionCount > 0 {
                Button { store.focusNextAttention() } label: {
                    HStack(spacing: 8) {
                        Circle().fill(Theme.orange).frame(width: 7, height: 7)
                        Text(verbatim: "\(store.attentionCount) oturum sizi bekliyor")
                    }
                }
                .buttonStyle(.plain)
                .help("Dikkat bekleyene git (⌘J)")
            }
            Spacer()
            if !ports.isEmpty {
                Text("Açık portlar").font(Theme.mono(12))
                ForEach(ports, id: \.self) { port in
                    Button { store.openURL("http://localhost:\(port)") } label: {
                        Text(verbatim: ":\(port)")
                            .font(Theme.mono(12))
                            .foregroundStyle(Theme.green)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(RoundedRectangle(cornerRadius: 7).fill(Theme.greenBg))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .font(.system(size: 12))
        .foregroundStyle(Theme.secondary)
        .padding(.horizontal, 36)
        .frame(height: 40)
        .background(Color(hex: 0x0B0C0E))
        .overlay(alignment: .top) { Rectangle().fill(Theme.hairline).frame(height: 1) }
    }
}
