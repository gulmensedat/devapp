import WidgetKit
import SwiftUI
import AppKit
import AppIntents

// MARK: - Veri

struct DevAppEntry: TimelineEntry {
    let date: Date
    let snapshot: WidgetSnapshot
    let isSample: Bool
    var problem: String? = nil
    /// Projeler widget'ında gösterilen sayfa (oklarla değişir)
    var page: Int = 0
}

struct DevAppProvider: TimelineProvider {
    func placeholder(in context: Context) -> DevAppEntry {
        DevAppEntry(date: Date(), snapshot: .sample, isSample: true)
    }

    func getSnapshot(in context: Context, completion: @escaping (DevAppEntry) -> Void) {
        if context.isPreview {
            completion(DevAppEntry(date: Date(), snapshot: .sample, isSample: true))
        } else {
            completion(current())
        }
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<DevAppEntry>) -> Void) {
        // DevApp açıkken değişiklikte widget'ı kendisi yeniler; bu yalnızca yedek tazeleme
        let next = Date().addingTimeInterval(15 * 60)
        completion(Timeline(entries: [current()], policy: .after(next)))
    }

    private func current() -> DevAppEntry {
        if let snap = SharedStore.read() {
            // Widget, uygulamada seçilen dili kullanır
            LanguageStore.shared.applyResolved(snap.language)
            return DevAppEntry(date: Date(), snapshot: snap, isSample: false, page: WidgetPager.page)
        }
        return DevAppEntry(date: Date(), snapshot: .empty, isSample: false, problem: SharedStore.readProblem())
    }
}

// MARK: - Sayfalama (widget'larda kaydırma yok; oklarla sayfa değiştirilir)

enum WidgetPager {
    private static let key = "projectsPage"
    private static var defaults: UserDefaults {
        SharedStore.groupID.flatMap { UserDefaults(suiteName: $0) } ?? .standard
    }

    static var page: Int { defaults.integer(forKey: key) }

    static func shift(by delta: Int) {
        defaults.set(page + delta, forKey: key)
    }

    /// Kayıtlı sayfa numarasını sayfa sayısına göre sarmalar
    static func clamp(_ page: Int, count: Int) -> Int {
        guard count > 0 else { return 0 }
        return ((page % count) + count) % count
    }
}

struct ProjectsPageIntent: AppIntent {
    static var title: LocalizedStringResource = "Projects page"
    static var isDiscoverable: Bool = false

    @Parameter(title: "Delta") var delta: Int

    init() { delta = 1 }
    init(delta: Int) { self.delta = delta }

    func perform() async throws -> some IntentResult {
        WidgetPager.shift(by: delta)
        return .result()
    }
}

// MARK: - Widget'lar

@main
struct DevAppWidgets: WidgetBundle {
    var body: some Widget {
        UsageWidget()
        ProjectsWidget()
    }
}

struct UsageWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "DevAppUsage", provider: DevAppProvider()) { entry in
            UsageWidgetView(entry: entry)
                .containerBackground(for: .widget) { W.bg }
                .widgetURL(URL(string: "devapp://dashboard"))
        }
        .configurationDisplayName(L("Claude & Codex Kullanımı", "Claude & Codex Usage"))
        .description(L("5 saatlik ve haftalık limitler, bugünkü token kullanımı.", "5-hour and weekly limits, today’s token usage."))
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

struct ProjectsWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "DevAppProjects", provider: DevAppProvider()) { entry in
            ProjectsWidgetView(entry: entry)
                .containerBackground(for: .widget) { W.bg }
                .widgetURL(URL(string: "devapp://dashboard"))
        }
        .configurationDisplayName(L("DevApp Projeleri", "DevApp Projects"))
        .description(L("Çalışan projeler, açık portlar, sizi bekleyen ajanlar ve kullanım.", "Running projects, open ports, agents waiting for you and usage."))
        .supportedFamilies([.systemMedium, .systemLarge])
    }
}

