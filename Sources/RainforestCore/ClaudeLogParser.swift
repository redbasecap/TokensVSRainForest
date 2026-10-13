import Foundation

/// One assistant response with usage from a Claude Code session log.
struct ClaudeUsageEntry: Hashable, Sendable {
    let key: String?
    let day: DayKey
    let counts: TokenCounts
    let isIncomplete: Bool
}

/// Parses `~/.claude/projects/**/*.jsonl`. Mirrors CodexBar: streaming writes repeat a response several times,
/// so rows are keyed by `message.id` + `requestId` and the final chunk wins.
enum ClaudeLogParser {
    static func parse(data: Data, calendar: Calendar) -> [ClaudeUsageEntry] {
        var entries: [ClaudeUsageEntry] = []
        JSONL.forEachLine(in: data, containing: [#""type":"assistant""#, #""usage""#]) { line in
            guard let obj = JSONL.object(line),
                  obj["type"] as? String == "assistant",
                  let message = obj["message"] as? [String: Any],
                  let usage = message["usage"] as? [String: Any],
                  let timestampText = obj["timestamp"] as? String,
                  let timestamp = Timestamps.parse(timestampText)
            else { return }

            let input = intValue(usage["input_tokens"])
            let cacheWrite = intValue(usage["cache_creation_input_tokens"])
            let cacheRead = intValue(usage["cache_read_input_tokens"])
            let output = intValue(usage["output_tokens"])
            guard input + cacheWrite + cacheRead + output > 0 else { return }

            // Proxies may log a cache-unaware estimate in message_start (same rule as CodexBar).
            let isIncomplete = message["stop_reason"] is NSNull && input > 0 && output == 0
                && usage["cache_read_input_tokens"] == nil && usage["cache_creation_input_tokens"] == nil

            var key: String?
            if let messageId = message["id"] as? String, !messageId.isEmpty {
                if let requestId = obj["requestId"] as? String {
                    key = "\(messageId)|\(requestId)"
                } else if let sessionId = obj["sessionId"] as? String, !sessionId.isEmpty {
                    key = "\(messageId)|session:\(sessionId)"
                }
            }

            entries.append(ClaudeUsageEntry(
                key: key,
                day: DayKey(date: timestamp, calendar: calendar),
                counts: TokenCounts(
                    freshInput: input,
                    cacheWrite: cacheWrite,
                    cacheRead: cacheRead,
                    output: output,
                    requests: 1),
                isIncomplete: isIncomplete))
        }
        return entries
    }

    /// Deduplicates across all files (resumed sessions copy earlier responses into new files).
    static func ledger(from files: [[ClaudeUsageEntry]]) -> [DayKey: TokenCounts] {
        var keyed: [String: ClaudeUsageEntry] = [:]
        var result: [DayKey: TokenCounts] = [:]
        for entries in files {
            for entry in entries {
                guard let key = entry.key else {
                    result[entry.day, default: .zero] += entry.counts
                    continue
                }
                if let existing = keyed[key], entry.isIncomplete, !existing.isIncomplete { continue }
                keyed[key] = entry
            }
        }
        for entry in keyed.values {
            result[entry.day, default: .zero] += entry.counts
        }
        return result
    }
}
