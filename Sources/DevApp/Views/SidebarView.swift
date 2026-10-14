import SwiftUI

/// Sol ince şerit: pano, tüm terminaller, proje ikonları.
struct RailView: View {
    @Environment(AppStore.self) private var store

    var body: some View {
        VStack(spacing: 8) {
            // Pencere düğmeleri (kırmızı/sarı/yeşil) için boşluk
            Color.clear.frame(height: 30)

            RailButton(symbol: "square.grid.2x2", help: L("Pano", "Dashboard"),
                       selected: store.screen == .dashboard) { store.openDashboard() }
            RailButton(symbol: "terminal", help: L("Tüm terminaller", "All terminals"),
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

            RailButton(symbol: "plus", help: L("Proje ekle", "Add project"), selected: false) { store.addProjectsViaPanel() }
            SettingsLink {
                Image(systemName: "gearshape")
                    .font(.system(size: 17, weight: .medium))
                    .foregroundStyle(Color(hex: 0x8B8E96))
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help(L("Ayarlar", "Settings"))
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
        [L("Mavi", "Blue"), L("Turuncu", "Orange"), L("Turkuaz", "Teal"), L("Sarı", "Yellow"), L("Pembe", "Pink"), L("Gök mavisi", "Sky blue"), L("Mor", "Purple"), L("Yeşil", "Green")][i % 8]
    }

    var body: some View {
        Button(L("Projeyi Başlat", "Start Project")) { store.startProject(project) }
        Button(L("Projeyi Durdur", "Stop Project")) { store.stopProject(project) }
            .disabled(!store.projectHasRunningCommands(project))
        Button(L("Komutları Düzenle…", "Edit Commands…")) { store.editCommands(project) }
        Divider()
        Button(L("Yeni Terminal", "New Terminal")) { store.quickNew(.shell, projectID: project.id) }
        Button(L("Yeni Claude", "New Claude")) { store.quickNew(.claude, projectID: project.id) }
        Button(L("Yeni Codex", "New Codex")) { store.quickNew(.codex, projectID: project.id) }
        Button(L("Yeni Oturum (Gelişmiş)…", "New Session (Advanced)…")) { store.requestNewSession(kind: .claude, projectID: project.id) }
        Divider()
        Button(L("Xcode'da Aç", "Open in Xcode")) { store.openInXcode(path: project.path) }
        Button(L("Finder'da Göster", "Show in Finder")) { store.revealInFinder(path: project.path) }
        Button(L("Harici Terminalde Aç", "Open in External Terminal")) { store.openInExternalTerminal(path: project.path) }
        Button(L("Yolu Kopyala", "Copy Path")) { Launcher.copyPath(project.path) }
        Divider()
        Menu("Logo") {
            Button(L("Dosya Seç…", "Choose File…")) { store.chooseIcon(for: project) }
            Button(L("Projeden Otomatik Bul", "Find in Project")) { store.autoIcon(for: project) }
            Button(L("Logo Kullanma (harf ikonu)", "No Logo (letter icon)")) { store.removeIcon(for: project) }
        }
        Menu(L("Renk", "Color")) {
            Button(L("Otomatik", "Automatic")) { store.setColor(nil, for: project.id) }
            ForEach(Array(Theme.projectPalette.enumerated()), id: \.offset) { i, _ in
                Button(colorName(i)) { store.setColor(i, for: project.id) }
            }
        }
        Divider()
        Button(L("Projeyi Kaldır", "Remove Project"), role: .destructive) { store.removeProject(project) }
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
        Button(L("Odakla", "Focus")) { store.focus(session) }
        Button(store.layout == .focus ? L("Izgaraya Dön", "Back to Grid") : L("Odak Modunda Aç", "Open in Focus Mode")) { store.toggleFocusLayout(on: session) }
        Divider()
        Button(L("Xcode'da Aç", "Open in Xcode")) { store.openInXcode(path: session.directory) }
        Button(L("Finder'da Göster", "Show in Finder")) { store.revealInFinder(path: session.directory) }
        Button(L("Harici Terminalde Aç", "Open in External Terminal")) { store.openInExternalTerminal(path: session.directory) }
        Button(L("Yolu Kopyala", "Copy Path")) { Launcher.copyPath(session.directory) }
        Divider()
        Button(L("Yeniden Adlandır…", "Rename…")) { store.rename(session) }
        Button(L("Yeniden Başlat", "Restart")) { store.restart(session) }
        Button(L("Kapat", "Close"), role: .destructive) { store.close(session) }
    }
}

struct CommandMenuItems: View {
    @Environment(AppStore.self) private var store
    let project: Project
    let command: RunCommand

    var body: some View {
        let running = store.isCommandRunning(command.id)
        Button(running ? L("Durdur", "Stop") : L("Çalıştır", "Run")) { store.toggle(command, in: project) }
        Button(L("Yeniden Başlat", "Restart")) {
            if let s = store.commandSession(command.id) { store.restart(s) } else { store.run(command, in: project) }
        }
        if let s = store.commandSession(command.id) {
            if let url = store.liveURL(for: s) { Button(L("Tarayıcıda Aç (\(url))", "Open in Browser (\(url))")) { store.openURL(url) } }
            Button(L("Terminali Göster", "Show Terminal")) { store.focus(s) }
            Button(L("Çıktıyı Kapat", "Close Output")) { store.close(s) }
        }
        Divider()
        Button(command.effectivePort == nil ? L("Port Ata…", "Assign Port…") : L("Portu Değiştir…", "Change Port…")) { store.editCommands(project) }
        Button(L("Komutları Düzenle…", "Edit Commands…")) { store.editCommands(project) }
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
