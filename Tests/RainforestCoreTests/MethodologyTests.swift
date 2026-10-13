import Foundation
import Testing
@testable import RainforestCore

struct MethodologyTests {
    @Test
    func `Claude coefficients reproduce Jegham Table 4 exactly`() {
        let c = Methodology.claudeEnergy
        func energy(_ input: Double, _ output: Double) -> Double {
            c.perRequestWh + c.perInputTokenWh * input + c.perOutputTokenWh * output
        }
        #expect(abs(energy(100, 300) - 0.950) < 1e-9)
        #expect(abs(energy(1000, 1000) - 2.989) < 1e-9)
        #expect(abs(energy(10000, 1500) - 5.671) < 1e-9)
        #expect(abs(c.perOutputTokenWh - 0.0027243) < 1e-6)
        #expect(abs(c.perInputTokenWh - 0.00014664) < 1e-7)
        #expect(abs(c.perRequestWh - 0.11805) < 1e-4)
    }

    @Test
    func `Codex coefficients reproduce Jegham Table 4 exactly`() {
        let c = Methodology.codexEnergy
        #expect(abs(c.perRequestWh + 100 * c.perInputTokenWh + 300 * c.perOutputTokenWh - 0.423) < 1e-9)
        #expect(abs(c.perRequestWh + 10000 * c.perInputTokenWh + 1500 * c.perOutputTokenWh - 2.875) < 1e-9)
        #expect(abs(c.perOutputTokenWh - 0.00096308) < 1e-7)
    }

    @Test
    func `rainforest constants follow IPCC and ter Steege`() {
        // 307.1 t d.m./ha × 0.47 × 44/12
        #expect(abs(Methodology.co2TonnesPerHectare - 529.236) < 0.01)
        #expect(abs(Methodology.co2KgPerSquareMeter - 52.92) < 0.01)
        #expect(abs(Methodology.co2KgPerTree - 936.7) < 0.1)
        #expect(abs(Methodology.co2KgPerBlock - 23.42) < 0.01)
        #expect(abs(Methodology.co2GramsPerPixel - 91.48) < 0.01)
    }

    @Test
    func `full chain from tokens to pixels is pinned`() {
        let counts = TokenCounts(freshInput: 10_000, cacheWrite: 1_000_000, cacheRead: 50_000_000,
                                 output: 500_000, requests: 2_000)
        let impact = ImpactCalculator.impact(counts, provider: .claude, grid: .datacenter)
        let c = Methodology.claudeEnergy
        let expectedWh = 2_000 * c.perRequestWh
            + c.perInputTokenWh * (1_010_000 + 0.1 * 50_000_000)
            + c.perOutputTokenWh * 500_000
        #expect(abs(impact.energyWh - expectedWh) < 1e-6)
        #expect(abs(impact.energyWh - 2479.6) < 0.1)
        #expect(abs(impact.co2Kg - 0.71165) < 0.0001)
        #expect(abs(impact.pixels - impact.co2Kg * 1000 / 91.48) < 0.01)
        #expect(impact.trees < 0.001)
    }

    @Test
    func `global grid uses Ember world average`() {
        let counts = TokenCounts(output: 1_000_000)
        let impact = ImpactCalculator.impact(counts, provider: .codex, grid: .globalAverage)
        #expect(abs(impact.co2Kg - impact.energyWh / 1000 * 0.458) < 1e-9)
    }
}

struct TreeLayoutTests {
    @Test
    func `pixel tree has exactly the block count used by the methodology`() {
        #expect(TreeLayout.blocks.count == Methodology.blocksPerTree)
        #expect(Set(TreeLayout.burnOrder).count == Methodology.blocksPerTree)
        #expect(TreeLayout.burnOrder.last?.isLog == true)
    }
}