// MARK: - Renkler

enum W {
    static let bg = Color(rgb: 0x0E0F11)
    static let card = Color.white.opacity(0.06)
    /// Açık renkli yarı saydam iz: hem tam renkli hem "tek renk" (vibrant) masaüstü modunda görünür
    static let track = Color.white.opacity(0.16)
    static let text = Color(rgb: 0xE9E9EC)
    static let secondary = Color(rgb: 0x9A9DA6)
    static let tertiary = Color(rgb: 0x6F727A)
    static let green = Color(rgb: 0x5BE39A)
    static let orange = Color(rgb: 0xFFB86B)
    static let red = Color(rgb: 0xFF8A7A)
    static let claude = Color(rgb: 0xFFB86B)
    static let codex = Color(rgb: 0x6EE7D8)

    static func level(_ p: Double, tint: Color) -> Color {
        if p >= 90 { return red }
        if p >= 70 { return orange }
        return tint
    }
}

/// macOS masaüstünde widget'lar arka plandayken "tek renk" (vibrant) çizilir;
/// o modda koyu renkler kaybolur, bu yüzden dolgular birincil renge çevrilir.
struct ModeAwareFill: ViewModifier {
    @Environment(\.widgetRenderingMode) private var mode
    let color: Color

    func body(content: Content) -> some View {
        content.foregroundStyle(mode == .fullColor ? color : Color.primary)
    }
}

extension View {
    func modeFill(_ color: Color) -> some View { modifier(ModeAwareFill(color: color)) }
}

/// Son 12 saatin saatlik token grafiği
struct MiniBars: View {
    let values: [Int]
    let tint: Color

    var body: some View {
        let data = values.isEmpty ? [Int](repeating: 0, count: 12) : values
        let peak = max(data.max() ?? 0, 1)
        GeometryReader { geo in
            HStack(alignment: .bottom, spacing: 2) {
                ForEach(Array(data.enumerated()), id: \.offset) { i, v in
                    let h = v == 0 ? 2 : max(3, geo.size.height * CGFloat(v) / CGFloat(peak))
                    RoundedRectangle(cornerRadius: 1.5)
                        .modeFill(v == 0 ? W.track : tint.opacity(i == data.count - 1 ? 1 : 0.75))
                        .frame(height: h)
                        .widgetAccentable()
                }
            }
            .frame(maxHeight: .infinity, alignment: .bottom)
        }
    }
}

extension Color {
    init(rgb: UInt32) {
        self.init(.sRGB,
                  red: Double((rgb >> 16) & 0xFF) / 255,
                  green: Double((rgb >> 8) & 0xFF) / 255,
                  blue: Double(rgb & 0xFF) / 255,
                  opacity: 1)
    }
}

// MARK: - Kullanım widget'ı

struct UsageWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: DevAppEntry

    var body: some View {
        let s = entry.snapshot
        if s.claude == nil && s.codex == nil && !entry.isSample {
            NoDataView(problem: entry.problem)
        } else if family == .systemSmall {
            HStack(spacing: 10) {
                UsageRing(usage: s.claude, label: "Claude", tint: W.claude)
                UsageRing(usage: s.codex, label: "Codex", tint: W.codex)
            }
        } else {
            HStack(alignment: .center, spacing: 14) {
                ProviderColumn(usage: s.claude, label: "Claude", mark: "C", tint: W.claude)
                Rectangle().fill(W.track).frame(width: 1)
                ProviderColumn(usage: s.codex, label: "Codex", mark: "X", tint: W.codex)
            }
            .frame(maxHeight: .infinity)
        }
    }
}

/// 5 saatlik kullanım halkası + haftalık yüzde
struct UsageRing: View {
    let usage: ProviderUsage?
    let label: String
    let tint: Color

