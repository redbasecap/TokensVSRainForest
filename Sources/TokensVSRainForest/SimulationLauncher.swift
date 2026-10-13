import AppKit
import RainforestCore

/// Opens the bundled web simulation with the user's 30-day average injected.
@MainActor
enum SimulationLauncher {
    static func open(store: UsageStore) {
        guard let template = Bundle.main.url(forResource: "simulation", withExtension: "html")
            .flatMap({ try? String(contentsOf: $0, encoding: .utf8) })
        else {
            NSWorkspace.shared.open(URL(string: "https://github.com/redbasecap/TokensVSRainForest/tree/main/web")!)
            return
        }
        let calendar = Calendar.current
        let today = DayKey(date: Date(), calendar: calendar)
        let start = Period.month.startDate(calendar: calendar).map { DayKey(date: $0, calendar: calendar) }
        let summary = UsageSummary(ledger: store.ledger, from: start, through: today, grid: store.grid)
        let json = (try? JSONEncoder().encode(summary)).flatMap { String(data: $0, encoding: .utf8) } ?? "null"
        let html = "<!doctype html>\n" + template.replacingOccurrences(
            of: "/*TVR_DATA*/", with: "window.TVR_DATA = \(json);")

        let directory = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("TokensVSRainForest", isDirectory: true)
        let file = directory.appendingPathComponent("simulation.html")
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try html.write(to: file, atomically: true, encoding: .utf8)
            NSWorkspace.shared.open(file)
        } catch {
            NSSound.beep()
        }
    }
}
