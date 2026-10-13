import Foundation
import Testing
@testable import RainforestCore

struct UsageLimitsTests {
    @Test
    func `Codex limits come from the newest token_count event`() {
        let log = [
            #"{"timestamp":"2026-10-10T11:29:31.661Z","type":"event_msg","payload":{"type":"token_count","info":null,"rate_limits":{"primary":{"used_percent":1.0,"window_minutes":10080,"resets_at":1791996121},"secondary":null,"plan_type":"prolite"}}}"#,
            #"{"timestamp":"2026-10-10T12:00:00.000Z","type":"event_msg","payload":{"type":"token_count","info":null,"rate_limits":{"primary":{"used_percent":42.5,"window_minutes":300,"resets_at":1791999000},"secondary":{"used_percent":7,"window_minutes":10080,"resets_at":1792500000},"plan_type":"pro"}}}"#,
        ].joined(separator: "\n")
        let result = CodexLogParser.parseWithLimits(data: Data(log.utf8), calendar: .current)
        let limits = try! #require(result.limits)
        #expect(limits.plan == "pro")
        #expect(limits.windows == [
            LimitWindow(label: "5 Stunden", usedPercent: 42.5, resetsAt: Date(timeIntervalSince1970: 1_791_999_000)),
            LimitWindow(label: "Woche", usedPercent: 7, resetsAt: Date(timeIntervalSince1970: 1_792_500_000)),
        ])
        #expect(result.entries.isEmpty) // info: null carries no tokens
    }

    @Test
    func `expired windows reset to zero`() {
        let window = LimitWindow(label: "Woche", usedPercent: 80, resetsAt: Date(timeIntervalSince1970: 100))
        #expect(window.current(now: Date(timeIntervalSince1970: 200)).usedPercent == 0)
        #expect(window.current(now: Date(timeIntervalSince1970: 50)).usedPercent == 80)
    }

    @Test
    func `Claude usage response is decoded`() {
        let json = #"{"five_hour":{"utilization":37.0,"resets_at":"2026-10-14T05:00:00.000+00:00"},"seven_day":{"utilization":12,"resets_at":"2026-10-18T09:00:00Z"},"seven_day_opus":null}"#
        let limits = try! #require(ClaudeLimitsClient.decode(Data(json.utf8), plan: "max"))
        #expect(limits.provider == .claude)
        #expect(limits.plan == "max")
        #expect(limits.windows.map(\.label) == ["5 Stunden", "Woche"])
        #expect(limits.windows.map(\.usedPercent) == [37, 12])
        #expect(limits.windows[1].resetsAt == ISO8601DateFormatter().date(from: "2026-10-18T09:00:00Z"))
    }

    @Test
    func `Claude Code credential JSON is parsed`() {
        let json = #"{"claudeAiOauth":{"accessToken":"tok","refreshToken":"r","expiresAt":1791999000000,"subscriptionType":"max"}}"#
        let credentials = try! #require(ClaudeCredentials.parse(Data(json.utf8)))
        #expect(credentials.accessToken == "tok")
        #expect(credentials.subscriptionType == "max")
        #expect(credentials.expiresAt == Date(timeIntervalSince1970: 1_791_999_000))
        #expect(ClaudeCredentials.parse(Data("{}".utf8)) == nil)
    }
}