    var body: some View {
        let p = usage?.sessionPercent
        VStack(spacing: 6) {
            if let p {
                ZStack {
                    Circle().stroke(W.track, lineWidth: 7)
                    Circle()
                        .trim(from: 0, to: max(0.02, min(p, 100) / 100))
                        .stroke(style: StrokeStyle(lineWidth: 7, lineCap: .round))
                        .modeFill(W.level(p, tint: tint))
                        .rotationEffect(.degrees(-90))
                        .widgetAccentable()
                    VStack(spacing: 0) {
                        Text(verbatim: "\(Int(p.rounded()))")
                            .font(.system(size: 18, weight: .bold, design: .rounded))
                            .foregroundStyle(W.text)
                        Text(verbatim: L("5 saat", "5 hours"))
                            .font(.system(size: 8, weight: .medium))
                            .foregroundStyle(W.tertiary)
                    }
                }
                .frame(width: 60, height: 60)
            } else {
                // Plan yüzdesi yok: bugünkü token + saatlik grafik
                VStack(spacing: 4) {
                    Text(verbatim: UsageFormat.tokens(usage?.todayTokens ?? 0))
                        .font(.system(size: 17, weight: .bold, design: .rounded))
                        .foregroundStyle(W.text)
                    MiniBars(values: usage?.hourly ?? [], tint: tint)
                        .frame(height: 30)
                }
                .frame(width: 64, height: 60)
            }
            HStack(spacing: 4) {
                AgentBadge(name: label.lowercased(), mark: String(label.prefix(1)), tint: tint, size: 13)
                Text(verbatim: label)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(tint)
            }
            Text(verbatim: L("hafta \(UsageFormat.percent(usage?.weeklyPercent))", "week \(UsageFormat.percent(usage?.weeklyPercent))"))
                .font(.system(size: 9.5, design: .monospaced))
                .foregroundStyle(W.secondary)
        }
        .frame(maxWidth: .infinity)
    }
}

struct ProviderColumn: View {
    let usage: ProviderUsage?
    let label: String
    let mark: String
    let tint: Color
    /// Projeler widget'ının altında: grafik ve not yok, aralıklar dar
    var compact = false

    var body: some View {
        VStack(alignment: .leading, spacing: compact ? 6 : 8) {
            HStack(spacing: 7) {
                AgentBadge(name: label.lowercased(), mark: mark, tint: tint, size: 20)
                Text(verbatim: label)
                    .font(.system(size: compact ? 12 : 13, weight: .semibold))
                    .foregroundStyle(W.text)
                    .lineLimit(1)
                Spacer(minLength: 2)
                Text(verbatim: UsageFormat.tokens(usage?.todayTokens ?? 0))
                    .font(.system(size: 11, weight: .semibold, design: .monospaced))
                    .foregroundStyle(W.secondary)
                    .fixedSize()
            }
            WidgetBar(title: L("5 saat", "5 hours"), percent: usage?.sessionPercent, resetsAt: usage?.sessionResetsAt, tint: tint)
            WidgetBar(title: L("Hafta", "Week"), percent: usage?.weeklyPercent, resetsAt: usage?.weeklyResetsAt, tint: tint)
            if !compact {
                MiniBars(values: usage?.hourly ?? [], tint: tint)
                    .frame(height: 16)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct WidgetBar: View {
    let title: String
    let percent: Double?
    let resetsAt: Date?
    let tint: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 4) {
                Text(verbatim: title)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(W.secondary)
                    .lineLimit(1)
                Spacer(minLength: 2)
                Text(verbatim: UsageFormat.percent(percent))
                    .font(.system(size: 10, weight: .semibold, design: .monospaced))
                    .foregroundStyle(percent.map { W.level($0, tint: tint) } ?? W.tertiary)
                    .fixedSize()
                if let reset = UsageFormat.resetIn(resetsAt) {
                    Text(verbatim: "· " + reset)
                        .font(.system(size: 9, design: .monospaced))
                        .foregroundStyle(W.tertiary)
                        .lineLimit(1)
                        .fixedSize()
                }
            }
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(W.track)
                    if let percent {
                        Capsule()
                            .modeFill(W.level(percent, tint: tint))
                            .frame(width: max(3, geo.size.width * min(percent, 100) / 100))
                            .widgetAccentable()
                    }
                }
            }
            .frame(height: 5)
        }
    }
}

