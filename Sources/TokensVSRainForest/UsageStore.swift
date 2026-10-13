import Foundation
import Observation
import RainforestCore

enum Period: String, CaseIterable, Identifiable {
    case today
    case week
    case month
    case all

    var id: String {
        self.rawValue
    }

    var title: String {
        switch self {
        case .today: "Heute"
        case .week: "7 Tage"
        case .month: "30 Tage"
        case .all: "Gesamt"
        }
    }

    func startDate(calendar: Calendar = .current, now: Date = Date()) -> Date? {
        let today = calendar.startOfDay(for: now)
        switch self {
        case .today: return today
        case .week: return calendar.date(byAdding: .day, value: -6, to: today)
        case .month: return calendar.date(byAdding: .day, value: -29, to: today)
        case .all: return nil
        }
    }
}

@MainActor
@Observable
final class UsageStore {
    private(set) var ledger = UsageLedger()
    private(set) var isLoading = false
    private(set) var lastUpdated: Date?
    @ObservationIgnored private var reloadPending = false

    var period: Period {
        didSet {
            UserDefaults.standard.set(self.period.rawValue, forKey: "period")
            Task { await self.refresh() }
        }
    }

    var grid: GridMix {
        didSet { UserDefaults.standard.set(self.grid.rawValue, forKey: "grid") }
    }

    private let loader = UsageLoader()
    private var timer: Task<Void, Never>?

    init() {
        self.period = UserDefaults.standard.string(forKey: "period").flatMap(Period.init(rawValue:)) ?? .today
        self.grid = UserDefaults.standard.string(forKey: "grid").flatMap(GridMix.init(rawValue:)) ?? .datacenter
        self.timer = Task { [weak self] in
            while !Task.isCancelled {
                await self?.refresh()
                try? await Task.sleep(for: .seconds(300))
            }
        }
    }

    var startKey: DayKey? {
        self.period.startDate().map { DayKey(date: $0) }
    }

    func counts(_ provider: Provider) -> TokenCounts {
        self.ledger.counts(provider: provider, from: self.startKey, through: nil)
    }

    var impact: Impact {
        ImpactCalculator.impact(ledger: self.ledger, from: self.startKey, through: nil, grid: self.grid)
    }

    var todayImpact: Impact {
        ImpactCalculator.impact(
            ledger: self.ledger, from: Period.today.startDate().map { DayKey(date: $0) }, through: nil, grid: self.grid)
    }

    func refresh() async {
        guard !self.isLoading else {
            self.reloadPending = true
            return
        }
        self.isLoading = true
        repeat {
            self.reloadPending = false
            // Always cover at least 30 days so switching between short periods is instant.
            let wanted = self.period == .all ? nil : Period.month.startDate()
            self.ledger = await self.loader.load(since: wanted)
            self.lastUpdated = Date()
        } while self.reloadPending
        self.isLoading = false
    }
}
