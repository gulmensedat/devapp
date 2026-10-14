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
        UsageCard(usage: store.claudeUsage, fallbackName: "Claude", mark: "C",
                  tint: Theme.orange, tintBg: Theme.orangeBg)
            .frame(minWidth: 320)
        UsageCard(usage: store.codexUsage, fallbackName: "Codex", mark: "X",
                  tint: Color(hex: 0x6EE7D8), tintBg: Color(hex: 0x123331))
            .frame(minWidth: 320)
    }
}

struct UsageCard: View {
    let usage: ProviderUsage?
    let fallbackName: String
    let mark: String
    let tint: Color
    let tintBg: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                Text(verbatim: mark)
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(tint)
                    .frame(width: 26, height: 26)
                    .background(RoundedRectangle(cornerRadius: 7, style: .continuous).fill(tintBg))
                VStack(alignment: .leading, spacing: 1) {
                    Text(verbatim: usage?.name ?? fallbackName)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(Theme.textStrong)
                    Text(verbatim: subtitle)
                        .font(.system(size: 11))
                        .foregroundStyle(Theme.secondary)
                        .lineLimit(1)
                }
                Spacer(minLength: 4)
                VStack(alignment: .trailing, spacing: 1) {
                    Text(verbatim: UsageFormat.tokens(usage?.todayTokens ?? 0))
                        .font(Theme.mono(14, weight: .semibold))
                        .foregroundStyle(Theme.text)
                    Text("bugün")
                        .font(.system(size: 10))
                        .foregroundStyle(Theme.tertiary)
                }
            }

            UsageBar(title: "5 saat", percent: usage?.sessionPercent, resetsAt: usage?.sessionResetsAt,
                     fallback: usage.map { "\(UsageFormat.tokens($0.windowTokens)) token" }, tint: tint)
            UsageBar(title: "Haftalık", percent: usage?.weeklyPercent, resetsAt: usage?.weeklyResetsAt,
                     fallback: nil, tint: tint)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Theme.card))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(Theme.border))
        .help(usage?.note ?? "")
    }

    private var subtitle: String {
        if let note = usage?.note { return note }
        guard let last = usage?.lastActivity else { return "etkinlik yok" }
        let mins = Int(Date().timeIntervalSince(last) / 60)
        if mins < 1 { return "şu an etkin" }
        if mins < 60 { return "\(mins) dk önce" }
        if mins < 1440 { return "\(mins / 60) sa önce" }
        return "\(mins / 1440) gün önce"
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
