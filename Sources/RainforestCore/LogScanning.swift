import Foundation

// MARK: - JSONL helpers

enum JSONL {
    /// Calls `body` for every line that contains all `needles`; lines are decoded lazily by the caller.
    static func forEachLine(in data: Data, containing needles: [String], _ body: (Data) -> Void) {
        let needleBytes = needles.map { Data($0.utf8) }
        data.withUnsafeBytes { (raw: UnsafeRawBufferPointer) in
            guard let base = raw.baseAddress?.assumingMemoryBound(to: UInt8.self) else { return }
            let count = raw.count
            var start = 0
            while start < count {
                var end = start
                while end < count, base[end] != 0x0A {
                    end += 1
                }
                if end > start {
                    let line = Data(bytesNoCopy: UnsafeMutableRawPointer(mutating: base + start),
                                    count: end - start, deallocator: .none)
                    if needleBytes.allSatisfy({ line.range(of: $0) != nil }) {
                        body(Data(line))
                    }
                }
                start = end + 1
            }
        }
    }

    static func object(_ line: Data) -> [String: Any]? {
        (try? JSONSerialization.jsonObject(with: line)) as? [String: Any]
    }
}

func intValue(_ any: Any?) -> Int {
    max(0, (any as? NSNumber)?.intValue ?? 0)
}

enum Timestamps {
    nonisolated(unsafe) static let fractional: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()

    nonisolated(unsafe) static let plain: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f
    }()

    static let lock = NSLock()

    static func parse(_ text: String) -> Date? {
        self.lock.lock()
        defer { self.lock.unlock() }
        return self.fractional.date(from: text) ?? self.plain.date(from: text)
    }
}

// MARK: - File discovery

public struct LogRoots: Sendable {
    public var claude: [URL]
    public var codex: [URL]

    public init(claude: [URL], codex: [URL]) {
        self.claude = claude
        self.codex = codex
    }

    /// Default log locations of Claude Code and Codex CLI. Only plain files are read; nothing touches the Keychain.
    public static func standard(
        environment: [String: String] = ProcessInfo.processInfo.environment,
        home: URL = FileManager.default.homeDirectoryForCurrentUser) -> LogRoots
    {
        var claude: [URL] = []
        if let configDirs = environment["CLAUDE_CONFIG_DIR"], !configDirs.isEmpty {
            for dir in configDirs.split(separator: ",") {
                claude.append(URL(fileURLWithPath: String(dir).trimmingCharacters(in: .whitespaces))
                    .appendingPathComponent("projects"))
            }
        }
        claude.append(home.appendingPathComponent(".claude/projects"))
        claude.append(home.appendingPathComponent(".config/claude/projects"))

        let codexHome = environment["CODEX_HOME"].flatMap { $0.isEmpty ? nil : URL(fileURLWithPath: $0) }
            ?? home.appendingPathComponent(".codex")
        let codex = [
            codexHome.appendingPathComponent("sessions"),
            codexHome.appendingPathComponent("archived_sessions"),
        ]
        return LogRoots(claude: claude, codex: codex)
    }
}

struct LogFile: Hashable, Sendable {
    let url: URL
    let modified: Date
    let size: Int
}

enum LogDiscovery {
    static func jsonlFiles(under roots: [URL], modifiedSince: Date?) -> [LogFile] {
        var seen = Set<String>()
        var files: [LogFile] = []
        let keys: [URLResourceKey] = [.isRegularFileKey, .contentModificationDateKey, .fileSizeKey]
        for root in roots {
            let resolved = root.resolvingSymlinksInPath()
            guard let enumerator = FileManager.default.enumerator(
                at: resolved,
                includingPropertiesForKeys: keys,
                options: [.skipsHiddenFiles])
            else { continue }
            for case let url as URL in enumerator where url.pathExtension == "jsonl" {
                guard let values = try? url.resourceValues(forKeys: Set(keys)),
                      values.isRegularFile == true
                else { continue }
                let modified = values.contentModificationDate ?? .distantPast
                if let modifiedSince, modified < modifiedSince { continue }
                guard seen.insert(url.standardizedFileURL.path).inserted else { continue }
                files.append(LogFile(url: url, modified: modified, size: values.fileSize ?? 0))
            }
        }
        return files
    }
}
