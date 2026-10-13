import Foundation

/// Which electricity carbon intensity to apply.
public enum GridMix: String, CaseIterable, Codable, Sendable {
    /// Cloud-specific values from Jegham et al. Table 1 (AWS for Claude, Azure for Codex).
    case datacenter
    /// World average 2025 from Ember.
    case globalAverage

    public var displayName: String {
        switch self {
        case .datacenter: "Rechenzentrum (AWS/Azure)"
        case .globalAverage: "Weltdurchschnitt Strom"
        }
    }

    public func carbonIntensity(for provider: Provider) -> Double {
        switch self {
        case .datacenter:
            provider == .claude ? Methodology.awsCarbonIntensity : Methodology.azureCarbonIntensity
        case .globalAverage:
            Methodology.globalGridCarbonIntensity
        }
    }
}

/// Every intermediate value of the token → rainforest chain, so the UI can show its work.
public struct Impact: Hashable, Sendable {
    public var energyWh: Double
    public var co2Kg: Double

    public init(energyWh: Double = 0, co2Kg: Double = 0) {
        self.energyWh = energyWh
        self.co2Kg = co2Kg
    }

    public static let zero = Impact()

    public static func + (lhs: Impact, rhs: Impact) -> Impact {
        Impact(energyWh: lhs.energyWh + rhs.energyWh, co2Kg: lhs.co2Kg + rhs.co2Kg)
    }

    public var rainforestSquareMeters: Double {
        self.co2Kg / Methodology.co2KgPerSquareMeter
    }

    public var trees: Double {
        self.co2Kg / Methodology.co2KgPerTree
    }

    public var blocks: Double {
        self.co2Kg / Methodology.co2KgPerBlock
    }

    public var pixels: Double {
        self.co2Kg * 1000 / Methodology.co2GramsPerPixel
    }
}

public enum ImpactCalculator {
    public static func coefficients(for provider: Provider) -> EnergyCoefficients {
        switch provider {
        case .claude: Methodology.claudeEnergy
        case .codex: Methodology.codexEnergy
        }
    }

    public static func energyWh(_ counts: TokenCounts, coefficients c: EnergyCoefficients) -> Double {
        let computedInput = Double(counts.freshInput + counts.cacheWrite)
        let cachedInput = Double(counts.cacheRead) * c.cacheReadWeight
        return c.perRequestWh * Double(counts.requests)
            + c.perInputTokenWh * (computedInput + cachedInput)
            + c.perOutputTokenWh * Double(counts.output)
    }

    public static func impact(_ counts: TokenCounts, provider: Provider, grid: GridMix) -> Impact {
        let wh = self.energyWh(counts, coefficients: self.coefficients(for: provider))
        return Impact(energyWh: wh, co2Kg: wh / 1000 * grid.carbonIntensity(for: provider))
    }

    public static func impact(ledger: UsageLedger, from start: DayKey?, through end: DayKey?, grid: GridMix) -> Impact {
        Provider.allCases.reduce(Impact.zero) { total, provider in
            total + self.impact(ledger.counts(provider: provider, from: start, through: end), provider: provider, grid: grid)
        }
    }
}