/// Claude / Codex logosu: uygulamanın App Group'a yazdığı ikon, yoksa harf
struct AgentBadge: View {
    let name: String
    let mark: String
    let tint: Color
    var size: CGFloat = 20

    var body: some View {
        if let url = SharedStore.agentIconURL(name), let image = NSImage(contentsOf: url) {
            Image(nsImage: image)
                .resizable()
                .interpolation(.high)
                .aspectRatio(contentMode: .fit)
                .frame(width: size, height: size)
        } else {
            Text(verbatim: mark)
                .font(.system(size: size * 0.5, weight: .bold))
                .foregroundStyle(tint)
                .frame(width: size, height: size)
                .background(RoundedRectangle(cornerRadius: size * 0.25).fill(tint.opacity(0.18)))
        }
    }
}

// MARK: - Projeler widget'ı

struct ProjectsWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: DevAppEntry

    private static let rowHeight: CGFloat = 30
    private static let rowSpacing: CGFloat = 4
    private static let headerHeight: CGFloat = 20
    /// Büyük boyutta alttaki kullanım bölümünün yüksekliği (çizgi + iki sütun)
    private static let usageHeight: CGFloat = 86

    var body: some View {
        // Satır sayısı widget'ın gerçek yüksekliğinden hesaplanır; böylece hiçbir boyutta kesilmez
        GeometryReader { geo in
            content(height: geo.size.height)
        }
    }

    private func rowsPerPage(height: CGFloat) -> Int {
        var avail = height - Self.headerHeight - 6
        if family == .systemLarge { avail -= Self.usageHeight + 8 }
        return max(1, Int((avail + Self.rowSpacing) / (Self.rowHeight + Self.rowSpacing)))
    }

    @ViewBuilder
    private func content(height: CGFloat) -> some View {
        let s = entry.snapshot
        let ordered = s.projects.sorted { rank($0.state) < rank($1.state) }
        let rows = rowsPerPage(height: height)
        let pageCount = max(1, (ordered.count + rows - 1) / rows)
        let page = WidgetPager.clamp(entry.page, count: pageCount)
        let visible = Array(ordered.dropFirst(page * rows).prefix(rows))

        VStack(alignment: .leading, spacing: 6) {
            header(s, page: page, pageCount: pageCount)

            if ordered.isEmpty {
                Spacer(minLength: 0)
                Text(verbatim: entry.isSample ? "" : (entry.problem ?? L("DevApp'i açıp bir proje ekleyin", "Open DevApp and add a project")))
                    .font(.system(size: 11))
                    .foregroundStyle(W.secondary)
                    .frame(maxWidth: .infinity)
                Spacer(minLength: 0)
            } else {
                VStack(spacing: Self.rowSpacing) {
                    ForEach(visible) { p in
                        Link(destination: URL(string: "devapp://project/\(p.id.uuidString)")!) {
                            ProjectRowView(project: p, maxPorts: family == .systemLarge ? 2 : 1)
                        }
                    }
                }
                Spacer(minLength: 0)
            }

            if family == .systemLarge {
                VStack(spacing: 8) {
                    Rectangle().fill(W.track).frame(height: 1)
                    HStack(alignment: .top, spacing: 14) {
                        ProviderColumn(usage: s.claude, label: "Claude", mark: "C", tint: W.claude, compact: true)
                        ProviderColumn(usage: s.codex, label: "Codex", mark: "X", tint: W.codex, compact: true)
                    }
                }
                .frame(height: Self.usageHeight, alignment: .top)
            }
        }
        .frame(width: nil, height: height, alignment: .top)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func header(_ s: WidgetSnapshot, page: Int, pageCount: Int) -> some View {
        HStack(spacing: 6) {
            Text(verbatim: "DevApp")
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(W.text)
                .fixedSize()
            let running = s.projects.filter { $0.state == "running" || $0.state == "attention" }.count
            Text(verbatim: L("· \(running) çalışıyor", "· \(running) running"))
                .font(.system(size: 11))
                .foregroundStyle(W.secondary)
                .lineLimit(1)
            Spacer(minLength: 4)
            if s.attention > 0 {
                Link(destination: URL(string: "devapp://attention")!) {
                    HStack(spacing: 3) {
                        Image(systemName: "bell.fill").font(.system(size: 9))
                        Text(verbatim: "\(s.attention)").font(.system(size: 11, weight: .bold))
                    }
                    .foregroundStyle(Color(rgb: 0x1A1206))
                    .padding(.horizontal, 7)
                    .frame(height: 18)
                    .background(Capsule().fill(W.orange))
                    .fixedSize()
                }
            }
            if pageCount > 1 {
                PagerControl(page: page, pageCount: pageCount)
            }
        }
        .frame(height: Self.headerHeight)
    }

    private func rank(_ state: String) -> Int {
        switch state {
        case "attention": return 0
        case "running": return 1
        case "crashed": return 2
        default: return 3
        }
    }
}

