import RainforestCore
import SwiftUI

/// Subscription limits per provider, like CodexBar: one bar per window with reset countdown.
struct LimitsSection: View {
    @Bindable var store: UsageStore

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Abo-Limits").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
            self.providerBlock(.codex, limits: self.store.codexLimits) {
                Text("Keine Limits in den Codex-Logs der letzten 30 Tage.")
            }
            self.claudeBlock
        }
    }

    @ViewBuilder
    private var claudeBlock: some View {
        if !self.store.claudeLimitsEnabled {
            VStack(alignment: .leading, spacing: 4) {
                Text("Claude Code").font(.caption.weight(.semibold))
                HStack(alignment: .firstTextBaseline) {
                    Text("Liest deinen Claude-Code-Login aus dem Schlüsselbund und fragt Anthropic nach den Limits.")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 8)
                    Button("Anzeigen") { self.store.claudeLimitsEnabled = true }
                        .controlSize(.small)
                }
            }
        } else if let error = self.store.claudeLimitsError, self.store.claudeLimits == nil {
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text("Claude Code").font(.caption.weight(.semibold))
                    Spacer()
                    Button("Aus") { self.store.claudeLimitsEnabled = false }.buttonStyle(.borderless).font(.caption2)
                }
                Text(error).font(.caption2).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
        } else {
            self.providerBlock(.claude, limits: self.store.claudeLimits) {
                Text("Lade …")
            }
        }
    }

    private func providerBlock(_ provider: Provider, limits: ProviderLimits?,
                               @ViewBuilder empty: () -> some View) -> some View
    {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Text(provider.displayName).font(.caption.weight(.semibold))
                if let plan = limits?.plan {
                    Text(plan.capitalized)
                        .font(.caption2.weight(.medium))
                        .padding(.horizontal, 5)
                        .padding(.vertical, 1)
                        .background(.quaternary, in: Capsule())
                }
                Spacer()
                if let limits, let stale = Self.staleText(limits.observedAt) {
                    Text(stale).font(.caption2).foregroundStyle(.tertiary)
                }
            }
            if let limits {
                ForEach(limits.windows.map { $0.current() }, id: \.label) { window in
                    LimitBar(window: window)
                }
            } else {
                empty().font(.caption2).foregroundStyle(.secondary)
            }
        }
    }

    /// Log-based values can be old when the CLI hasn't been used for a while.
    static func staleText(_ date: Date, now: Date = Date()) -> String? {
        let minutes = Int(now.timeIntervalSince(date) / 60)
        switch minutes {
        case ..<60: return nil
        case ..<1440: return "Stand vor \(minutes / 60) Std."
        default: return "Stand vor \(minutes / 1440) T."
        }
    }
}

private struct LimitBar: View {
    let window: LimitWindow

    private var tint: Color {
        switch self.window.usedPercent {
        case 90...: .red
        case 70...: .orange
        default: .green
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Text(self.window.label).font(.caption2)
                Spacer()
                Text("\(Int(self.window.usedPercent.rounded())) %").font(.caption2.monospacedDigit().weight(.semibold))
                if let reset = self.window.resetsAt {
                    Text("· Reset \(Self.relative(reset))").font(.caption2).foregroundStyle(.secondary)
                }
            }
            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule().fill(.quaternary)
                    Capsule().fill(self.tint)
                        .frame(width: max(3, proxy.size.width * self.window.usedPercent / 100))
                }
            }
            .frame(height: 5)
        }
        .accessibilityElement(children: .combine)
    }

    static func relative(_ date: Date, now: Date = Date()) -> String {
        let minutes = max(0, Int(date.timeIntervalSince(now) / 60))
        if minutes >= 1440 { return "in \(minutes / 1440) T \(minutes % 1440 / 60) Std." }
        if minutes >= 60 { return "in \(minutes / 60) Std. \(minutes % 60) Min." }
        return "in \(minutes) Min."
    }
}
