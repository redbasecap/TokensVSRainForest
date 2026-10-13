import Foundation

/// Reads local Claude Code and Codex logs into a `UsageLedger`, re-parsing only files that changed.
public actor UsageLoader {
    private struct CacheKey: Hashable {
        let modified: Date
        let size: Int
    }

    private let roots: LogRoots
    private let calendar: Calendar
    private var claudeCache: [String: (CacheKey, [ClaudeUsageEntry])] = [:]
    private var codexCache: [String: (CacheKey, CodexLogParser.ParseResult)] = [:]

    public init(roots: LogRoots = .standard(), calendar: Calendar = .current) {
        self.roots = roots
        self.calendar = calendar
    }

    /// - Parameter since: files last modified before this date are skipped (they cannot contain newer entries).
    public func load(since: Date?) -> UsageLedger {
        let claudeFiles = LogDiscovery.jsonlFiles(under: self.roots.claude, modifiedSince: since)
        let codexFiles = LogDiscovery.jsonlFiles(under: self.roots.codex, modifiedSince: since)

        let claudeEntries = claudeFiles.sorted { $0.modified < $1.modified }.compactMap { file in
            self.cached(file, cache: &self.claudeCache) { ClaudeLogParser.parse(data: $0, calendar: self.calendar) }
        }
        let codexResults = codexFiles.sorted { $0.modified < $1.modified }.compactMap { file in
            self.cached(file, cache: &self.codexCache) {
                CodexLogParser.parseWithLimits(data: $0, calendar: self.calendar)
            }
        }
        self.latestCodexLimits = codexResults.compactMap(\.limits).max { $0.observedAt < $1.observedAt }

        var ledger = UsageLedger()
        ledger.days[.claude] = ClaudeLogParser.ledger(from: claudeEntries)
        ledger.days[.codex] = CodexLogParser.ledger(from: codexResults.map(\.entries))
        return ledger
    }

    public func latestCodexLimitsAfterLoad(since: Date?) -> ProviderLimits? {
        _ = self.load(since: since)
        return self.latestCodexLimits
    }

    /// Newest Codex rate-limit snapshot seen by the last `load`.
    public private(set) var latestCodexLimits: ProviderLimits?

    private func cached<Result: Sendable>(
        _ file: LogFile,
        cache: inout [String: (CacheKey, Result)],
        parse: (Data) -> Result) -> Result?
    {
        let key = CacheKey(modified: file.modified, size: file.size)
        if let hit = cache[file.url.path], hit.0 == key { return hit.1 }
        guard let data = try? Data(contentsOf: file.url, options: .mappedIfSafe) else { return nil }
        let entries = autoreleasepool { parse(data) }
        cache[file.url.path] = (key, entries)
        return entries
    }
}
