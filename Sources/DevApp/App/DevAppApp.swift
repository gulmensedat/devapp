import SwiftUI
import AppKit

@main
struct DevAppApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var store = AppStore.shared

    var body: some Scene {
        // Tek pencere: terminal görünümleri aynı anda yalnızca bir yerde gösterilebilir.
        Window("DevApp", id: "main") {
            ContentView()
                .environment(store)
                .frame(minWidth: 980, minHeight: 620)
        }
        // Başlık çubuğu gizli: içerik pencerenin tepesine kadar uzanır, sol şerit trafik ışıklarının altında başlar
        .windowStyle(.hiddenTitleBar)
        .defaultSize(width: 1440, height: 900)
        .commands { AppCommands(store: store) }

        Settings {
            SettingsView()
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        // `swift run` ile çalışırken de Dock'ta görünsün ve öne gelsin
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        applyDevelopmentIcon()
    }

    /// .app paketi dışında (swift run / Xcode) çalışırken Dock'ta ikon görünsün diye depodaki PNG'yi kullan.
    private func applyDevelopmentIcon() {
        guard Bundle.main.bundleURL.pathExtension != "app" else { return }
        let repoRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()   // App
            .deletingLastPathComponent()   // DevApp
            .deletingLastPathComponent()   // Sources
            .deletingLastPathComponent()   // depo kökü
        let candidates = [
            repoRoot.appendingPathComponent("Support/AppIcon.png"),
            URL(fileURLWithPath: FileManager.default.currentDirectoryPath).appendingPathComponent("Support/AppIcon.png"),
        ]
        for url in candidates {
            if let image = NSImage(contentsOf: url) {
                NSApp.applicationIconImage = image
                return
            }
        }
    }

    /// Dock simgesine sağ tık: açık terminaller, bekleyenler, projeyi başlat
    func applicationDockMenu(_ sender: NSApplication) -> NSMenu? {
        MainActor.assumeIsolated { DockMenu.shared.build() }
    }

    /// Dock simgesine tıklanınca pencere kapalıysa yeniden aç
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag { MainActor.assumeIsolated { AppStore.shared.showMainWindow() } }
        return true
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        let ok = MainActor.assumeIsolated { AppStore.shared.confirmQuit() }
        return ok ? NSApplication.TerminateReply.terminateNow : NSApplication.TerminateReply.terminateCancel
    }

    func applicationWillTerminate(_ notification: Notification) {
        MainActor.assumeIsolated {
            AppStore.shared.shutdown()
        }
    }

    /// Pencere kapansa da ajanlar arka planda çalışmaya devam eder.
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }
}

struct AppCommands: Commands {
    let store: AppStore

    var body: some Commands {
        CommandGroup(replacing: .newItem) {
            Button("Yeni Terminal") { store.quickNew(.shell) }
                .keyboardShortcut("t", modifiers: .command)
            Button("Yeni Claude Oturumu") { store.quickNew(.claude) }
                .keyboardShortcut("c", modifiers: [.command, .shift])
            Button("Yeni Codex Oturumu") { store.quickNew(.codex) }
                .keyboardShortcut("k", modifiers: [.command, .shift])
            Button("Yeni Oturum (Gelişmiş)…") { store.requestNewSession(kind: .claude) }
                .keyboardShortcut("n", modifiers: .command)
            Divider()
            Button("Proje Ekle…") { store.addProjectsViaPanel() }
                .keyboardShortcut("o", modifiers: .command)
        }

        CommandMenu("Proje") {
            Button("Projeyi Başlat") { if let p = store.currentProject { store.startProject(p) } }
                .keyboardShortcut("r", modifiers: [.command, .option])
            Button("Projeyi Durdur") { if let p = store.currentProject { store.stopProject(p) } }
                .keyboardShortcut(".", modifiers: [.command, .option])
            Button("Komutları Düzenle…") { if let p = store.currentProject { store.editCommands(p) } }
                .keyboardShortcut("e", modifiers: [.command, .option])
        }

        CommandGroup(after: .sidebar) {
            Button("Pano") { store.openDashboard() }
                .keyboardShortcut("0", modifiers: .command)
            Button("Tüm Terminaller") { store.openTerminals() }
                .keyboardShortcut("0", modifiers: [.command, .shift])
            Divider()
        }

        CommandMenu("Terminaller") {
            Button("Izgara / Odak Modu") { store.toggleLayout() }
                .keyboardShortcut(.return, modifiers: .command)
            Button("Sonraki Terminal") { store.focusNext(1) }
                .keyboardShortcut(.tab, modifiers: .control)
            Button("Önceki Terminal") { store.focusNext(-1) }
                .keyboardShortcut(.tab, modifiers: [.control, .shift])
            Button("Dikkat Bekleyene Git") { store.focusNextAttention() }
                .keyboardShortcut("j", modifiers: .command)
            Divider()
            Button("Yeniden Başlat") { if let s = store.focusedSession { store.restart(s) } }
                .keyboardShortcut("r", modifiers: [.command, .shift])
            Button("Yeniden Adlandır…") { if let s = store.focusedSession { store.rename(s) } }
            Button("Terminali Kapat") { if let s = store.focusedSession { store.close(s) } }
                .keyboardShortcut("w", modifiers: [.command, .shift])
            Divider()
            Button("Toplu Gönderim Çubuğu") { store.showBroadcast.toggle() }
                .keyboardShortcut("b", modifiers: [.command, .shift])
            Divider()
            ForEach(1...9, id: \.self) { n in
                Button("Terminal \(n)") { store.focusIndex(n - 1) }
                    .keyboardShortcut(KeyEquivalent(Character("\(n)")), modifiers: .command)
            }
        }

        CommandMenu("Aç") {
            Button("Xcode'da Aç") { store.openInXcode() }
                .keyboardShortcut("x", modifiers: [.command, .shift])
            Button("Finder'da Göster") { store.revealInFinder() }
                .keyboardShortcut("f", modifiers: [.command, .shift])
            Button("Harici Terminalde Aç") { store.openInExternalTerminal() }
                .keyboardShortcut("t", modifiers: [.command, .shift])
            Divider()
            ForEach(Launcher.installedEditors.filter { $0.id != Launcher.xcode.id }) { app in
                Button("\(app.name) ile Aç") { store.open(with: app) }
            }
        }
    }
}
