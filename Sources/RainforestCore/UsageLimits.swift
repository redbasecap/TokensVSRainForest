import Foundation

/// One rate-limit window of a subscription, e.g. "5 Stunden" at 42 %.
public struct LimitWindow: Hashable, Sendable {
    public let label: String
    /// 0…100
    public let usedPercent: Double
    public let resetsAt: Date?

    public init(label: String, usedPercent: Double, resetsAt: Date?) {
        self.label = label
        self.usedPercent = min(100, max(0, usedPercent))
        self.resetsAt = resetsAt
    }

    /// A window whose reset time has passed is back at 0 %.
    public func current(now: Date = Date()) -> LimitWindow {
        guard let resetsAt, resetsAt <= now else { return self }
        return LimitWindow(label: self.label, usedPercent: 0, resetsAt: nil)
    }
}

/// Subscription limits of one provider. Identity/plan fields always come from that provider only.
public struct ProviderLimits: Hashable, Sendable {
    public let provider: Provider
    public let plan: String?
    public let windows: [LimitWindow]
    /// When the values were observed (log timestamp or fetch time).
    public let observedAt: Date

    public init(provider: Provider, plan: String?, windows: [LimitWindow], observedAt: Date) {
        self.provider = provider
        self.plan = plan
        self.windows = windows
        self.observedAt = observedAt
    }
}

enum LimitLabels {
    static func window(minutes: Int) -> String {
        switch minutes {
        case 300: "5 Stunden"
        case 10080: "Woche"
        case let m where m % 1440 == 0: "\(m / 1440) Tage"
        case let m where m % 60 == 0: "\(m / 60) Stunden"
        default: "\(minutes) Min."
        }
    }
}

// MARK: - Codex (local logs)

/// Codex writes `rate_limits` into every `token_count` event; the newest one is the current state.
enum CodexLimitParser {
    static func limits(from payload: [String: Any], observedAt: Date) -> ProviderLimits? {
        guard let rateLimits = payload["rate_limits"] as? [String: Any] else { return nil }
        var windows: [LimitWindow] = []
        for key in ["primary", "secondary"] {
            guard let window = rateLimits[key] as? [String: Any],
                  let used = (window["used_percent"] as? NSNumber)?.doubleValue
            else { continue }
            let minutes = (window["window_minutes"] as? NSNumber)?.intValue ?? 0
            let resetsAt = (window["resets_at"] as? NSNumber).map { Date(timeIntervalSince1970: $0.doubleValue) }
                ?? (window["resets_in_seconds"] as? NSNumber)
                .map { observedAt.addingTimeInterval($0.doubleValue) }
            windows.append(LimitWindow(label: LimitLabels.window(minutes: minutes), usedPercent: used,
                                       resetsAt: resetsAt))
        }
        guard !windows.isEmpty else { return nil }
        return ProviderLimits(provider: .codex, plan: rateLimits["plan_type"] as? String, windows: windows,
                              observedAt: observedAt)
    }
}

// MARK: - Claude (opt-in: Keychain + api.anthropic.com)

public enum ClaudeLimitsError: Error, LocalizedError, Equatable {
    case noCredentials
    case expired
    case unauthorized
    case rateLimited
    case server(Int)
    case network(String)
    case unreadable

    public var errorDescription: String? {
        switch self {
        case .noCredentials: "Kein Claude-Code-Login gefunden. Melde dich einmal in Claude Code an."
        case .expired: "Der Claude-Code-Login ist abgelaufen. Starte Claude Code einmal, dann klappt es wieder."
        case .unauthorized: "Anthropic hat den Login abgelehnt. Melde dich in Claude Code neu an."
        case .rateLimited: "Zu viele Abfragen. Versuch es in ein paar Minuten noch einmal."
        case let .server(code): "Anthropic antwortet mit Fehler \(code)."
        case let .network(message): "Keine Verbindung: \(message)"
        case .unreadable: "Die Antwort von Anthropic hat ein unbekanntes Format."
        }
    }
}

public struct ClaudeCredentials: Sendable {
    public let accessToken: String
    public let expiresAt: Date?
    public let subscriptionType: String?

    /// Parses Claude Code's credential JSON (`{"claudeAiOauth": {...}}`), from the Keychain or `.credentials.json`.
    public static func parse(_ data: Data) -> ClaudeCredentials? {
        guard let root = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              let oauth = root["claudeAiOauth"] as? [String: Any],
              let token = oauth["accessToken"] as? String, !token.isEmpty
        else { return nil }
        let expires = (oauth["expiresAt"] as? NSNumber).map { Date(timeIntervalSince1970: $0.doubleValue / 1000) }
        return ClaudeCredentials(accessToken: token, expiresAt: expires,
                                 subscriptionType: oauth["subscriptionType"] as? String)
    }
}

public enum ClaudeLimitsClient {
    static let keychainService = "Claude Code-credentials"

    /// Reads the file first (no prompt); falls back to one Keychain read, which macOS may ask the user to allow.
    public static func loadCredentials(home: URL = FileManager.default.homeDirectoryForCurrentUser)
        throws -> ClaudeCredentials
    {
        let file = home.appendingPathComponent(".claude/.credentials.json")
        if let data = try? Data(contentsOf: file), let credentials = ClaudeCredentials.parse(data) {
            return credentials
        }
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: Self.keychainService,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
              let data = item as? Data,
              let credentials = ClaudeCredentials.parse(data)
        else { throw ClaudeLimitsError.noCredentials }
        return credentials
    }

    public static func fetch(credentials: ClaudeCredentials, session: URLSession = .shared) async throws
        -> ProviderLimits
    {
        if let expiresAt = credentials.expiresAt, expiresAt <= Date() { throw ClaudeLimitsError.expired }
        var request = URLRequest(url: URL(string: "https://api.anthropic.com/api/oauth/usage")!)
        request.timeoutInterval = 20
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.setValue("Bearer \(credentials.accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("oauth-2025-04-20", forHTTPHeaderField: "anthropic-beta")
        request.setValue("TokensVSRainForest", forHTTPHeaderField: "User-Agent")

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            throw ClaudeLimitsError.network(error.localizedDescription)
        }
        switch (response as? HTTPURLResponse)?.statusCode ?? 0 {
        case 200: break
        case 401, 403: throw ClaudeLimitsError.unauthorized
        case 429: throw ClaudeLimitsError.rateLimited
        case let code: throw ClaudeLimitsError.server(code)
        }
        guard let limits = Self.decode(data, plan: credentials.subscriptionType) else {
            throw ClaudeLimitsError.unreadable
        }
        return limits
    }

    /// Decodes `{"five_hour": {"utilization": 42, "resets_at": "…"}, "seven_day": {…}, …}`.
    static func decode(_ data: Data, plan: String?, now: Date = Date()) -> ProviderLimits? {
        guard let root = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else { return nil }
        let keys: [(String, String)] = [
            ("five_hour", "5 Stunden"),
            ("seven_day", "Woche"),
            ("seven_day_opus", "Woche · Opus"),
            ("seven_day_sonnet", "Woche · Sonnet"),
        ]
        let windows: [LimitWindow] = keys.compactMap { key, label in
            guard let window = root[key] as? [String: Any],
                  let used = (window["utilization"] as? NSNumber)?.doubleValue
            else { return nil }
            let resetsAt = (window["resets_at"] as? String).flatMap(Timestamps.parse)
            return LimitWindow(label: label, usedPercent: used, resetsAt: resetsAt)
        }
        guard !windows.isEmpty else { return nil }
        return ProviderLimits(provider: .claude, plan: plan, windows: windows, observedAt: now)
    }
}
