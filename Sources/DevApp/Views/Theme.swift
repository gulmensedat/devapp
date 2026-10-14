import SwiftUI
import AppKit

/// Uygulamanın görsel dili: koyu zemin, proje başına bir renk, Geist benzeri sistem yazısı.
enum Theme {
    static let bg = Color(hex: 0x0E0F11)
    static let rail = Color(hex: 0x0A0B0C)
    static let panel = Color(hex: 0x121316)
    static let card = Color(hex: 0x16171A)
    static let raised = Color(hex: 0x1C1D21)
    static let terminalHeader = Color(hex: 0x141518)
    static let border = Color(hex: 0x24252A)
    static let hairline = Color(hex: 0x1E1F23)

    static let text = Color(hex: 0xE9E9EC)
    static let textStrong = Color(hex: 0xF2F2F4)
    static let secondary = Color(hex: 0x9A9DA6)
    static let tertiary = Color(hex: 0x6F727A)

    static let accent = Color(hex: 0x7C8CFF)
    static let accentSoft = Color(hex: 0x24263A)

    static let green = Color(hex: 0x5BE39A)
    static let greenBg = Color(hex: 0x13291D)
    static let orange = Color(hex: 0xFFB86B)
    static let orangeBg = Color(hex: 0x3A2614)
    static let red = Color(hex: 0xFF8A7A)
    static let redBg = Color(hex: 0x35191A)
    static let ink = Color(hex: 0x0B0C10)

    /// Projelere sırayla verilen renkler
    static let projectPalette: [UInt32] = [
        0x8E9BFF, 0xFF9A5A, 0x43D9B8, 0xF5C451, 0xF07AB0, 0x6EC6FF, 0xB38CFF, 0x9BD66B,
    ]

    static func mono(_ size: CGFloat, weight: Font.Weight = .regular) -> Font {
        .system(size: size, weight: weight, design: .monospaced)
    }
}

extension Color {
    init(hex: UInt32, opacity: Double = 1) {
        self.init(.sRGB,
                  red: Double((hex >> 16) & 0xFF) / 255,
                  green: Double((hex >> 8) & 0xFF) / 255,
                  blue: Double(hex & 0xFF) / 255,
                  opacity: opacity)
    }
}

extension Project {
    /// İsimden kararlı renk (Swift'in hashValue'su her açılışta değişir, djb2 kullanılır).
    var accentHex: UInt32 {
        if let colorIndex, Theme.projectPalette.indices.contains(colorIndex) {
            return Theme.projectPalette[colorIndex]
        }
        var h: UInt32 = 5381
        for b in name.utf8 { h = (h &* 33) &+ UInt32(b) }
        return Theme.projectPalette[Int(h % UInt32(Theme.projectPalette.count))]
    }

    var accent: Color { Color(hex: accentHex) }

    /// "web-panel" → "WP", "devapp" → "DE"
    var initials: String {
        let parts = name.split(whereSeparator: { "-_ .".contains($0) }).filter { !$0.isEmpty }
        if parts.count >= 2 {
            return parts.prefix(2).compactMap { part in part.first.map { String($0) } }.joined().uppercased()
        }
        return String(name.prefix(2)).uppercased()
    }
}

/// Proje harf ikonu
struct ProjectAvatar: View {
    let project: Project
    var size: CGFloat = 40
    var dimmed = false

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: size * 0.28, style: .continuous)
        Group {
            if let image = AppStore.shared.projectIcons[project.id] {
                // Projenin kendi logosu / uygulama ikonu
                Image(nsImage: image)
                    .resizable()
                    .interpolation(.high)
                    .aspectRatio(contentMode: .fit)
                    .padding(size * 0.06)
                    .frame(width: size, height: size)
                    .background(shape.fill(Color(hex: 0x1C1D21)))
                    .clipShape(shape)
                    .overlay(shape.strokeBorder(project.accent.opacity(0.35), lineWidth: 1))
            } else {
                Text(verbatim: project.initials)
                    .font(.system(size: size * 0.36, weight: .bold))
                    .foregroundStyle(Theme.ink)
                    .frame(width: size, height: size)
                    .background(shape.fill(project.accent))
            }
        }
        .opacity(dimmed ? 0.55 : 1)
    }
}

/// Renkli nokta + metin hap rozeti
struct StatusPill: View {
    let text: String
    let fg: Color
    let bg: Color

    var body: some View {
        HStack(spacing: 6) {
            Circle().fill(fg).frame(width: 7, height: 7)
            Text(text).font(.system(size: 12, weight: .semibold))
        }
        .foregroundStyle(fg)
        .padding(.horizontal, 10)
        .frame(height: 26)
        .background(Capsule().fill(bg))
    }
}

