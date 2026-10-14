import SwiftUI

/// Sol ince şerit: pano, tüm terminaller, proje ikonları.
struct RailView: View {
    @Environment(AppStore.self) private var store

    var body: some View {
        VStack(spacing: 8) {
            // Pencere düğmeleri (kırmızı/sarı/yeşil) için boşluk
            Color.clear.frame(height: 30)

            RailButton(symbol: "square.grid.2x2", help: "Pano",
                       selected: store.screen == .dashboard) { store.openDashboard() }
            RailButton(symbol: "terminal", help: "Tüm terminaller",
                       selected: store.screen == .terminals,
                       badge: store.attentionCount > 0) { store.openTerminals() }

            Rectangle().fill(Theme.border).frame(width: 28, height: 1).padding(.vertical, 6)

            ScrollView(showsIndicators: false) {
                VStack(spacing: 10) {
                    ForEach(store.projects) { project in
                        RailProjectButton(project: project)
                    }
                }
                .padding(.vertical, 4)
            }

            Spacer(minLength: 8)

            RailButton(symbol: "plus", help: "Proje ekle", selected: false) { store.addProjectsViaPanel() }
            SettingsLink {
                Image(systemName: "gearshape")
                    .font(.system(size: 17, weight: .medium))
                    .foregroundStyle(Color(hex: 0x8B8E96))
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("Ayarlar")
        }
        .padding(.bottom, 14)
        .frame(width: 68)
        .frame(maxHeight: .infinity)
        .background(Theme.rail)
        .overlay(alignment: .trailing) { Rectangle().fill(Theme.hairline).frame(width: 1) }
        .dropDestination(for: URL.self) { urls, _ in
            store.addProjects(urls)
            return true
        }
    }
}

struct RailButton: View {
    let symbol: String
    let help: String
    let selected: Bool
    var badge = false
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 17, weight: .medium))
                .foregroundStyle(selected ? Color(hex: 0xC4CAFF) : Color(hex: 0x8B8E96))
                .frame(width: 44, height: 44)
                .background(RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(selected ? Theme.accentSoft : (hovering ? Color(hex: 0x17181B) : .clear)))
                .overlay(alignment: .topTrailing) {
                    if badge {
                        Circle().fill(Theme.orange)
                            .frame(width: 9, height: 9)
                            .overlay(Circle().stroke(Theme.rail, lineWidth: 2))
                            .offset(x: -8, y: 8)
                    }
                }
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .help(help)
        .accessibilityLabel(help)
    }
}

struct RailProjectButton: View {
    @Environment(AppStore.self) private var store
    let project: Project

    var body: some View {
        let selected = store.screen == .project(project.id)
        let state = store.state(of: project)
        let active = state == .running || state == .attention

        Button { store.openProject(project) } label: {
            ProjectAvatar(project: project, size: 40, dimmed: !active && !selected)
                .padding(3)
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .strokeBorder(selected ? project.accent : .clear, lineWidth: 2)
                )
                .overlay(alignment: .bottomTrailing) {
                    if state != .idle {
                        Circle()
                            .fill(state == .attention ? Theme.orange : (state == .crashed ? Theme.red : Theme.green))
                            .frame(width: 10, height: 10)
                            .overlay(Circle().stroke(Theme.rail, lineWidth: 2))
                    }
                }
        }
        .buttonStyle(.plain)
        .help(project.name)
        .accessibilityLabel(project.name)
        .contextMenu { ProjectMenu(project: project) }
    }
}

struct CountBadge: View {
    let count: Int
    var attention: Int = 0

    var body: some View {
        HStack(spacing: 4) {
            if attention > 0 {
                Text("\(attention)")
                    .font(.caption2.bold())
                    .padding(.horizontal, 5)
                    .background(Capsule().fill(.orange))
                    .foregroundStyle(.white)
            }
            if count > 0 {
                Text("\(count)").font(.caption).foregroundStyle(.secondary)
            }
        }
    }
}

struct ProjectMenu: View {
    @Environment(AppStore.self) private var store
    let project: Project

    private func colorName(_ i: Int) -> String {
        ["Mavi", "Turuncu", "Turkuaz", "Sarı", "Pembe", "Gök mavisi", "Mor", "Yeşil"][i % 8]
    }

