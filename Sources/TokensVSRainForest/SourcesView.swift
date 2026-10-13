import RainforestCore
import SwiftUI

/// Shows every step of the calculation with its source, so nothing is a black box.
struct SourcesView: View {
    @Bindable var store: UsageStore

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                Text("So wird gerechnet")
                    .font(.title2.weight(.bold))
                Text("Tokens → Strom → CO₂ → Regenwald. Alle Werte sind Schätzungen mit großer Unsicherheit; "
                    + "die App zeigt eine CO₂-Äquivalenz, keine tatsächlich gerodete Fläche.")
                    .foregroundStyle(.secondary)

                self.step(
                    number: 1,
                    title: "Tokens zählen (lokal)",
                    body: "Gelesen werden nur die Logdateien von Claude Code (~/.claude/projects) und Codex CLI "
                        + "(~/.codex/sessions). Keine Netzwerkanfragen, kein Schlüsselbund. Nutzung im Browser oder "
                        + "in den Chat-Apps (claude.ai, ChatGPT) steht nicht in diesen Logs und fehlt daher.",
                    sources: [Sources.codexBar])

                self.step(
                    number: 2,
                    title: "Strom pro Token",
                    body: self.energyText,
                    sources: [Sources.jegham2025, Sources.anthropicCaching, Sources.epoch2025, Sources.google2025])

                VStack(alignment: .leading, spacing: 6) {
                    self.stepTitle(3, "CO₂ pro kWh")
                    Picker("Strommix", selection: self.$store.grid) {
                        ForEach(GridMix.allCases, id: \.self) { Text($0.displayName).tag($0) }
                    }
                    .pickerStyle(.radioGroup)
                    Text("Rechenzentrum: \(Methodology.awsCarbonIntensity) kg/kWh (AWS, Claude) und "
                        + "\(Methodology.azureCarbonIntensity) kg/kWh (Azure, Codex) laut Jegham et al. Tabelle 1. "
                        + "Weltdurchschnitt: \(Methodology.globalGridCarbonIntensity) kg/kWh (Ember 2026). "
                        + "Die Energiewerte enthalten bereits den PUE-Overhead des Rechenzentrums.")
                        .fixedSize(horizontal: false, vertical: true)
                    self.sourceLinks([Sources.jegham2025, Sources.ember2026])
                }

                self.step(
                    number: 4,
                    title: "CO₂ → Regenwald",
                    body: self.forestText,
                    sources: [Sources.ipcc2019, Sources.ipcc2006, Sources.terSteege2013])

                VStack(alignment: .leading, spacing: 6) {
                    self.stepTitle(5, "Nicht enthalten")
                    Text("Training der Modelle, Herstellung der Hardware (Scope 3), Wasserverbrauch, Netzwerk und "
                        + "dein eigener Rechner. Für neuere Modelle (Claude 4.x, GPT-5) gibt es keine öffentlichen "
                        + "Messwerte pro Token, deshalb werden die Werte von Claude 3.7 Sonnet bzw. GPT-4o verwendet.")
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(24)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(minWidth: 520, idealWidth: 600, minHeight: 560, idealHeight: 720)
        .textSelection(.enabled)
    }

    private var energyText: String {
        let claude = Methodology.claudeEnergy
        let codex = Methodology.codexEnergy
        func mwh(_ wh: Double) -> String { String(format: "%.3f mWh", wh * 1000) }
        return """
        Jegham et al. (2025) schätzen den Strom pro Anfrage für drei Prompt-Größen \
        (100/300, 1 000/1 000 und 10 000/1 500 Input/Output-Tokens). Durch diese drei Punkte wird exakt \
        E = c · Anfragen + a · Input + b · Output gelegt:

        • Claude (Claude 3.7 Sonnet, 0,950 / 2,989 / 5,671 Wh): Output \(mwh(claude.perOutputTokenWh)), \
        Input \(mwh(claude.perInputTokenWh)) pro Token, \(String(format: "%.3f", claude.perRequestWh)) Wh pro Anfrage.
        • Codex (GPT-4o, 0,423 / 1,215 / 2,875 Wh): Output \(mwh(codex.perOutputTokenWh)), \
        Input \(mwh(codex.perInputTokenWh)) pro Token, \(String(format: "%.3f", codex.perRequestWh)) Wh pro Anfrage.

        Cache-Treffer (Cache-Read) überspringen die Neuberechnung. Annahme: Sie kosten \
        \(Int(Methodology.cacheReadWeight * 100)) % eines frischen Input-Tokens. Das entspricht dem \
        Preisverhältnis bei Anthropic, ist also ein Näherungswert und keine Messung. Cache-Writes zählen wie \
        frischer Input. Zum Vergleich: Epoch AI schätzt ≈ 0,3 Wh für 500 Output-Tokens (≈ 0,6 mWh/Token), \
        Google misst 0,24 Wh für einen mittleren Gemini-Prompt.
        """
    }

    private var forestText: String {
        """
        Oberirdische Biomasse im tropischen Primär-Regenwald Amerikas: \
        \(Methodology.aboveGroundBiomassTonnesPerHectare) t Trockenmasse/ha (IPCC 2019, Tab. 4.7) \
        × Kohlenstoffanteil \(Methodology.carbonFraction) (IPCC 2006, Tab. 4.3) × 44/12 (C → CO₂) \
        = \(String(format: "%.0f", Methodology.co2TonnesPerHectare)) t CO₂/ha \
        = \(String(format: "%.1f", Methodology.co2KgPerSquareMeter)) kg CO₂ pro m². \
        Wurzeln sind nicht eingerechnet, weil sie beim Brand nicht verbrennen.

        Bei \(Int(Methodology.treesPerHectare)) Bäumen/ha (ter Steege et al. 2013, Bäume ≥ 10 cm Stammdurchmesser) \
        speichert ein Baum im Schnitt ≈ \(String(format: "%.0f", Methodology.co2KgPerTree)) kg CO₂. \
        Der Pixel-Baum besteht aus \(Methodology.blocksPerTree) Blöcken mit je 16 × 16 Pixeln: \
        1 Block ≈ \(String(format: "%.1f", Methodology.co2KgPerBlock)) kg, \
        1 Pixel ≈ \(String(format: "%.1f", Methodology.co2GramsPerPixel)) g CO₂.
        """
    }

    private func stepTitle(_ number: Int, _ title: String) -> some View {
        Text("\(number). \(title)").font(.headline)
    }

    private func step(number: Int, title: String, body: String, sources: [Source]) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            self.stepTitle(number, title)
            Text(body).fixedSize(horizontal: false, vertical: true)
            self.sourceLinks(sources)
        }
    }

    private func sourceLinks(_ sources: [Source]) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            ForEach(sources) { source in
                VStack(alignment: .leading, spacing: 1) {
                    Link(source.citation, destination: source.url).font(.caption)
                    Text(source.locator).font(.caption2).foregroundStyle(.secondary)
                }
            }
        }
        .padding(.leading, 8)
    }
}