/// ▶ / ■ kare düğme — sabit boyutlu, durum değişince yerleşim kaymaz
struct PlayStopButton: View {
    let running: Bool
    var size: CGFloat = 28
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            ZStack {
                RoundedRectangle(cornerRadius: size * 0.28, style: .continuous)
                    .fill(running ? Color(hex: 0x3A1E1E) : Theme.greenBg)
                RoundedRectangle(cornerRadius: size * 0.28, style: .continuous)
                    .strokeBorder((running ? Theme.red : Theme.green).opacity(hovering ? 0.6 : 0), lineWidth: 1)
                Image(systemName: running ? "stop.fill" : "play.fill")
                    .font(.system(size: size * 0.36, weight: .bold))
                    .foregroundStyle(running ? Theme.red : Theme.green)
                    // ▶ üçgeni görsel olarak sola kaçık durur; optik olarak ortala
                    .offset(x: running ? 0 : size * 0.04)
            }
            .frame(width: size, height: size)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .fixedSize()
        .onHover { hovering = $0 }
        .help(running ? L("Durdur", "Stop") : L("Çalıştır", "Run"))
        .accessibilityLabel(running ? L("Durdur", "Stop") : L("Çalıştır", "Run"))
    }
}

/// Koyu, ince çerçeveli ikincil düğme
struct GhostButtonStyle: ButtonStyle {
    var height: CGFloat = 36

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 13, weight: .medium))
            .foregroundStyle(Theme.text)
            .padding(.horizontal, 12)
            .frame(minWidth: height, minHeight: height)
            .background(RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(configuration.isPressed ? Theme.border : Theme.raised))
            .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(Color(hex: 0x2A2B30)))
            .contentShape(Rectangle())
    }
}

/// Büyük Başlat / Durdur hap düğmesi — iki durumda da aynı genişlik (yanındakiler kaymasın)
struct PrimaryRunButton: View {
    let running: Bool
    let color: Color
    var height: CGFloat = 40
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 7) {
                Image(systemName: running ? "stop.fill" : "play.fill")
                    .font(.system(size: 11, weight: .bold))
                    .frame(width: 12)
                Text(running ? L("Durdur", "Stop") : L("Başlat", "Start"))
                    .font(.system(size: 13, weight: .semibold))
                    .lineLimit(1)
            }
            .foregroundStyle(running ? Theme.textStrong : Theme.ink)
            .frame(width: 104, height: height)
            .background(Capsule().fill(running ? Color(hex: 0x2A2B30) : color))
            .overlay(Capsule().strokeBorder(running ? Color(hex: 0x3A3B42) : .clear))
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .fixedSize()
    }
}

/// Terminal çıktı satırını kabaca renklendirir (önizlemeler için).
enum LineTint {
    static func color(for line: String) -> Color {
        let l = line.lowercased()
        if l.hasPrefix("$ ") || l.hasPrefix("> ") { return Theme.tertiary }
        if l.contains("error") || l.contains("failed") || l.contains("eaddrinuse") || l.contains("hata")
            || l.contains("panic") || l.contains("exception") { return Color(hex: 0xFF7A6B) }
        if l.contains("warn") || l.contains("uyarı") || l.contains("bekliyor") || l.contains("(y/n)") { return Theme.orange }
        if l.contains("ready") || l.contains("listening") || l.contains("passed") || l.contains("success")
            || l.contains("compiled") || l.contains("build complete") || l.contains("✓") || l.contains("local:") {
            return Theme.green
        }
        return Color(hex: 0xC9CBD1)
    }
}

/// Sığmayan öğeleri bir alt satıra kaydıran yerleşim (komut düğmeleri, filtreler)
struct FlowLayout: Layout {
    var spacing: CGFloat = 8
    var lineSpacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxWidth = proposal.width ?? .infinity
        var x: CGFloat = 0, y: CGFloat = 0, lineHeight: CGFloat = 0, widest: CGFloat = 0
        for sub in subviews {
            let size = sub.sizeThatFits(.unspecified)
            if x > 0, x + size.width > maxWidth {
                y += lineHeight + lineSpacing
                x = 0
                lineHeight = 0
            }
            x += size.width + spacing
            lineHeight = max(lineHeight, size.height)
            widest = max(widest, x - spacing)
        }
        return CGSize(width: proposal.width ?? widest, height: y + lineHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX, y = bounds.minY, lineHeight: CGFloat = 0
        for sub in subviews {
            let size = sub.sizeThatFits(.unspecified)
            if x > bounds.minX, x + size.width > bounds.maxX {
                y += lineHeight + lineSpacing
                x = bounds.minX
                lineHeight = 0
            }
            sub.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
            x += size.width + spacing
            lineHeight = max(lineHeight, size.height)
        }
    }
}
