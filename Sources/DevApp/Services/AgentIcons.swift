import AppKit
import SwiftUI

/// Claude / Codex logoları: Mac'te kurulu resmi masaüstü uygulamalarının kendi ikonları kullanılır
/// (Claude.app, Codex.app, yoksa ChatGPT.app). Hiçbiri kurulu değilse harf ikonu gösterilir.
@MainActor
enum AgentIcons {
    private static var cache: [AgentKind: NSImage?] = [:]

    private static func bundleIDs(_ agent: AgentKind) -> [String] {
        switch agent {
        case .claude: return ["com.anthropic.claudefordesktop", "com.anthropic.claude"]
        case .codex: return ["com.openai.codex", "com.openai.chat"]
        }
    }

    static func image(for agent: AgentKind) -> NSImage? {
        if let cached = cache[agent] { return cached }
        var found: NSImage?
        for id in bundleIDs(agent) {
            if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: id) {
                found = NSWorkspace.shared.icon(forFile: url.path)
                break
            }
        }
        cache[agent] = .some(found)
        return found
    }

    /// Widget için App Group kabına PNG yazar (widget uygulama ikonlarını kendisi okuyamaz).
    static func writeForWidget() {
        for agent in AgentKind.allCases {
            guard let url = SharedStore.agentIconURL(agent.rawValue) else { continue }
            guard let image = image(for: agent), let data = ProjectIconFinder.pngData(from: image) else {
                try? FileManager.default.removeItem(at: url)
                continue
            }
            try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try? data.write(to: url, options: .atomic)
        }
    }
}

/// Ajan logosu; uygulama ikonu yoksa renkli harf
struct AgentLogo: View {
    let agent: AgentKind
    var size: CGFloat = 22

    var body: some View {
        if let image = AgentIcons.image(for: agent) {
            Image(nsImage: image)
                .resizable()
                .interpolation(.high)
                .aspectRatio(contentMode: .fit)
                .frame(width: size, height: size)
        } else {
            let tint = agent == .claude ? Color(hex: 0xFFB86B) : Color(hex: 0x6EE7D8)
            let bg = agent == .claude ? Color(hex: 0x3A2614) : Color(hex: 0x123331)
            Text(verbatim: agent == .claude ? "C" : "X")
                .font(.system(size: size * 0.5, weight: .bold))
                .foregroundStyle(tint)
                .frame(width: size, height: size)
                .background(RoundedRectangle(cornerRadius: size * 0.27, style: .continuous).fill(bg))
        }
    }
}