/// ‹ 1/3 › — widget'ta kaydırma olmadığı için sayfalar arasında geçiş
struct PagerControl: View {
    let page: Int
    let pageCount: Int

    var body: some View {
        HStack(spacing: 2) {
            Button(intent: ProjectsPageIntent(delta: -1)) {
                Image(systemName: "chevron.left")
                    .font(.system(size: 9, weight: .bold))
                    .frame(width: 18, height: 18)
                    .background(Circle().fill(W.card))
            }
            .buttonStyle(.plain)
            Text(verbatim: "\(page + 1)/\(pageCount)")
                .font(.system(size: 10, weight: .medium, design: .monospaced))
                .foregroundStyle(W.secondary)
                .fixedSize()
            Button(intent: ProjectsPageIntent(delta: 1)) {
                Image(systemName: "chevron.right")
                    .font(.system(size: 9, weight: .bold))
                    .frame(width: 18, height: 18)
                    .background(Circle().fill(W.card))
            }
            .buttonStyle(.plain)
        }
        .foregroundStyle(W.text)
        .fixedSize()
    }
}

struct ProjectRowView: View {
    let project: ProjectSnapshot
    var maxPorts = 2

    var body: some View {
        HStack(spacing: 8) {
            if project.hasIcon == true, let url = SharedStore.iconURL(for: project.id),
               let image = NSImage(contentsOf: url) {
                Image(nsImage: image)
                    .resizable()
                    .interpolation(.high)
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 24, height: 24)
                    .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
                    .opacity(project.state == "idle" ? 0.6 : 1)
            } else {
            Text(verbatim: project.initials)
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(Color(rgb: 0x0B0C10))
                .frame(width: 24, height: 24)
                .background(RoundedRectangle(cornerRadius: 7, style: .continuous).modeFill(Color(rgb: project.colorHex)))
                .opacity(project.state == "idle" ? 0.55 : 1)
            }
            VStack(alignment: .leading, spacing: 0) {
                Text(verbatim: project.name)
                    .truncationMode(.tail)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(W.text)
                    .lineLimit(1)
                Text(verbatim: detail)
                    .font(.system(size: 9.5))
                    .foregroundStyle(W.secondary)
                    .lineLimit(1)
            }
            .layoutPriority(1)
            Spacer(minLength: 4)
            ForEach(project.ports.prefix(maxPorts), id: \.self) { port in
                Text(verbatim: ":\(port)")
                    .font(.system(size: 9.5, weight: .medium, design: .monospaced))
                    .foregroundStyle(W.green)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 1)
                    .background(RoundedRectangle(cornerRadius: 4).fill(W.green.opacity(0.15)))
                    .fixedSize()
            }
            Circle().fill(dot).frame(width: 7, height: 7)
        }
        .padding(.horizontal, 7)
        .frame(height: 30)
        .background(RoundedRectangle(cornerRadius: 9, style: .continuous).fill(W.card))
    }

    private var dot: Color {
        switch project.state {
        case "attention": return W.orange
        case "running": return W.green
        case "crashed": return W.red
        default: return W.tertiary
        }
    }

    private var detail: String {
        var parts: [String] = []
        switch project.state {
        case "attention": parts.append(L("sizi bekliyor", "waiting for you"))
        case "crashed": parts.append(L("hata", "error"))
        case "idle": parts.append(L("durdu", "stopped"))
        default: break
        }
        if project.runningCommands > 0 { parts.append(L("\(project.runningCommands) komut", "\(project.runningCommands) commands")) }
        if project.agents > 0 { parts.append(L("\(project.agents) ajan", "\(project.agents) agents")) }
        return parts.isEmpty ? L("çalışıyor", "running") : parts.joined(separator: " · ")
    }
}