    var body: some View {
        Button("Projeyi Başlat") { store.startProject(project) }
        Button("Projeyi Durdur") { store.stopProject(project) }
            .disabled(!store.projectHasRunningCommands(project))
        Button("Komutları Düzenle…") { store.editCommands(project) }
        Divider()
        Button("Yeni Terminal") { store.quickNew(.shell, projectID: project.id) }
        Button("Yeni Claude") { store.quickNew(.claude, projectID: project.id) }
        Button("Yeni Codex") { store.quickNew(.codex, projectID: project.id) }
        Button("Yeni Oturum (Gelişmiş)…") { store.requestNewSession(kind: .claude, projectID: project.id) }
        Divider()
        Button("Xcode'da Aç") { store.openInXcode(path: project.path) }
        Button("Finder'da Göster") { store.revealInFinder(path: project.path) }
        Button("Harici Terminalde Aç") { store.openInExternalTerminal(path: project.path) }
        Button("Yolu Kopyala") { Launcher.copyPath(project.path) }
        Divider()
        Menu("Renk") {
            Button("Otomatik") { store.setColor(nil, for: project.id) }
            ForEach(Array(Theme.projectPalette.enumerated()), id: \.offset) { i, _ in
                Button(colorName(i)) { store.setColor(i, for: project.id) }
            }
        }
        Divider()
        Button("Projeyi Kaldır", role: .destructive) { store.removeProject(project) }
    }
}

struct StatusDot: View {
    let status: SessionStatus

    var body: some View {
        Image(systemName: "circle.fill")
            .font(.system(size: 7))
            .foregroundStyle(status.color)
            .symbolEffect(.pulse, isActive: status == .busy)
            .help(status.label)
    }
}

/// Terminal oturumu için ortak menü öğeleri (kenar çubuğu + kutu başlığı).
struct SessionMenuItems: View {
    @Environment(AppStore.self) private var store
    let session: TerminalSession

    var body: some View {
        Button("Odakla") { store.focus(session) }
        Button(store.layout == .focus ? "Izgaraya Dön" : "Odak Modunda Aç") { store.toggleFocusLayout(on: session) }
        Divider()
        Button("Xcode'da Aç") { store.openInXcode(path: session.directory) }
        Button("Finder'da Göster") { store.revealInFinder(path: session.directory) }
        Button("Harici Terminalde Aç") { store.openInExternalTerminal(path: session.directory) }
        Button("Yolu Kopyala") { Launcher.copyPath(session.directory) }
        Divider()
        Button("Yeniden Adlandır…") { store.rename(session) }
        Button("Yeniden Başlat") { store.restart(session) }
        Button("Kapat", role: .destructive) { store.close(session) }
    }
}

struct CommandMenuItems: View {
    @Environment(AppStore.self) private var store
    let project: Project
    let command: RunCommand

    var body: some View {
        let running = store.isCommandRunning(command.id)
        Button(running ? "Durdur" : "Çalıştır") { store.toggle(command, in: project) }
        Button("Yeniden Başlat") {
            if let s = store.commandSession(command.id) { store.restart(s) } else { store.run(command, in: project) }
        }
        if let s = store.commandSession(command.id) {
            if let url = store.liveURL(for: s) { Button("Tarayıcıda Aç (\(url))") { store.openURL(url) } }
            Button("Terminali Göster") { store.focus(s) }
            Button("Çıktıyı Kapat") { store.close(s) }
        }
        Divider()
        Button(command.effectivePort == nil ? "Port Ata…" : "Portu Değiştir…") { store.editCommands(project) }
        Button("Komutları Düzenle…") { store.editCommands(project) }
    }
}

/// ":3000" rozeti; port dinleniyorsa yeşil.
struct PortBadge: View {
    let port: Int
    let isOpen: Bool

    var body: some View {
        Text(verbatim: ":\(port)")
            .font(.system(size: 10, weight: .medium, design: .monospaced))
            .padding(.horizontal, 5)
            .padding(.vertical, 1)
            .background(Capsule().fill(isOpen ? Color.green.opacity(0.22) : Color.primary.opacity(0.07)))
            .foregroundStyle(isOpen ? Color.green : Color.secondary)
    }
}

extension Sequence where Element: Hashable {
    func uniqued() -> [Element] {
        var seen = Set<Element>()
        return filter { seen.insert($0).inserted }
    }
}
