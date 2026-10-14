import SwiftUI
import AppKit

extension TerminalSession {
    /// Durum noktası rengi
    var dotColor: Color {
        if needsAttention { return Theme.orange }
        switch status {
        case .busy, .running: return Theme.green
        case .starting: return Theme.secondary
        case .idle: return Color(hex: 0x6F727A)
        case .exited(let code): return code == 0 ? Theme.tertiary : Theme.red
        }
    }

    /// Başlıkta adın yanında gösterilecek açıklama
    var subtitle: String {
        if !title.isEmpty { return title }
        if isRunCommand, let c = customCommand { return c }
        return directory.abbreviatingHome
    }
}

/// Oturum türünü gösteren küçük renkli kare (C, X, ▶, $)
struct KindMark: View {
    let session: TerminalSession
    var size: CGFloat = 22

    private var style: (mark: String, fg: Color, bg: Color) {
        if session.isRunCommand { return ("▶", Theme.green, Theme.greenBg) }
        switch session.kind {
        case .claude: return ("C", Theme.orange, Theme.orangeBg)
        case .codex: return ("X", Color(hex: 0x6EE7D8), Color(hex: 0x123331))
        case .custom: return ("›", Color(hex: 0xC4A8FF), Color(hex: 0x2A2140))
        case .shell: return ("$", Color(hex: 0xC9CBD1), Color(hex: 0x1E1F24))
        }
    }

    var body: some View {
        Text(verbatim: style.mark)
            .font(.system(size: size * 0.5, weight: .bold))
            .foregroundStyle(style.fg)
            .frame(width: size, height: size)
            .background(RoundedRectangle(cornerRadius: size * 0.27, style: .continuous).fill(style.bg))
    }
}

/// Başlık çubuğu + canlı terminal (+ ajan beklerken alt uyarı bandı).
struct TerminalTile: View {
    @Environment(AppStore.self) private var store
    let session: TerminalSession
    let index: Int

    private var isFocused: Bool { store.focusedSessionID == session.id }

    var body: some View {
        VStack(spacing: 0) {
            TileHeader(session: session, index: index, isFocused: isFocused)
            TerminalHost(session: session, focusToken: isFocused ? store.focusToken : -1)
                .padding(.leading, 10)
                .padding(.trailing, 4)
                .padding(.vertical, 6)
            if session.needsAttention && session.isRunning {
                HStack(spacing: 10) {
                    Image(systemName: "bell")
                        .font(.system(size: 13, weight: .semibold))
                    Text(verbatim: attentionText)
                        .font(.system(size: 12.5))
                    Spacer()
                    Button("Gördüm") { store.focus(session) }
                        .buttonStyle(.plain)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Color(hex: 0x1A1206))
                        .padding(.horizontal, 12)
                        .frame(height: 26)
                        .background(RoundedRectangle(cornerRadius: 8).fill(Theme.orange))
                }
                .foregroundStyle(Color(hex: 0xFFCF94))
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(Color(hex: 0x2A1E10))
                .overlay(alignment: .top) { Rectangle().fill(Color(hex: 0x5A3E1C)).frame(height: 1) }
            }
        }
        .background(TerminalTheme.backgroundColor)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(borderColor, lineWidth: isFocused || session.needsAttention ? 1.5 : 1)
        )
        .shadow(color: isFocused ? Theme.accent.opacity(0.12) : .clear, radius: 12)
        .environment(\EnvironmentValues.colorScheme, .dark)
    }

    private var attentionText: String {
        switch session.kind {
        case .claude: return "Claude sizi bekliyor"
        case .codex: return "Codex sizi bekliyor"
        default:
            if case .exited(let code) = session.status { return "Komut kapandı (çıkış \(code.map { String($0) } ?? "?"))" }
            return "İş bitti"
        }
    }

    private var borderColor: Color {
        if session.needsAttention { return Color(hex: 0xB9742E) }
        if isFocused { return Theme.accent }
        return Theme.hairline
    }
}

struct TileHeader: View {
    @Environment(AppStore.self) private var store
    let session: TerminalSession
    let index: Int
    let isFocused: Bool
    @State private var hovering = false

    var body: some View {
        // Kutu genişliğine göre sıkışık mod: dar kutularda ikincil bilgiler gizlenir, düğmeler hiç ezilmez
        GeometryReader { geo in
            content(compact: geo.size.width < 440, tiny: geo.size.width < 300)
                .frame(width: geo.size.width, height: 38)
        }
        .frame(height: 38)
        .background(
            Theme.terminalHeader
                .contentShape(Rectangle())
                .onTapGesture(count: 2) { store.toggleFocusLayout(on: session) }
                .simultaneousGesture(TapGesture().onEnded { store.focus(session) })
        )
        .overlay(alignment: .bottom) { Rectangle().fill(Theme.hairline).frame(height: 1) }
        .onHover { hovering = $0 }
    }

