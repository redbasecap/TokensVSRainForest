import Foundation

/// Daily averages over a period; feeds the web simulation (`web/index.html`).
public struct UsageSummary: Codable, Sendable {
    public let from: String
    public let through: String
    public let days: Int
    public let tokensPerDay: Double
    public let outputTokensPerDay: Double
    public let energyWhPerDay: Double
    public let co2KgPerDay: Double
    public let grid: String

    public init(ledger: UsageLedger, from start: DayKey?, through end: DayKey, grid: GridMix) {
        let first = start ?? ledger.firstDay ?? end
        let days = max(1, Self.dayCount(from: first, through: end))
        let counts = Provider.allCases.map { ledger.counts(provider: $0, from: first, through: end) }
        let impact = ImpactCalculator.impact(ledger: ledger, from: first, through: end, grid: grid)
        self.from = first.rawValue
        self.through = end.rawValue
        self.days = days
        self.tokensPerDay = Double(counts.map(\.total).reduce(0, +)) / Double(days)
        self.outputTokensPerDay = Double(counts.map(\.output).reduce(0, +)) / Double(days)
        self.energyWhPerDay = impact.energyWh / Double(days)
        self.co2KgPerDay = impact.co2Kg / Double(days)
        self.grid = grid.rawValue
    }

    static func dayCount(from start: DayKey, through end: DayKey) -> Int {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.timeZone = TimeZone(identifier: "UTC")
        formatter.dateFormat = "yyyy-MM-dd"
        guard let a = formatter.date(from: start.rawValue), let b = formatter.date(from: end.rawValue) else { return 1 }
        return Int((b.timeIntervalSince(a) / 86400).rounded()) + 1
    }
}
