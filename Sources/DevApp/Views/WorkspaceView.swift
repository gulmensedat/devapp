import SwiftUI

/// Tüm projelerin terminalleri
struct AllTerminalsScreen: View {
    var body: some View {
        VStack(spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Tüm Terminaller")
                        .font(.system(size: 26, weight: .bold))
                        .foregroundStyle(Theme.textStrong)
                    Text("Her projedeki komutlar, ajanlar ve terminaller")
                        .font(.system(size: 13))
                        .foregroundStyle(Theme.secondary)
                }
                Spacer()
            }
            .padding(.horizontal, 32)
            .padding(.top, 30)
            .padding(.bottom, 6)
            TerminalArea(title: nil)
        }
        .background(Theme.bg)
    }
}

/// Terminal ızgarası/odak görünümü + bölüm başlığı + toplu gönderim çubuğu
struct TerminalArea: View {
    @Environment(AppStore.self) private var store
    let title: String?

    var body: some View {
        let visible = store.visibleSessions
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                if let title {
                    Text(title.uppercased())
                        .font(.system(size: 12, weight: .semibold))
                        .tracking(0.6)
                        .foregroundStyle(Color(hex: 0xA7AAB2))
                }
                Text(verbatim: "\(visible.count)")
                    .font(Theme.mono(11))
                    .foregroundStyle(Theme.tertiary)
                Spacer()

                Button { store.showBroadcast.toggle() } label: {
                    Image(systemName: "dot.radiowaves.left.and.right")
                        .foregroundStyle(store.showBroadcast ? Color(hex: 0xC4CAFF) : Theme.secondary)
                        .frame(width: 30, height: 28)
                        .background(RoundedRectangle(cornerRadius: 7)
                            .fill(store.showBroadcast ? Theme.accentSoft : Color(hex: 0x17181B)))
                }
                .buttonStyle(.plain)
                .help("Seçili terminallere aynı anda yaz (⇧⌘B)")

                Menu {
                    Button("Otomatik") { store.setGridColumns(0) }
                    ForEach(1...4, id: \.self) { n in
                        Button("\(n) sütun") { store.setGridColumns(n) }
                    }
                } label: {
                    Image(systemName: "rectangle.split.3x1")
                }
                .menuStyle(.borderlessButton)
                .menuIndicator(.hidden)
                .fixedSize()
                .help("Sütun sayısı")

                LayoutSwitch()
            }
            .padding(.horizontal, 32)
            .padding(.top, 14)
            .padding(.bottom, 4)

            Group {
                if visible.isEmpty {
                    EmptyStateView()
                } else if store.layout == .focus {
                    FocusLayout(sessions: visible)
                } else {
                    GridLayout(sessions: visible)
                }
            }
            .padding(.horizontal, 24)

            if store.showBroadcast {
                BroadcastBar()
                    .overlay(alignment: .top) { Rectangle().fill(Theme.hairline).frame(height: 1) }
            }
        }
    }
}

struct LayoutSwitch: View {
    @Environment(AppStore.self) private var store

    var body: some View {
        HStack(spacing: 0) {
            segment("Izgara", .grid)
            segment("Odak", .focus)
        }
        .padding(3)
        .background(RoundedRectangle(cornerRadius: 9).fill(Color(hex: 0x17181B)))
        .overlay(RoundedRectangle(cornerRadius: 9).strokeBorder(Theme.border))
        .help("Izgara ↔ odak (⌘↩)")
    }

    private func segment(_ label: String, _ mode: LayoutMode) -> some View {
        let active = store.layout == mode
        return Button {
            if store.layout != mode { store.toggleLayout() }
        } label: {
            Text(label)
                .font(.system(size: 12))
                .foregroundStyle(active ? Color(hex: 0xE3E6FF) : Theme.secondary)
                .padding(.horizontal, 12)
                .frame(height: 26)
                .background(RoundedRectangle(cornerRadius: 7).fill(active ? Color(hex: 0x2A2C38) : .clear))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(active ? .isSelected : [])
    }
}

/// Tüm terminalleri eşit kutularda gösterir; sığmazsa dikey kaydırır.
struct GridLayout: View {
    @Environment(AppStore.self) private var store
    let sessions: [TerminalSession]
    private let spacing: CGFloat = 14
    private let minTileHeight: CGFloat = 240