    private func content(compact: Bool, tiny: Bool) -> some View {
        HStack(spacing: compact ? 7 : 9) {
            Circle().fill(session.dotColor).frame(width: 8, height: 8)
                .help(session.status.label)
            if !tiny { KindMark(session: session) }

            // Metinler esner ve kısalır; düğmeler sabit kalır
            HStack(spacing: 7) {
                if !compact, store.filterProjectID == nil, let p = store.project(session.projectID) {
                    Text(verbatim: p.name)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(p.accent)
                        .lineLimit(1)
                        .layoutPriority(1)
                }
                Text(verbatim: session.name)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Theme.text)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .layoutPriority(2)
                if !compact {
                    Text(verbatim: session.subtitle)
                        .font(.system(size: 12))
                        .foregroundStyle(Color(hex: 0x8B8E96))
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
                if !compact, let branch = session.worktreeBranch {
                    Label { Text(verbatim: branch).lineLimit(1) } icon: { Image(systemName: "arrow.triangle.branch") }
                        .font(.system(size: 10.5))
                        .foregroundStyle(Theme.secondary)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Capsule().fill(Color.white.opacity(0.06)))
                        .help(session.directory.abbreviatingHome)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            if !tiny, let url = store.liveURL(for: session) {
                Button { store.openURL(url) } label: {
                    Text(verbatim: url.replacingOccurrences(of: "http://", with: "").replacingOccurrences(of: "localhost", with: ""))
                        .font(Theme.mono(11))
                        .foregroundStyle(Theme.green)
                        .lineLimit(1)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 2)
                        .background(RoundedRectangle(cornerRadius: 6).fill(Theme.greenBg))
                }
                .buttonStyle(.plain)
                .fixedSize()
                .help("Tarayıcıda aç: \(url)")
            }

            if session.isRunCommand {
                PlayStopButton(running: session.isRunning, size: 24) {
                    if session.isRunning { session.stop() } else { store.restart(session) }
                }
            }

            if store.showBroadcast {
                Toggle("", isOn: Binding(
                    get: { session.broadcastSelected },
                    set: { session.broadcastSelected = $0 }
                ))
                .toggleStyle(.checkbox)
                .labelsHidden()
                .fixedSize()
                .help("Toplu gönderime dahil et")
            }

            // İkincil düğmeler: üzerine gelince ya da odaktayken; sıkışık modda yalnızca menü + kapat
            HStack(spacing: 2) {
                if !compact {
                    HeaderIconButton(symbol: "hammer", help: "Bu klasörü Xcode'da aç") {
                        store.openInXcode(path: session.directory)
                    }
                }
                Menu {
                    SessionMenuItems(session: session)
                } label: {
                    Image(systemName: "ellipsis")
                        .font(.system(size: 12, weight: .semibold))
                        .frame(width: 24, height: 24)
                        .contentShape(Rectangle())
                }
                .menuStyle(.borderlessButton)
                .menuIndicator(.hidden)
                .frame(width: 24, height: 24)
                .fixedSize()
                HeaderIconButton(symbol: "xmark", help: "Kapat (⇧⌘W)") { store.close(session) }
            }
            .foregroundStyle(Theme.secondary)
            .opacity(hovering || isFocused ? 1 : 0.0001)
            .fixedSize()

            if !compact, index < 9 {
                Text(verbatim: "⌘\(index + 1)")
                    .font(Theme.mono(11))
                    .foregroundStyle(Color(hex: 0x5F626A))
                    .fixedSize()
            }
        }
        .padding(.horizontal, compact ? 9 : 12)
    }
}

/// Başlıktaki küçük ikon düğmesi (sabit 24×24)
struct HeaderIconButton: View {
    let symbol: String
    let help: String
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 11.5, weight: .semibold))
                .frame(width: 24, height: 24)
                .background(RoundedRectangle(cornerRadius: 6).fill(hovering ? Color.white.opacity(0.08) : .clear))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .fixedSize()
        .onHover { hovering = $0 }
        .help(help)
    }
}

/// Oturumun kalıcı terminal NSView'ini SwiftUI içine yerleştirir.
/// Görünüm her seferinde yeniden oluşturulmaz; sadece taşıyıcısı değişir, böylece süreç yaşar.
struct TerminalHost: NSViewRepresentable {
    let session: TerminalSession
    /// -1: odakta değil. Değer değişince terminal klavye odağını alır.
    let focusToken: Int

    final class Coordinator {
        var lastToken = -1
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeNSView(context: Context) -> NSView {
        let container = NSView()
        attach(to: container)
        return container
    }

    func updateNSView(_ container: NSView, context: Context) {
        attach(to: container)
        if focusToken >= 0, focusToken != context.coordinator.lastToken {
            context.coordinator.lastToken = focusToken
            let tv = session.terminalView
            Task { @MainActor in
                tv.window?.makeFirstResponder(tv)
            }
        }
    }

    static func dismantleNSView(_ container: NSView, coordinator: Coordinator) {
        // Terminal başka bir taşıyıcıya geçmişse burada bulunmaz; yalnızca kendimizinkini bırakırız.
        container.subviews.forEach { $0.removeFromSuperview() }
    }

    private func attach(to container: NSView) {
        let tv = session.terminalView
        for sub in container.subviews where sub !== tv {
            sub.removeFromSuperview()
        }
        guard tv.superview !== container else { return }
        tv.removeFromSuperview()
        tv.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(tv)
        NSLayoutConstraint.activate([
            tv.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            tv.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            tv.topAnchor.constraint(equalTo: container.topAnchor),
            tv.bottomAnchor.constraint(equalTo: container.bottomAnchor),
        ])
    }
}
