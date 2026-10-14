import AppKit

struct ExternalApp: Identifiable, Hashable {
    let id: String      // bundle identifier
    let name: String
    let symbol: String
}

/// Klasörleri Xcode, editörler ve harici terminallerde açar.
enum Launcher {
    static let xcode = ExternalApp(id: "com.apple.dt.Xcode", name: "Xcode", symbol: "hammer")

    static let editors: [ExternalApp] = [
        xcode,
        ExternalApp(id: "com.microsoft.VSCode", name: "VS Code", symbol: "chevron.left.forwardslash.chevron.right"),
        ExternalApp(id: "com.todesktop.230313mzl4w4u92", name: "Cursor", symbol: "cursorarrow.rays"),
        ExternalApp(id: "dev.zed.Zed", name: "Zed", symbol: "bolt"),
        ExternalApp(id: "com.google.android.studio", name: "Android Studio", symbol: "apps.iphone"),
    ]

    static let terminals: [ExternalApp] = [
        ExternalApp(id: "com.mitchellh.ghostty", name: "Ghostty", symbol: "terminal"),
        ExternalApp(id: "com.googlecode.iterm2", name: "iTerm", symbol: "terminal"),
        ExternalApp(id: "dev.warp.Warp-Stable", name: "Warp", symbol: "terminal"),
        ExternalApp(id: "com.apple.Terminal", name: "Terminal", symbol: "terminal"),
    ]

    static func appURL(_ app: ExternalApp) -> URL? {
        NSWorkspace.shared.urlForApplication(withBundleIdentifier: app.id)
    }

    static var installedEditors: [ExternalApp] { editors.filter { appURL($0) != nil } }
    static var installedTerminals: [ExternalApp] { terminals.filter { appURL($0) != nil } }
    static var preferredTerminal: ExternalApp { installedTerminals.first ?? terminals[terminals.count - 1] }

    @discardableResult
    static func open(_ path: String, with app: ExternalApp) -> Bool {
        guard let appURL = appURL(app) else { return false }
        let target = app.id == xcode.id ? xcodeTarget(for: path) : URL(fileURLWithPath: path)
        let config = NSWorkspace.OpenConfiguration()
        config.activates = true
        NSWorkspace.shared.open([target], withApplicationAt: appURL, configuration: config, completionHandler: nil)
        return true
    }

    static func reveal(_ path: String) {
        NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: path)])
    }

    static func copyPath(_ path: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(path, forType: .string)
    }

    /// Klasörde açılacak en uygun Xcode hedefini bulur:
    /// .xcworkspace > .xcodeproj > Package.swift; yoksa ios/, macos/ gibi alt klasörlere bakar.
    static func xcodeTarget(for dir: String) -> URL {
        let fm = FileManager.default
        let base = URL(fileURLWithPath: dir)

        func scan(_ folder: URL) -> URL? {
            guard let items = try? fm.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil,
                                                          options: [.skipsHiddenFiles]) else { return nil }
            if let ws = items.first(where: { $0.pathExtension == "xcworkspace" }) { return ws }
            if let proj = items.first(where: { $0.pathExtension == "xcodeproj" }) { return proj }
            if let pkg = items.first(where: { $0.lastPathComponent == "Package.swift" }) { return pkg }
            return nil
        }

        if let t = scan(base) { return t }
        for sub in ["ios", "iOS", "macos", "macOS", "App", "apple"] {
            if let t = scan(base.appendingPathComponent(sub)) { return t }
        }

        let skip: Set<String> = ["node_modules", "Pods", "build", "DerivedData", "vendor"]
        if let items = try? fm.contentsOfDirectory(at: base, includingPropertiesForKeys: [.isDirectoryKey],
                                                   options: [.skipsHiddenFiles]) {
            for item in items {
                let isDir = (try? item.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false
                guard isDir, !skip.contains(item.lastPathComponent),
                      !["xcodeproj", "xcworkspace"].contains(item.pathExtension) else { continue }
                if let t = scan(item) { return t }
            }
        }
        return base
    }
}
