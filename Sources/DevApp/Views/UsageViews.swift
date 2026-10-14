import SwiftUI

/// Panonun üstündeki Claude / Codex kullanım kartları
struct UsageStrip: View {
    @Environment(AppStore.self) private var store

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 16) { cards }
            VStack(spacing: 12) { cards }
        }
    }

    @ViewBuilder private var cards: some View {
        UsageCard(agent: .claude, usage: store.claudeUsage, health: store.agentHealth[.claude], fallbackName: "Claude",
                  tint: Theme.orange, tintBg: Theme.orangeBg)
            .frame(minWidth: 320)
        UsageCard(agent: .codex, usage: store.codexUsage, health: store.agentHealth[.codex], fallbackName: "Codex",
                  tint: Color(hex: 0x6EE7D8), tintBg: Color(hex: 0x123331))
            .frame(minWidth: 320)
    }
}

struct UsageCard: View {
    let agent: AgentKind
    let usage: ProviderUsage?
    var health: AgentHealth? = nil
    let fallbackName: String
    let tint: Color
    let tintBg: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                AgentLogo(agent: agent, size: 28)
                VStack(alignment: .leading, spacing: 1) {
                    Text(verbatim: usage?.name ?? fallbackName)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(Theme.textStrong)
                    Text(verbatim: connectionProblem ?? subtitle)
                        .font(.system(size: 11))
                        .foregroundStyle(connectionProblem == nil ? Theme.secondary : Theme.orange)
                        .lineLimit(1)
                }
                Spacer(minLength: 4)
                VStack(alignment: .trailing, spacing: 1) {
                    Text(verbatim: UsageFormat.tokens(usage?.todayTokens ?? 0))
                        .font(Theme.mono(14, weight: .semibold))
                        .foregroundStyle(Theme.text)
                    Text(L("bugün", "today"))
                        .font(.system(size: 10))
                        .foregroundStyle(Theme.tertiary)
                }
            }

            UsageBar(title: L("5 saat", "5 hours"), percent: usage?.sessionPercent, resetsAt: usage?.sessionResetsAt,
                     fallback: usage.map { L("\(UsageFormat.tokens($0.windowTokens)) token", "\(UsageFormat.tokens($0.windowTokens)) tokens") }, tint: tint)
            UsageBar(title: L("Haftalık", "Weekly"), percent: usage?.weeklyPercent, resetsAt: usage?.weeklyResetsAt,
                     fallback: nil, tint: tint)
            HourlyBars(values: usage?.hourly ?? [], tint: tint)
                .frame(height: 26)
                .help(L("Son 12 saat, saatlik token", "Last 12 hours, tokens per hour"))
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Theme.card))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(Theme.border))
        .help(connectionProblem.map { $0 + " — " + L("Ayarlar › Ajanlar", "Settings › Agents") } ?? usage?.note ?? "")
    }

    /// Ajan kurulu değilse ya da oturum açılmamışsa kartta uyarı
    private var connectionProblem: String? {
        guard let health, !health.isChecking else { return nil }
        if !health.isInstalled { return L("Kurulu değil", "Not installed") }
        if !health.isSignedIn { return L("Oturum açılmamış", "Not signed in") }
        return nil
    }

    private var subtitle: String {
        if let note = usage?.note { return note }
        guard let last = usage?.lastActivity else { return L("etkinlik yok", "no activity") }
        let mins = Int(Date().timeIntervalSince(last) / 60)
        if mins < 1 { return L("şu an etkin", "active now") }
        if mins < 60 { return L("\(mins) dk önce", "\(mins) min ago") }
        if mins < 1440 { return L("\(mins / 60) sa önce", "\(mins / 60) h ago") }
        return L("\(mins / 1440) gün önce", "\(mins / 1440) d ago")
    }
}

struct UsageBar: View {
    let title: String
    let percent: Double?
    let resetsAt: Date?
    let fallback: String?
    let tint: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 6) {
                Text(title)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(Color(hex: 0xA7AAB2))
                Spacer(minLength: 4)
                if let percent {
                    Text(verbatim: UsageFormat.percent(percent))
                        .font(Theme.mono(11, weight: .semibold))
                        .foregroundStyle(color(percent))
                    if let reset = UsageFormat.resetIn(resetsAt) {
                        Text(verbatim: "· \(reset)")
                            .font(Theme.mono(10.5))
                            .foregroundStyle(Theme.tertiary)
                    }
                } else {
                    Text(verbatim: fallback ?? "—")
                        .font(Theme.mono(11))
                        .foregroundStyle(Theme.secondary)
                }
            }
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color(hex: 0x24252A))
                    if let percent {
                        Capsule()
                            .fill(color(percent))
                            .frame(width: max(4, geo.size.width * min(percent, 100) / 100))
                    }
                }
            }
            .frame(height: 6)
        }
    }

    private func color(_ p: Double) -> Color {
        if p >= 90 { return Theme.red }
        if p >= 70 { return Theme.orange }
        return tint
    }
}

/// Son 12 saatin saatlik token grafiği
struct HourlyBars: View {
    let values: [Int]
    let tint: Color

    var body: some View {
        let data = values.isEmpty ? [Int](repeating: 0, count: 12) : values
        let peak = max(data.max() ?? 0, 1)
        GeometryReader { geo in
            HStack(alignment: .bottom, spacing: 3) {
                ForEach(Array(data.enumerated()), id: \.offset) { i, v in
                    RoundedRectangle(cornerRadius: 2)
                        .fill(v == 0 ? Color(hex: 0x24252A) : tint.opacity(i == data.count - 1 ? 1 : 0.7))
                        .frame(height: v == 0 ? 3 : max(4, geo.size.height * CGFloat(v) / CGFloat(peak)))
                        .help(Text(verbatim: L("\(12 - i) sa önce: \(UsageFormat.tokens(v)) token", "\(12 - i) h ago: \(UsageFormat.tokens(v)) tokens")))
                }
            }
            .frame(maxHeight: .infinity, alignment: .bottom)
        }
    }
}
