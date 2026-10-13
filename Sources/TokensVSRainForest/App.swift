import AppKit
import RainforestCore
import SwiftUI

@main
struct TokensVSRainForestApp: App {
    @State private var store = UsageStore()

    init() {
        SnapshotExporter.runIfRequested()
        NSApplication.shared.setActivationPolicy(.accessory)
    }

    var body: some Scene {
        MenuBarExtra {
            PopoverView(store: self.store)
        } label: {
            MenuBarLabel(impact: self.store.todayImpact)
        }
        .menuBarExtraStyle(.window)

        Window("Quellen & Rechnung", id: "sources") {
            SourcesView(store: self.store)
        }
        .windowResizability(.contentSize)
    }
}

/// Tiny pixel tree in the menu bar; it catches fire once today's tokens cost anything.
struct MenuBarLabel: View {
    let impact: Impact

    var body: some View {
        HStack(spacing: 3) {
            Image(nsImage: MenuBarIcon.image(burning: self.impact.co2Kg > 0))
            Text(Format.co2(self.impact.co2Kg))
        }
    }
}

enum MenuBarIcon {
    static func image(burning: Bool) -> NSImage {
        let pixel: CGFloat = 2
        let image = NSImage(size: NSSize(width: 9 * pixel, height: 9 * pixel), flipped: true) { _ in
            func fill(_ x: Int, _ y: Int, _ w: Int, _ h: Int, _ hex: UInt32) {
                NSColor(
                    red: CGFloat((hex >> 16) & 0xFF) / 255,
                    green: CGFloat((hex >> 8) & 0xFF) / 255,
                    blue: CGFloat(hex & 0xFF) / 255,
                    alpha: 1).setFill()
                NSRect(x: CGFloat(x) * pixel, y: CGFloat(y) * pixel, width: CGFloat(w) * pixel,
                       height: CGFloat(h) * pixel).fill()
            }
            fill(2, 1, 5, 4, 0x3FA34D)
            fill(1, 2, 7, 2, 0x3FA34D)
            fill(3, 1, 2, 1, 0x57C25F)
            fill(4, 5, 1, 4, 0x7D5733)
            fill(3, 2, 1, 1, 0x1B1B1B)
            fill(5, 2, 1, 1, 0x1B1B1B)
            if burning {
                fill(6, 0, 2, 2, 0xFF7B1C)
                fill(7, 1, 1, 2, 0xFFE45C)
                fill(1, 3, 1, 1, 0xE8452C)
            }
            return true
        }
        image.isTemplate = false
        return image
    }
}