    var body: some View {
        GeometryReader { geo in
            // Kutular en az ~380 pt genişlikte kalsın: dar pencerede sütun sayısı otomatik azalır
            let fit = max(1, Int((geo.size.width + spacing) / (380 + spacing)))
            let cols = max(1, min(store.effectiveColumns(for: sessions.count), fit))
            let rows = Int((Double(sessions.count) / Double(cols)).rounded(.up))
            let available = geo.size.height - spacing * CGFloat(rows + 1)
            let tileHeight = max(minTileHeight, available / CGFloat(max(rows, 1)))
            let totalHeight = tileHeight * CGFloat(rows) + spacing * CGFloat(rows + 1)

            ScrollView(.vertical) {
                VStack(spacing: spacing) {
                    ForEach(0..<rows, id: \.self) { row in
                        HStack(spacing: spacing) {
                            ForEach(0..<cols, id: \.self) { col in
                                let i = row * cols + col
                                if i < sessions.count {
                                    TerminalTile(session: sessions[i], index: i)
                                        .id(sessions[i].id)
                                } else {
                                    Color.clear
                                }
                            }
                        }
                        .frame(height: tileHeight)
                    }
                }
                .padding(.vertical, spacing)
                .padding(.horizontal, 8)
            }
            .scrollDisabled(totalHeight <= geo.size.height + 1)
        }
    }
}

/// Bir terminal büyük, diğerleri altta çipler.
struct FocusLayout: View {
    @Environment(AppStore.self) private var store
    let sessions: [TerminalSession]

    var body: some View {
        let focused = sessions.first { $0.id == store.focusedSessionID } ?? sessions[0]
        let index = sessions.firstIndex { $0 === focused } ?? 0

        VStack(spacing: 10) {
            TerminalTile(session: focused, index: index)
                .id(focused.id)
            if sessions.count > 1 {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(Array(sessions.enumerated()), id: \.element.id) { i, s in
                            SessionChip(session: s, index: i, isActive: s === focused)
                        }
                    }
                    .padding(.vertical, 1)
                }
            }
        }
        .padding(.vertical, 14)
        .padding(.horizontal, 8)
    }
}

struct SessionChip: View {
    @Environment(AppStore.self) private var store
    let session: TerminalSession
    let index: Int
    let isActive: Bool

    var body: some View {
        Button { store.focus(session) } label: {
            HStack(spacing: 8) {
                Circle().fill(session.dotColor).frame(width: 7, height: 7)
                KindMark(session: session, size: 18)
                Text(verbatim: session.name).lineLimit(1)
                if session.needsAttention {
                    Image(systemName: "bell.badge.fill").foregroundStyle(Theme.orange)
                }
                if index < 9 {
                    Text(verbatim: "⌘\(index + 1)").font(Theme.mono(10)).foregroundStyle(Color(hex: 0x5F626A))
                }
            }
            .font(.system(size: 12))
            .foregroundStyle(Theme.text)
            .padding(.horizontal, 10)
            .frame(height: 32)
            .background(Capsule().fill(isActive ? Theme.accentSoft : Theme.card))
            .overlay(Capsule().strokeBorder(session.needsAttention ? Theme.orange
                                            : (isActive ? Color(hex: 0x4A5190) : Theme.border)))
        }
        .buttonStyle(.plain)
        .contextMenu { SessionMenuItems(session: session) }
    }
}

struct EmptyStateView: View {
    @Environment(AppStore.self) private var store

    var body: some View {
        VStack(spacing: 14) {
            if let pid = store.filterProjectID, let project = store.project(pid) {
                Image(systemName: "terminal")
                    .font(.system(size: 38, weight: .light))
                    .foregroundStyle(Theme.tertiary)
                Text("Açık terminal yok")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(Theme.text)
                Text(project.commands.isEmpty
                     ? "Yukarıdan komut ekleyin ya da bir ajan/terminal açın."
                     : "Yukarıdaki komutlardan birini ▶ ile başlatın ya da bir ajan açın.")
                    .font(.system(size: 13))
                    .foregroundStyle(Theme.secondary)
                    .multilineTextAlignment(.center)
                HStack(spacing: 10) {
                    ForEach([SessionKind.claude, .codex, .shell]) { kind in
                        Button { store.quickNew(kind, projectID: project.id) } label: {
                            Label(kind.label, systemImage: kind.symbol)
                        }
                        .buttonStyle(GhostButtonStyle(height: 38))
                    }
                }
                .padding(.top, 4)
            } else {
                Image(systemName: "square.grid.2x2")
                    .font(.system(size: 38, weight: .light))
                    .foregroundStyle(Theme.tertiary)
                Text("Çalışan bir şey yok")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(Theme.text)
                Text("Panodan bir projeyi başlatın; komutları ve ajanları burada görürsünüz.")
                    .font(.system(size: 13))
                    .foregroundStyle(Theme.secondary)
                Button("Panoya dön") { store.openDashboard() }
                    .buttonStyle(GhostButtonStyle(height: 38))
                    .padding(.top, 4)
            }
        }
        .padding(40)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
