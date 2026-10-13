import AppKit
import RainforestCore
import SwiftUI

/// `TokensVSRainForest --snapshot <dir>` renders the scene at fixed CO₂ amounts to PNGs (for README and review).
@MainActor
enum SnapshotExporter {
    static func runIfRequested() {
        let arguments = CommandLine.arguments
        guard let index = arguments.firstIndex(of: "--snapshot"), index + 1 < arguments.count else { return }
        let directory = URL(fileURLWithPath: arguments[index + 1], isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let cases: [(String, Double)] = [
            ("0-nothing", 0),
            ("1-block-12px", 12 * Methodology.co2GramsPerPixel / 1000),
            ("2-block-180px", 180 * Methodology.co2GramsPerPixel / 1000),
            ("3-tree-7blocks", 7.4 * Methodology.co2KgPerBlock),
            ("4-tree-30blocks", 30.5 * Methodology.co2KgPerBlock),
            ("5-forest-5trees", 5.3 * Methodology.co2KgPerTree),
        ]
        for (name, kg) in cases {
            let view = Canvas { context, size in
                PixelSceneView.render(context: context, size: size, impact: Impact(co2Kg: kg), t: 2.4)
            }
            .frame(width: 320, height: 192)
            let renderer = ImageRenderer(content: view)
            renderer.scale = 2
            guard let image = renderer.nsImage,
                  let tiff = image.tiffRepresentation,
                  let png = NSBitmapImageRep(data: tiff)?.representation(using: .png, properties: [:])
            else { continue }
            try? png.write(to: directory.appendingPathComponent("\(name).png"))
        }
        exit(0)
    }
}