struct NoDataView: View {
    var problem: String? = nil

    var body: some View {
        VStack(spacing: 6) {
            Image(systemName: "chart.bar.xaxis")
                .font(.system(size: 20))
                .foregroundStyle(W.tertiary)
            Text(L("DevApp'i açın", "Open DevApp"))
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(W.text)
            Text(verbatim: problem ?? L("Kullanım verisi uygulama açıkken güncellenir", "Usage data updates while DevApp is open"))
                .font(.system(size: 10))
                .foregroundStyle(W.secondary)
                .multilineTextAlignment(.center)
        }
    }
}

// MARK: - Örnek veri (widget galerisi için)

extension WidgetSnapshot {
    static var sample: WidgetSnapshot {
        let now = Date()
        return WidgetSnapshot(
            updatedAt: now,
            projects: [
                ProjectSnapshot(id: UUID(), name: "web-panel", initials: "WP", colorHex: 0xFF9A5A,
                                state: "attention", runningCommands: 2, agents: 1, ports: [5173, 3322]),
                ProjectSnapshot(id: UUID(), name: "devapp", initials: "DE", colorHex: 0x8E9BFF,
                                state: "running", runningCommands: 1, agents: 0, ports: []),
                ProjectSnapshot(id: UUID(), name: "mobil-app", initials: "MA", colorHex: 0x43D9B8,
                                state: "idle", runningCommands: 0, agents: 0, ports: []),
                ProjectSnapshot(id: UUID(), name: "api-gateway", initials: "AG", colorHex: 0xF5D76E,
                                state: "idle", runningCommands: 0, agents: 0, ports: []),
            ],
            attention: 1,
            claude: ProviderUsage(name: "Claude", sessionPercent: 42, sessionResetsAt: now.addingTimeInterval(7_800),
                                  weeklyPercent: 18, weeklyResetsAt: now.addingTimeInterval(300_000),
                                  todayTokens: 1_840_000, windowTokens: 620_000, lastActivity: now,
                                  hourly: [0, 40, 120, 80, 0, 0, 30, 200, 260, 140, 90, 180].map { $0 * 1000 }),
            codex: ProviderUsage(name: "Codex", sessionPercent: 12, sessionResetsAt: now.addingTimeInterval(14_000),
                                 weeklyPercent: 31, weeklyResetsAt: now.addingTimeInterval(410_000),
                                 todayTokens: 920_000, windowTokens: 310_000, lastActivity: now,
                                 hourly: [10, 0, 0, 60, 90, 40, 0, 0, 70, 110, 30, 50].map { $0 * 1000 })
        )
    }
}
