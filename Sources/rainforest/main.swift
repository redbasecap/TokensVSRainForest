import Foundation
import RainforestCore

// Usage: rainforest [--days N | --all] [--global-grid]
let arguments = CommandLine.arguments.dropFirst()
if arguments.contains("--help") || arguments.contains("-h") {
    print("""
    rainforest – wie viel Regenwald-CO₂ entsprechen deinen Claude-Code-/Codex-Tokens?

      --days N        letzte N Tage inkl. heute (Standard: 1 = heute)
      --all           alle lokalen Logs
      --global-grid   Welt-Strommix (Ember 2026) statt Rechenzentrums-Mix (Jegham et al. 2025)
      --sources       Quellen ausgeben
    """)
    exit(0)
}

if arguments.contains("--sources") {
    for source in Sources.all {
        print("• \(source.citation)\n  \(source.locator)\n  \(source.url.absoluteString)\n")
    }
    exit(0)
}

let calendar = Calendar.current
let today = calendar.startOfDay(for: Date())
var startDate: Date? = today
if arguments.contains("--all") {
    startDate = nil
} else if let index = arguments.firstIndex(of: "--days"), arguments.index(after: index) < arguments.endIndex,
          let days = Int(arguments[arguments.index(after: index)]), days > 0
{
    startDate = calendar.date(byAdding: .day, value: -(days - 1), to: today)
}
let grid: GridMix = arguments.contains("--global-grid") ? .globalAverage : .datacenter

let started = Date()
let ledger = await UsageLoader().load(since: startDate)
let startKey = startDate.map { DayKey(date: $0, calendar: calendar) }

func format(_ value: Double, _ digits: Int = 2) -> String {
    String(format: "%.\(digits)f", value)
}

func formatInt(_ value: Int) -> String {
    let formatter = NumberFormatter()
    formatter.numberStyle = .decimal
    formatter.groupingSeparator = "’"
    return formatter.string(from: NSNumber(value: value)) ?? "\(value)"
}

print("Zeitraum: \(startKey.map { "ab \($0)" } ?? "alle Logs") · Strommix: \(grid.displayName)\n")
var total = Impact.zero
for provider in Provider.allCases {
    let counts = ledger.counts(provider: provider, from: startKey, through: nil)
    let impact = ImpactCalculator.impact(counts, provider: provider, grid: grid)
    total = total + impact
    print("""
    \(provider.displayName)
      Requests      \(formatInt(counts.requests))
      Input frisch  \(formatInt(counts.freshInput))
      Cache-Write   \(formatInt(counts.cacheWrite))
      Cache-Read    \(formatInt(counts.cacheRead))
      Output        \(formatInt(counts.output))
      Energie       \(format(impact.energyWh / 1000, 3)) kWh
      CO₂e          \(format(impact.co2Kg, 3)) kg  (\(grid.carbonIntensity(for: provider)) kg/kWh)

    """)
}
print("""
Gesamt
  Energie      \(format(total.energyWh / 1000, 3)) kWh
  CO₂e         \(format(total.co2Kg, 3)) kg
  Regenwald    \(format(total.rainforestSquareMeters * 10000, 0)) cm²  (\(format(Methodology.co2KgPerSquareMeter, 1)) kg CO₂/m²)
  Bäume        \(format(total.trees, 5))  (1 Baum ≈ \(format(Methodology.co2KgPerTree, 0)) kg CO₂)
  Blöcke       \(format(total.blocks, 3))  (1 Block ≈ \(format(Methodology.co2KgPerBlock, 1)) kg CO₂)
  Pixel        \(format(total.pixels, 0))  (1 Pixel ≈ \(format(Methodology.co2GramsPerPixel, 1)) g CO₂)

(gescannt in \(format(Date().timeIntervalSince(started), 1)) s)
""")
