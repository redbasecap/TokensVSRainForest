import AppKit
import RainforestCore
import SwiftUI

/// `TokensVSRainForest --snapshot <dir> [--frames]` renders the scene at fixed CO₂ amounts to PNGs, and with
/// `--frames` also animation frame sequences for README GIFs (see `Scripts/make_gifs.sh`).
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
            self.write(kg: kg, t: 2.4, to: directory.appendingPathComponent("\(name).png"))
        }
        if arguments.contains("--frames") {
            self.writeFrames(directory)
        }
        exit(0)
    }

    /// 12 fps sequences: flickering fire on a tree, a burning leaf block, and the zoom levels as CO₂ grows.
    private static func writeFrames(_ directory: URL) {
        let fps = 12.0
        let sequences: [(String, Int, (Int) -> Double)] = [
            ("frames-tree", 36, { _ in 22.6 * Methodology.co2KgPerBlock }),
            ("frames-block", 36, { _ in 130 * Methodology.co2GramsPerPixel / 1000 }),
            ("frames-progress", 96, { i in
                // Exponential growth from 1 pixel to 6 trees, so every zoom level gets screen time.
                let from = log(Methodology.co2GramsPerPixel / 1000), to = log(6 * Methodology.co2KgPerTree)
                return exp(from + (to - from) * Double(i) / 95)
            }),
        ]
        for (name, count, kg) in sequences {
            let folder = directory.appendingPathComponent(name, isDirectory: true)
            try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            for i in 0..<count {
                self.write(kg: kg(i), t: Double(i) / fps,
                           to: folder.appendingPathComponent(String(format: "frame_%03d.png", i)))
            }
        }
    }

    private static func write(kg: Double, t: Double, to url: URL) {
        let view = Canvas { context, size in
            PixelSceneView.render(context: context, size: size, impact: Impact(co2Kg: kg), t: t)
        }
        .frame(width: 320, height: 192)
        let renderer = ImageRenderer(content: view)
        renderer.scale = 2
        guard let image = renderer.nsImage,
              let tiff = image.tiffRepresentation,
              let png = NSBitmapImageRep(data: tiff)?.representation(using: .png, properties: [:])
        else { return }
        try? png.write(to: url)
    }
}
