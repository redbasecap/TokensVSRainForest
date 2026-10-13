import Foundation

/// One `token_count` observation from a Codex rollout, already converted to a per-request delta.
struct CodexUsageEntry: Hashable, Sendable {
    /// Timestamp + cumulative totals; forked rollouts replay parent events with identical signatures.
    let signature: String
    let day: DayKey
    let counts: TokenCounts
}

/// Parses `~/.codex/sessions/**/*.jsonl`. Each new `token_count` event is one request: `last_token_usage` is used,
/// falling back to deltas of the cumulative `total_token_usage`. `input_tokens` includes cached tokens and
/// `output_tokens` includes reasoning, so fresh input = input − cached and reasoning is not added again.
enum CodexLogParser {
    private struct Totals: Equatable {
        var input = 0
        var cached = 0
        var output = 0

        init(_ usage: [String: Any]) {
            self.input = intValue(usage["input_tokens"])
            self.cached = min(self.input, max(intValue(usage["cached_input_tokens"]),
                                              intValue(usage["cache_read_input_tokens"])))
            self.output = intValue(usage["output_tokens"])
        }

        init() {}

        func minus(_ other: Totals) -> Totals? {
            var delta = Totals()
            delta.input = self.input - other.input
            delta.cached = self.cached - other.cached
            delta.output = self.output - other.output
            guard delta.input >= 0, delta.cached >= 0, delta.output >= 0 else { return nil }
            return delta
        }

        var counts: TokenCounts {
            TokenCounts(
                freshInput: max(0, self.input - self.cached),
                cacheRead: self.cached,
                output: self.output,
                requests: 1)
        }
    }

    struct ParseResult: Sendable {
        var entries: [CodexUsageEntry] = []
        /// Newest `rate_limits` snapshot in the file.
        var limits: ProviderLimits?
    }

    static func parse(data: Data, calendar: Calendar) -> [CodexUsageEntry] {
        self.parseWithLimits(data: data, calendar: calendar).entries
    }

    static func parseWithLimits(data: Data, calendar: Calendar) -> ParseResult {
        var result = ParseResult()
        var entries: [CodexUsageEntry] = []
        var previous: Totals?
        JSONL.forEachLine(in: data, containing: [#""token_count""#]) { line in
            guard let obj = JSONL.object(line),
                  let payload = obj["payload"] as? [String: Any],
                  payload["type"] as? String == "token_count",
                  let timestampText = obj["timestamp"] as? String,
                  let timestamp = Timestamps.parse(timestampText)
            else { return }
            if let limits = CodexLimitParser.limits(from: payload, observedAt: timestamp),
               limits.observedAt >= (result.limits?.observedAt ?? .distantPast)
            {
                result.limits = limits
            }
            guard let info = payload["info"] as? [String: Any] else { return }

            let delta: Totals
            let signatureTotals: String
            if let totalUsage = info["total_token_usage"] as? [String: Any] {
                let total = Totals(totalUsage)
                defer { previous = total }
                // Codex re-emits token_count without a new request; unchanged totals mean nothing new.
                if total == previous { return }
                if let last = info["last_token_usage"] as? [String: Any] {
                    // Prefer the per-request usage: a resumed or forked file may start with carried-over totals.
                    delta = Totals(last)
                } else if let previous, let diff = total.minus(previous) {
                    delta = diff
                } else {
                    delta = total
                }
                signatureTotals = "\(total.input)/\(total.cached)/\(total.output)"
            } else if let last = info["last_token_usage"] as? [String: Any] {
                delta = Totals(last)
                signatureTotals = "last:\(delta.input)/\(delta.cached)/\(delta.output)"
            } else {
                return
            }
            guard delta.input + delta.output > 0 else { return }
            entries.append(CodexUsageEntry(
                signature: "\(timestampText)|\(signatureTotals)",
                day: DayKey(date: timestamp, calendar: calendar),
                counts: delta.counts))
        }
        result.entries = entries
        return result
    }

    static func ledger(from files: [[CodexUsageEntry]]) -> [DayKey: TokenCounts] {
        var seen = Set<String>()
        var result: [DayKey: TokenCounts] = [:]
        for entries in files {
            for entry in entries where seen.insert(entry.signature).inserted {
                result[entry.day, default: .zero] += entry.counts
            }
        }
        return result
    }
}
