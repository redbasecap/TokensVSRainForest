import Foundation
import Testing
@testable import RainforestCore

struct LogParserTests {
    private var utc: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }

    private func claudeLine(id: String, request: String, ts: String, input: Int, write: Int, read: Int,
                            output: Int, stop: String? = "\"end_turn\"") -> String
    {
        """
        {"type":"assistant","timestamp":"\(ts)","requestId":"\(request)","sessionId":"s1","message":{"id":"\(id)",\
        "model":"claude-sonnet-4-5","stop_reason":\(stop ?? "null"),"usage":{"input_tokens":\(input),\
        "cache_creation_input_tokens":\(write),"cache_read_input_tokens":\(read),"output_tokens":\(output)}}}
        """
    }

    @Test
    func `Claude streaming chunks are deduplicated and the final chunk wins`() {
        let log = [
            #"{"type":"user","timestamp":"2026-10-14T08:00:00.000Z","message":{"content":"hi"}}"#,
            self.claudeLine(id: "m1", request: "r1", ts: "2026-10-14T08:00:01.000Z",
                            input: 3, write: 100, read: 1000, output: 1),
            self.claudeLine(id: "m1", request: "r1", ts: "2026-10-14T08:00:02.000Z",
                            input: 3, write: 100, read: 1000, output: 50),
            self.claudeLine(id: "m2", request: "r2", ts: "2026-10-15T09:00:00.000Z",
                            input: 5, write: 0, read: 2000, output: 20),
        ].joined(separator: "\n")
        let entries = ClaudeLogParser.parse(data: Data(log.utf8), calendar: self.utc)
        // A resumed session repeats m1 in another file; it must not be counted twice.
        let ledger = ClaudeLogParser.ledger(from: [entries, Array(entries.prefix(2))])

        #expect(ledger[DayKey("2026-10-14")] == TokenCounts(
            freshInput: 3, cacheWrite: 100, cacheRead: 1000, output: 50, requests: 1))
        #expect(ledger[DayKey("2026-10-15")] == TokenCounts(freshInput: 5, cacheRead: 2000, output: 20, requests: 1))
    }

    @Test
    func `Codex uses per-request usage and skips repeated totals`() {
        func event(_ ts: String, total: (Int, Int, Int), last: (Int, Int, Int)) -> String {
            """
            {"timestamp":"\(ts)","type":"event_msg","payload":{"type":"token_count","info":{\
            "total_token_usage":{"input_tokens":\(total.0),"cached_input_tokens":\(total.1),"output_tokens":\(total.2),\
            "reasoning_output_tokens":10},"last_token_usage":{"input_tokens":\(last.0),\
            "cached_input_tokens":\(last.1),"output_tokens":\(last.2)}}}}
            """
        }
        let log = [
            event("2026-10-14T10:00:00.000Z", total: (1000, 0, 100), last: (1000, 0, 100)),
            event("2026-10-14T10:00:01.000Z", total: (1000, 0, 100), last: (1000, 0, 100)),
            event("2026-10-14T10:01:00.000Z", total: (2500, 900, 150), last: (1500, 900, 50)),
            #"{"timestamp":"2026-10-14T10:02:00.000Z","type":"event_msg","payload":{"type":"token_count","info":null}}"#,
        ].joined(separator: "\n")
        let entries = CodexLogParser.parse(data: Data(log.utf8), calendar: self.utc)
        // A forked rollout replays the same events; signatures dedupe them.
        let ledger = CodexLogParser.ledger(from: [entries, entries])

        #expect(entries.count == 2)
        #expect(ledger[DayKey("2026-10-14")] == TokenCounts(
            freshInput: 1000 + 600, cacheRead: 900, output: 150, requests: 2))
    }

    @Test
    func `Codex without last usage falls back to total deltas`() {
        let log = [
            #"{"timestamp":"2026-10-14T10:00:00Z","payload":{"type":"token_count","info":{"total_token_usage":{"input_tokens":100,"cached_input_tokens":0,"output_tokens":10}}}}"#,
            #"{"timestamp":"2026-10-14T10:01:00Z","payload":{"type":"token_count","info":{"total_token_usage":{"input_tokens":300,"cached_input_tokens":50,"output_tokens":30}}}}"#,
        ].joined(separator: "\n")
        let ledger = CodexLogParser.ledger(from: [CodexLogParser.parse(data: Data(log.utf8), calendar: self.utc)])
        #expect(ledger[DayKey("2026-10-14")] == TokenCounts(freshInput: 100 + 150, cacheRead: 50, output: 30,
                                                            requests: 2))
    }

    @Test
    func `ledger filters by day range`() {
        var ledger = UsageLedger()
        ledger.add(TokenCounts(output: 1), provider: .claude, day: DayKey("2026-10-01"))
        ledger.add(TokenCounts(output: 2), provider: .claude, day: DayKey("2026-10-14"))
        #expect(ledger.counts(provider: .claude, from: DayKey("2026-10-10"), through: nil).output == 2)
        #expect(ledger.counts(provider: .claude, from: nil, through: nil).output == 3)
        #expect(ledger.firstDay == DayKey("2026-10-01"))
    }
}
