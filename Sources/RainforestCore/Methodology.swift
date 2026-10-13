import Foundation

// MARK: - Sources

/// A citable reference that backs one or more constants of the impact model.
public struct Source: Identifiable, Hashable, Sendable {
    public let id: String
    public let citation: String
    public let locator: String
    public let url: URL

    public init(id: String, citation: String, locator: String, url: String) {
        self.id = id
        self.citation = citation
        self.locator = locator
        self.url = URL(string: url)!
    }
}

public enum Sources {
    public static let jegham2025 = Source(
        id: "jegham2025",
        citation: "Jegham, Abdelatti, Koh, Elmoubarki, Hendawi (2025): How Hungry is AI? Benchmarking Energy, "
            + "Water, and Carbon Footprint of LLM Inference. arXiv:2505.09598v6",
        locator: "Tabelle 4 (Energie pro Prompt, Wh) und Tabelle 1 (PUE, CIF je Cloud)",
        url: "https://arxiv.org/abs/2505.09598")

    public static let epoch2025 = Source(
        id: "epoch2025",
        citation: "You, J. / Epoch AI (2025-02-07): How much energy does ChatGPT use?",
        locator: "≈0,3 Wh pro GPT-4o-Anfrage mit 500 Ausgabe-Tokens (Gegenprobe, untere Schranke)",
        url: "https://epoch.ai/gradient-updates/how-much-energy-does-chatgpt-use")

    public static let google2025 = Source(
        id: "google2025",
        citation: "Elsworth et al. / Google (2025): Measuring the environmental impact of delivering AI at "
            + "Google Scale. arXiv:2508.15734",
        locator: "Median-Prompt Gemini Apps: 0,24 Wh (Plausibilitätsprüfung)",
        url: "https://arxiv.org/abs/2508.15734")

    public static let anthropicCaching = Source(
        id: "anthropicCaching",
        citation: "Anthropic: Prompt caching – Preise (Cache-Read = 0,1 × Basis-Input-Preis)",
        locator: "Annahme: Preisverhältnis als Proxy für den Rechenaufwand eines Cache-Treffers",
        url: "https://docs.claude.com/en/docs/build-with-claude/prompt-caching")

    public static let ember2026 = Source(
        id: "ember2026",
        citation: "Ember (2026): Global Electricity Review 2026",
        locator: "Weltweite Emissionsintensität Strom 2025: 458 gCO₂e/kWh",
        url: "https://ember-energy.org/latest-insights/global-electricity-review-2026/")

    public static let ipcc2019 = Source(
        id: "ipcc2019",
        citation: "IPCC (2019): 2019 Refinement to the 2006 IPCC Guidelines for National Greenhouse Gas "
            + "Inventories, Vol. 4, Kap. 4 Forest Land",
        locator: "Tabelle 4.7 (Updated): Tropischer Regenwald, Nord- & Südamerika, Primärwald: "
            + "307,1 t Trockenmasse/ha oberirdisch (SD 104,9)",
        url: "https://www.ipcc-nggip.iges.or.jp/public/2019rf/pdf/4_Volume4/19R_V4_Ch04_Forest%20Land.pdf")

    public static let ipcc2006 = Source(
        id: "ipcc2006",
        citation: "IPCC (2006): 2006 IPCC Guidelines for National Greenhouse Gas Inventories, Vol. 4, Kap. 4",
        locator: "Tabelle 4.3: Kohlenstoffanteil tropische Biomasse 0,47 (0,44–0,49) t C / t TM",
        url: "https://www.ipcc-nggip.iges.or.jp/public/2006gl/pdf/4_Volume4/V4_04_Ch4_Forest_Land.pdf")

    public static let terSteege2013 = Source(
        id: "terSteege2013",
        citation: "ter Steege et al. (2013): Hyperdominance in the Amazonian Tree Flora. Science 342, 1243092",
        locator: "3,9 × 10¹¹ Bäume (≥10 cm BHD), Median-Dichte 565 Bäume/ha",
        url: "https://doi.org/10.1126/science.1243092")

    public static let codexBar = Source(
        id: "codexBar",
        citation: "Steinberger, P.: CodexBar (MIT) – Vorbild für das Lesen lokaler Claude-Code-/Codex-Logs",
        locator: "Deduplizierung nach message.id + requestId, Codex token_count-Deltas",
        url: "https://github.com/steipete/CodexBar")

    public static let all: [Source] = [
        jegham2025, epoch2025, google2025, anthropicCaching, ember2026, ipcc2019, ipcc2006, terSteege2013, codexBar,
    ]
}

// MARK: - Energy per token

