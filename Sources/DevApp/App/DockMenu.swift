import AppKit

/// Dock simgesine sağ tıklayınca açılan menü: projelere göre açık terminaller,
/// dikkat bekleyenler ve hızlı eylemler.
@MainActor
final class DockMenu: NSObject {
    static let shared = DockMenu()

    func build() -> NSMenu {
        let store = AppStore.shared
        let menu = NSMenu()
        menu.autoenablesItems = false

        // Dikkat bekleyenler en üstte
        let waiting = store.sessions.filter(\.needsAttention)
        if !waiting.isEmpty {
            let header = NSMenuItem(title: "Sizi bekleyen (\(waiting.count))", action: nil, keyEquivalent: "")
            header.isEnabled = false
            menu.addItem(header)
            for s in waiting {
                menu.addItem(sessionItem(s, store: store, indent: 1))
            }
            menu.addItem(.separator())
        }

        // Projelere göre açık terminaller
        var any = false
        for project in store.projects {
            let sessions = store.sessions(in: project.id)
            let running = store.runningCommandCount(project) > 0
            guard !sessions.isEmpty || running else { continue }
            any = true

            let header = NSMenuItem(title: project.name, action: #selector(openProject(_:)), keyEquivalent: "")
            header.target = self
            header.representedObject = project.id
            header.image = projectImage(project)
            header.submenu = projectSubmenu(project, store: store)
            menu.addItem(header)

            for s in sessions {
                menu.addItem(sessionItem(s, store: store, indent: 1))
            }
        }
        if !any {
            let empty = NSMenuItem(title: "Açık terminal yok", action: nil, keyEquivalent: "")
            empty.isEnabled = false
            menu.addItem(empty)
        }

        // Duran projeleri başlat
        let idle = store.projects.filter { !$0.commands.isEmpty && store.runningCommandCount($0) == 0 }
        if !idle.isEmpty {
            menu.addItem(.separator())
            let start = NSMenuItem(title: "Projeyi Başlat", action: nil, keyEquivalent: "")
            let sub = NSMenu()
            for p in idle {
                let item = NSMenuItem(title: p.name, action: #selector(startProject(_:)), keyEquivalent: "")
                item.target = self
                item.representedObject = p.id
                item.image = projectImage(p)
                sub.addItem(item)
            }
            start.submenu = sub
            menu.addItem(start)
        }

        menu.addItem(.separator())
        menu.addItem(actionItem("Pano", #selector(openDashboard)))
        menu.addItem(actionItem("Tüm Terminaller", #selector(openTerminals)))
        return menu
    }

    // MARK: Öğeler

    private func sessionItem(_ s: TerminalSession, store: AppStore, indent: Int) -> NSMenuItem {
        var title = "\(symbol(for: s))  \(s.name)"
        if !s.title.isEmpty, s.title != s.name { title += " — \(s.title.prefix(40))" }
        if let cid = s.commandID, let port = store.command(cid)?.1.effectivePort, s.isRunning {
            title += "   :\(port)"
        }
        if case .exited = s.status { title += "  (kapandı)" }

        let item = NSMenuItem(title: title, action: #selector(openSession(_:)), keyEquivalent: "")
        item.target = self
        item.representedObject = s.id
        item.indentationLevel = indent
        item.toolTip = s.directory
        return item
    }

    private func symbol(for s: TerminalSession) -> String {
        if s.needsAttention { return "⚠︎" }
        if case .exited = s.status { return "■" }
        if s.isRunCommand { return "▶︎" }
        switch s.kind {
        case .claude: return "✳︎"
        case .codex: return "◆"
        case .custom: return "›"
        case .shell: return "$"
        }
    }

    private func projectSubmenu(_ p: Project, store: AppStore) -> NSMenu {
        let sub = NSMenu()
        sub.autoenablesItems = false
        let open = NSMenuItem(title: "Projeyi Aç", action: #selector(openProject(_:)), keyEquivalent: "")
        open.target = self
        open.representedObject = p.id
        sub.addItem(open)

        if !p.commands.isEmpty {
            let running = store.runningCommandCount(p) > 0
            let toggle = NSMenuItem(title: running ? "Durdur" : "Başlat",
                                    action: running ? #selector(stopProject(_:)) : #selector(startProject(_:)),
                                    keyEquivalent: "")
            toggle.target = self
            toggle.representedObject = p.id
            sub.addItem(toggle)
        }

        let xcode = NSMenuItem(title: "Xcode'da Aç", action: #selector(openXcode(_:)), keyEquivalent: "")
        xcode.target = self
        xcode.representedObject = p.id
        sub.addItem(xcode)

        let claude = NSMenuItem(title: "Yeni Claude", action: #selector(newClaude(_:)), keyEquivalent: "")
        claude.target = self
        claude.representedObject = p.id
        sub.addItem(claude)
        return sub
    }

    private func actionItem(_ title: String, _ action: Selector) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
        item.target = self
        return item
    }

    /// Projenin renginde küçük yuvarlak kare
    private func projectImage(_ p: Project) -> NSImage {
        let size = NSSize(width: 12, height: 12)
        let hex = p.accentHex
        let image = NSImage(size: size, flipped: false) { rect in
            NSColor(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255,
                    green: CGFloat((hex >> 8) & 0xFF) / 255,
                    blue: CGFloat(hex & 0xFF) / 255, alpha: 1).setFill()
            NSBezierPath(roundedRect: rect.insetBy(dx: 1, dy: 1), xRadius: 3, yRadius: 3).fill()
            return true
        }
        return image
    }

    // MARK: Eylemler

    private func bringToFront() {
        NSApp.activate(ignoringOtherApps: true)
        AppStore.shared.showMainWindow()
    }

    @objc private func openSession(_ sender: NSMenuItem) {
        guard let id = sender.representedObject as? UUID, let s = AppStore.shared.session(id) else { return }
        bringToFront()
        AppStore.shared.reveal(s)
    }

    @objc private func openProject(_ sender: NSMenuItem) {
        guard let id = sender.representedObject as? UUID, let p = AppStore.shared.project(id) else { return }
        bringToFront()
        AppStore.shared.openProject(p)
    }

    @objc private func startProject(_ sender: NSMenuItem) {
        guard let id = sender.representedObject as? UUID, let p = AppStore.shared.project(id) else { return }
        AppStore.shared.startProject(p, navigate: false)
    }

    @objc private func stopProject(_ sender: NSMenuItem) {
        guard let id = sender.representedObject as? UUID, let p = AppStore.shared.project(id) else { return }
        AppStore.shared.stopProject(p)
    }

    @objc private func openXcode(_ sender: NSMenuItem) {
        guard let id = sender.representedObject as? UUID, let p = AppStore.shared.project(id) else { return }
        AppStore.shared.openInXcode(path: p.path)
    }

    @objc private func newClaude(_ sender: NSMenuItem) {
        guard let id = sender.representedObject as? UUID else { return }
        bringToFront()
        AppStore.shared.quickNew(.claude, projectID: id)
    }

    @objc private func openDashboard() {
        bringToFront()
        AppStore.shared.openDashboard()
    }

    @objc private func openTerminals() {
        bringToFront()
        AppStore.shared.openTerminals()
    }
}
