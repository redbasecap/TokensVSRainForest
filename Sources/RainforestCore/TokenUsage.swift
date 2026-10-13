import Foundation

public enum Provider: String, CaseIterable, Codable, Sendable {
    case claude
    case codex

    public var displayName: String {
        switch self {
        case .claude: "Claude Code"
        case .codex: "Codex"
        }
    }
}

/// Token counts split into the four classes that differ in energy cost.
public struct TokenCounts: Hashable, Codable, Sendable {
    /// Uncached input tokens (prefill computed from scratch).
    public var freshInput: Int
    /// Input tokens written into the prompt cache (also computed from scratch).
    public var cacheWrite: Int
    /// Input tokens served from the prompt cache.
    public var cacheRead: Int
    /// Generated tokens, including reasoning/thinking.
    public var output: Int
    /// Number of model requests (assistant responses).
    public var requests: Int

    public init(freshInput: Int = 0, cacheWrite: Int = 0, cacheRead: Int = 0, output: Int = 0, requests: Int = 0) {
        self.freshInput = freshInput
        self.cacheWrite = cacheWrite
        self.cacheRead = cacheRead
        self.output = output
        self.requests = requests
    }

    public static let zero = TokenCounts()

    public var total: Int {
        self.freshInput + self.cacheWrite + self.cacheRead + self.output
    }

    public static func + (lhs: TokenCounts, rhs: TokenCounts) -> TokenCounts {
        TokenCounts(
            freshInput: lhs.freshInput + rhs.freshInput,
            cacheWrite: lhs.cacheWrite + rhs.cacheWrite,
            cacheRead: lhs.cacheRead + rhs.cacheRead,
            output: lhs.output + rhs.output,
            requests: lhs.requests + rhs.requests)
    }

    public static func += (lhs: inout TokenCounts, rhs: TokenCounts) {
        lhs = lhs + rhs
    }
}

/// Local calendar day key, e.g. `2026-10-14`.
public struct DayKey: Hashable, Comparable, Codable, Sendable, CustomStringConvertible {
    public let rawValue: String

    public init(_ rawValue: String) {
        self.rawValue = rawValue
    }

    public init(date: Date, calendar: Calendar = .current) {
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        self.rawValue = String(format: "%04d-%02d-%02d", parts.year ?? 0, parts.month ?? 0, parts.day ?? 0)
    }

    public var description: String {
        self.rawValue
    }

    public static func < (lhs: DayKey, rhs: DayKey) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

/// Per-provider, per-day token totals.
public struct UsageLedger: Hashable, Sendable {
    public var days: [Provider: [DayKey: TokenCounts]]

    public init(days: [Provider: [DayKey: TokenCounts]] = [:]) {
        self.days = days
    }

    public mutating func add(_ counts: TokenCounts, provider: Provider, day: DayKey) {
        self.days[provider, default: [:]][day, default: .zero] += counts
    }

    public func counts(provider: Provider, from start: DayKey?, through end: DayKey?) -> TokenCounts {
        guard let byDay = self.days[provider] else { return .zero }
        return byDay.reduce(into: TokenCounts.zero) { result, entry in
            if let start, entry.key < start { return }
            if let end, end < entry.key { return }
            result += entry.value
        }
    }

    public var firstDay: DayKey? {
        self.days.values.flatMap(\.keys).min()
    }
}
