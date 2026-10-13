import RainforestCore
import SwiftUI

enum Format {
    static func tokens(_ value: Int) -> String {
        switch value {
        case 1_000_000_000...: String(format: "%.2f Mrd.", Double(value) / 1e9)
        case 1_000_000...: String(format: "%.1f Mio.", Double(value) / 1e6)
        case 10000...: String(format: "%.0f k", Double(value) / 1e3)
        default: "\(value)"
        }
    }

    static func co2(_ kg: Double) -> String {
        kg >= 1 ? String(format: "%.2f kg", kg) : String(format: "%.0f g", kg * 1000)
    }

    static func energy(_ wh: Double) -> String {
        wh >= 1000 ? String(format: "%.2f kWh", wh / 1000) : String(format: "%.0f Wh", wh)
    }

    static func area(_ squareMeters: Double) -> String {
        squareMeters >= 1 ? String(format: "%.2f m²", squareMeters) : String(format: "%.0f cm²", squareMeters * 10000)
    }

    static func number(_ value: Double, digits: Int) -> String {
        String(format: "%.\(digits)f", value)
    }
}

struct PopoverView: View {
    @Bindable var store: UsageStore
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        let impact = self.store.impact
        VStack(alignment: .leading, spacing: 12) {
            self.header
            Picker("Zeitraum", selection: self.$store.period) {
                ForEach(Period.allCases) { Text($0.title).tag($0) }
            }
            .pickerStyle(.segmented)
            .labelsHidden()

            PixelSceneView(impact: impact)
                .frame(width: 320, height: 192)
                .overlay(alignment: .topLeading) { self.levelBadge(impact) }

            self.headline(impact)
            self.stats(impact)
            self.providerRows
            Divider()
            self.footer
        }
        .padding(16)
        .frame(width: 352)
        .fontDesign(.rounded)
    }

    private var header: some View {
        HStack {
            Text("Tokens vs. Regenwald")
                .font(.headline)
            Spacer()
            if self.store.isLoading {
                ProgressView().controlSize(.small)
            }
        }
    }

    private func levelBadge(_ impact: Impact) -> some View {
        let text = switch SceneLevel(impact: impact) {
        case .block: "Zoom: 1 Blatt-Block"
        case .tree: "1 Regenwaldbaum"
        case let .forest(trees):
            trees <= 18 ? "1 Symbol = 1 Baum" : "1 Symbol = \(Int((trees / 18).rounded(.up))) Bäume"
        }
        return Text(text)
            .font(.caption2.weight(.semibold))
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .background(.black.opacity(0.35), in: Capsule())
            .foregroundStyle(.white)
            .padding(6)
    }

    private func headline(_ impact: Impact) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(self.headlineText(impact))
                .font(.title3.weight(.bold))
            Text("Das CO₂ deiner Tokens entspricht dem Kohlenstoff in \(Format.area(impact.rainforestSquareMeters)) "
                + "Amazonas-Regenwald (oberirdische Biomasse).")
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func headlineText(_ impact: Impact) -> String {
        switch SceneLevel(impact: impact) {
        case let .block(pixels):
            pixels < 0.5 ? "Noch kein Pixel verbrannt 🌱" : "🔥 \(Format.number(pixels, digits: 0)) von 256 Pixeln verbrannt"
        case let .tree(blocks):
            "🔥 \(Format.number(blocks, digits: 1)) von 40 Baum-Blöcken verbrannt"
        case let .forest(trees):
            "🔥 \(Format.number(trees, digits: 2)) Regenwaldbäume verbrannt"
        }
    }

    private func stats(_ impact: Impact) -> some View {
        Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 4) {
            GridRow {
                StatCell(title: "Strom", value: Format.energy(impact.energyWh))
                StatCell(title: "CO₂e", value: Format.co2(impact.co2Kg))
                StatCell(title: "Bäume", value: Format.number(impact.trees, digits: impact.trees < 0.01 ? 4 : 2))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var providerRows: some View {
        VStack(alignment: .leading, spacing: 3) {
            ForEach(Provider.allCases, id: \.self) { provider in
                let counts = self.store.counts(provider)
                HStack {
                    Text(provider.displayName).font(.caption.weight(.semibold))
                    Spacer()
                    Text("\(Format.tokens(counts.total)) Tokens · \(Format.tokens(counts.output)) Output")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
            }
            Text("1 Pixel ≈ \(Format.number(Methodology.co2GramsPerPixel, digits: 0)) g CO₂ · 1 Baum ≈ "
                + "\(Format.number(Methodology.co2KgPerTree, digits: 0)) kg CO₂")
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
    }

    private var footer: some View {
        HStack {
            Button("Quellen & Rechnung") {
                self.openWindow(id: "sources")
                NSApp.activate(ignoringOtherApps: true)
            }
            Spacer()
            Button {
                Task { await self.store.refresh() }
            } label: {
                Image(systemName: "arrow.clockwise")
            }
            .help("Neu einlesen")
            Button {
                NSApp.terminate(nil)
            } label: {
                Image(systemName: "power")
            }
            .help("Beenden")
        }
        .buttonStyle(.borderless)
        .font(.callout)
    }
}

private struct StatCell: View {
    let title: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(self.title).font(.caption2).foregroundStyle(.secondary)
            Text(self.value).font(.callout.weight(.semibold).monospacedDigit())
        }
    }
}