/// Linear energy model `E = perRequest · requests + perInput · freshInput + perOutput · output`
/// (+ cache reads weighted by `cacheReadWeight` of `perInput`). All values in Wh and already include PUE.
public struct EnergyCoefficients: Hashable, Sendable {
    public let label: String
    public let perRequestWh: Double
    public let perInputTokenWh: Double
    public let perOutputTokenWh: Double
    public let cacheReadWeight: Double
    public let source: Source

    public init(
        label: String,
        perRequestWh: Double,
        perInputTokenWh: Double,
        perOutputTokenWh: Double,
        cacheReadWeight: Double,
        source: Source)
    {
        self.label = label
        self.perRequestWh = perRequestWh
        self.perInputTokenWh = perInputTokenWh
        self.perOutputTokenWh = perOutputTokenWh
        self.cacheReadWeight = cacheReadWeight
        self.source = source
    }

    /// Exact solve of `E = c + a·in + b·out` through the three prompt sizes of Jegham et al. Table 4
    /// (100/300, 1 000/1 000, 10 000/1 500 input/output tokens).
    public static func fitJegham(
        label: String,
        short: Double,
        medium: Double,
        long: Double,
        cacheReadWeight: Double = Methodology.cacheReadWeight) -> EnergyCoefficients
    {
        // medium − short: 900a + 700b = Δ1 ; long − medium: 9000a + 500b = Δ2
        let delta1 = medium - short
        let delta2 = long - medium
        let perOutput = (10 * delta1 - delta2) / (10 * 700 - 500)
        let perInput = (delta1 - 700 * perOutput) / 900
        let perRequest = short - 100 * perInput - 300 * perOutput
        return EnergyCoefficients(
            label: label,
            perRequestWh: perRequest,
            perInputTokenWh: perInput,
            perOutputTokenWh: perOutput,
            cacheReadWeight: cacheReadWeight,
            source: Sources.jegham2025)
    }
}

// MARK: - Constants

public enum Methodology {
    /// Cache reads skip the prefill; Anthropic bills them at 0.1× input. Used as compute proxy (assumption).
    public static let cacheReadWeight = 0.1

    /// Claude 3.7 Sonnet on AWS, Jegham et al. Table 4: 0.950 / 2.989 / 5.671 Wh.
    /// No public per-token data exists for newer Claude models; Sonnet values are used for all Claude models.
    public static let claudeEnergy = EnergyCoefficients.fitJegham(
        label: "Claude 3.7 Sonnet (AWS)", short: 0.950, medium: 2.989, long: 5.671)

    /// GPT-4o (Mar '25) on Azure, Jegham et al. Table 4: 0.423 / 1.215 / 2.875 Wh.
    public static let codexEnergy = EnergyCoefficients.fitJegham(
        label: "GPT-4o (Azure)", short: 0.423, medium: 1.215, long: 2.875)

    /// Carbon intensity used by Jegham et al. Table 1 for the hosting cloud (kg CO₂e per kWh).
    public static let awsCarbonIntensity = 0.287
    public static let azureCarbonIntensity = 0.35
    /// Ember Global Electricity Review 2026, world average 2025.
    public static let globalGridCarbonIntensity = 0.458

    /// IPCC 2019 Table 4.7: tropical rainforest, Americas, primary, above-ground (t dry matter / ha).
    public static let aboveGroundBiomassTonnesPerHectare = 307.1
    /// IPCC 2006 Table 4.3: carbon fraction of tropical biomass.
    public static let carbonFraction = 0.47
    /// Molar mass ratio CO₂ / C.
    public static let co2PerCarbon = 44.0 / 12.0
    /// ter Steege et al. 2013: median Amazon tree density (trees ≥ 10 cm DBH per ha).
    public static let treesPerHectare = 565.0

    /// Above-ground biomass only: that is what a fire releases immediately. Not the conservative choice —
    /// with roots (IPCC Tab. 4.4, R = 0.221) a tree holds ≈1 144 kg CO₂, i.e. ≈18 % fewer trees per kg.
    public static var co2TonnesPerHectare: Double {
        self.aboveGroundBiomassTonnesPerHectare * self.carbonFraction * self.co2PerCarbon
    }

    public static var co2KgPerSquareMeter: Double {
        self.co2TonnesPerHectare * 1000 / 10000
    }

    public static var co2KgPerTree: Double {
        self.co2TonnesPerHectare * 1000 / self.treesPerHectare
    }

    /// The pixel tree in the app is made of this many Minecraft-style blocks.
    public static let blocksPerTree = 40
    /// Each block has a 16 × 16 pixel texture, like Minecraft.
    public static let pixelsPerBlock = 256

    public static var co2KgPerBlock: Double {
        self.co2KgPerTree / Double(self.blocksPerTree)
    }

    public static var co2GramsPerPixel: Double {
        self.co2KgPerBlock * 1000 / Double(self.pixelsPerBlock)
    }
}
