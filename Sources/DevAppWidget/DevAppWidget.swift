import WidgetKit
import SwiftUI

// MARK: - Veri

struct DevAppEntry: TimelineEntry {
    let date: Date
    let snapshot: WidgetSnapshot
    let isSample: Bool
    var problem: String? = nil
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
            return DevAppEntry(date: Date(), snapshot: snap, isSample: false)
        }
        return DevAppEntry(date: Date(), snapshot: .empty, isSample: false, problem: SharedStore.readProblem())
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
        .configurationDisplayName("Claude & Codex Kullanımı")
        .description("5 saatlik ve haftalık limitler, bugünkü token kullanımı.")
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
        .configurationDisplayName("DevApp Projeleri")
        .description("Çalışan projeler, açık portlar, sizi bekleyen ajanlar ve kullanım.")
        .supportedFamilies([.systemMedium, .systemLarge])
    }
}

// MARK: - Renkler

enum W {
    static let bg = Color(rgb: 0x0E0F11)
    static let card = Color(rgb: 0x17181B)
    static let track = Color(rgb: 0x2A2B30)
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
            HStack(spacing: 14) {
                ProviderColumn(usage: s.claude, label: "Claude", mark: "C", tint: W.claude)
                Rectangle().fill(W.track).frame(width: 1)
                ProviderColumn(usage: s.codex, label: "Codex", mark: "X", tint: W.codex)
            }
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
            ZStack {
                Circle().stroke(W.track, lineWidth: 7)
                if let p {
                    Circle()
                        .trim(from: 0, to: min(p, 100) / 100)
                        .stroke(W.level(p, tint: tint), style: StrokeStyle(lineWidth: 7, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                }
                VStack(spacing: 0) {
                    Text(verbatim: p.map { "\(Int($0.rounded()))" } ?? "—")
                        .font(.system(size: 18, weight: .bold, design: .rounded))
                        .foregroundStyle(W.text)
                    Text(verbatim: p == nil ? UsageFormat.tokens(usage?.todayTokens ?? 0) : "5 saat")
                        .font(.system(size: 8, weight: .medium))
                        .foregroundStyle(W.tertiary)
                }
            }
            .frame(width: 60, height: 60)
            Text(verbatim: label)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(tint)
            Text(verbatim: "hafta \(UsageFormat.percent(usage?.weeklyPercent))")
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

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack(spacing: 7) {
                Text(verbatim: mark)
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(tint)
                    .frame(width: 20, height: 20)
                    .background(RoundedRectangle(cornerRadius: 5).fill(tint.opacity(0.18)))
                Text(verbatim: label)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(W.text)
                Spacer(minLength: 2)
                Text(verbatim: UsageFormat.tokens(usage?.todayTokens ?? 0))
                    .font(.system(size: 11, weight: .semibold, design: .monospaced))
                    .foregroundStyle(W.secondary)
            }
            WidgetBar(title: "5 saat", percent: usage?.sessionPercent, resetsAt: usage?.sessionResetsAt, tint: tint)
            WidgetBar(title: "Hafta", percent: usage?.weeklyPercent, resetsAt: usage?.weeklyResetsAt, tint: tint)
            if usage?.sessionPercent == nil, let note = usage?.note {
                Text(verbatim: note)
                    .font(.system(size: 9))
                    .foregroundStyle(W.tertiary)
                    .lineLimit(1)
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
                Spacer(minLength: 2)
                Text(verbatim: UsageFormat.percent(percent))
                    .font(.system(size: 10, weight: .semibold, design: .monospaced))
                    .foregroundStyle(percent.map { W.level($0, tint: tint) } ?? W.tertiary)
                if let resetsAt, resetsAt > Date() {
                    Text(resetsAt, style: .relative)
                        .font(.system(size: 9, design: .monospaced))
                        .foregroundStyle(W.tertiary)
                        .lineLimit(1)
                        .frame(maxWidth: 58, alignment: .trailing)
                }
            }
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(W.track)
                    if let percent {
                        Capsule()
                            .fill(W.level(percent, tint: tint))
                            .frame(width: max(3, geo.size.width * min(percent, 100) / 100))
                    }
                }
            }
            .frame(height: 5)
        }
    }
}

// MARK: - Projeler widget'ı

struct ProjectsWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: DevAppEntry

    var body: some View {
        let s = entry.snapshot
        let ordered = s.projects.sorted { rank($0.state) < rank($1.state) }
        let limit = family == .systemLarge ? 6 : 3

        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Text("DevApp")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(W.text)
                let running = s.projects.filter { $0.state == "running" || $0.state == "attention" }.count
                Text(verbatim: "· \(running) çalışıyor")
                    .font(.system(size: 11))
                    .foregroundStyle(W.secondary)
                Spacer()
                if s.attention > 0 {
                    Link(destination: URL(string: "devapp://attention")!) {
                        HStack(spacing: 4) {
                            Image(systemName: "bell.fill").font(.system(size: 9))
                            Text(verbatim: "\(s.attention)").font(.system(size: 11, weight: .bold))
                        }
                        .foregroundStyle(Color(rgb: 0x1A1206))
                        .padding(.horizontal, 7)
                        .padding(.vertical, 2)
                        .background(Capsule().fill(W.orange))
                    }
                }
            }

            if ordered.isEmpty {
                Spacer()
                Text(verbatim: entry.isSample ? "" : (entry.problem ?? "DevApp'i açıp bir proje ekleyin"))
                    .font(.system(size: 11))
                    .foregroundStyle(W.secondary)
                Spacer()
            } else {
                VStack(spacing: 5) {
                    ForEach(ordered.prefix(limit)) { p in
                        Link(destination: URL(string: "devapp://project/\(p.id.uuidString)")!) {
                            ProjectRowView(project: p)
                        }
                    }
                }
                if ordered.count > limit {
                    Text(verbatim: "+\(ordered.count - limit) proje")
                        .font(.system(size: 10))
                        .foregroundStyle(W.tertiary)
                }
                Spacer(minLength: 0)
            }

            if family == .systemLarge {
                Rectangle().fill(W.track).frame(height: 1)
                HStack(spacing: 14) {
                    ProviderColumn(usage: s.claude, label: "Claude", mark: "C", tint: W.claude)
                    ProviderColumn(usage: s.codex, label: "Codex", mark: "X", tint: W.codex)
                }
            }
        }
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

struct ProjectRowView: View {
    let project: ProjectSnapshot

    var body: some View {
        HStack(spacing: 8) {
            Text(verbatim: project.initials)
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(Color(rgb: 0x0B0C10))
                .frame(width: 24, height: 24)
                .background(RoundedRectangle(cornerRadius: 7, style: .continuous).fill(Color(rgb: project.colorHex)))
                .opacity(project.state == "idle" ? 0.55 : 1)
            VStack(alignment: .leading, spacing: 0) {
                Text(verbatim: project.name)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(W.text)
                    .lineLimit(1)
                Text(verbatim: detail)
                    .font(.system(size: 9.5))
                    .foregroundStyle(W.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 4)
            ForEach(project.ports.prefix(2), id: \.self) { port in
                Text(verbatim: ":\(port)")
                    .font(.system(size: 9.5, weight: .medium, design: .monospaced))
                    .foregroundStyle(W.green)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 1)
                    .background(RoundedRectangle(cornerRadius: 4).fill(W.green.opacity(0.15)))
            }
            Circle().fill(dot).frame(width: 7, height: 7)
        }
        .padding(.horizontal, 7)
        .padding(.vertical, 4)
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
        case "attention": parts.append("sizi bekliyor")
        case "crashed": parts.append("hata")
        case "idle": parts.append("durdu")
        default: break
        }
        if project.runningCommands > 0 { parts.append("\(project.runningCommands) komut") }
        if project.agents > 0 { parts.append("\(project.agents) ajan") }
        return parts.isEmpty ? "çalışıyor" : parts.joined(separator: " · ")
    }
}

struct NoDataView: View {
    var problem: String? = nil

    var body: some View {
        VStack(spacing: 6) {
            Image(systemName: "chart.bar.xaxis")
                .font(.system(size: 20))
                .foregroundStyle(W.tertiary)
            Text("DevApp'i açın")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(W.text)
            Text(verbatim: problem ?? "Kullanım verisi uygulama açıkken güncellenir")
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
            ],
            attention: 1,
            claude: ProviderUsage(name: "Claude", sessionPercent: 42, sessionResetsAt: now.addingTimeInterval(7_800),
                                  weeklyPercent: 18, weeklyResetsAt: now.addingTimeInterval(300_000),
                                  todayTokens: 1_840_000, windowTokens: 620_000, lastActivity: now),
            codex: ProviderUsage(name: "Codex", sessionPercent: 12, sessionResetsAt: now.addingTimeInterval(14_000),
                                 weeklyPercent: 31, weeklyResetsAt: now.addingTimeInterval(410_000),
                                 todayTokens: 920_000, windowTokens: 310_000, lastActivity: now)
        )
    }
}
