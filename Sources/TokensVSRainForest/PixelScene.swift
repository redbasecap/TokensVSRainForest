import RainforestCore
import SwiftUI

// MARK: - Pixel helpers

extension Color {
    init(hex: UInt32, opacity: Double = 1) {
        self.init(
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255,
            opacity: opacity)
    }
}

enum Palette {
    static let skyTop = Color(hex: 0x8ED6FF)
    static let skyBands: [Color] = [0x8ED6FF, 0x9FDDFF, 0xB2E5FF, 0xC6EEFF].map { Color(hex: $0) }
    static let grass: [Color] = [0x5BBF4A, 0x4CA83E, 0x6ACD58].map { Color(hex: $0) }
    static let dirt: [Color] = [0x8B5A2B, 0x7A4B22, 0x9A6634].map { Color(hex: $0) }
    static let leaves: [Color] = [0x2E8B3A, 0x3FA34D, 0x57C25F, 0x23702E].map { Color(hex: $0) }
    static let log: [Color] = [0x6B4A2B, 0x7D5733, 0x5A3D22].map { Color(hex: $0) }
    static let charcoal: [Color] = [0x2B2B2B, 0x3A3330, 0x222020].map { Color(hex: $0) }
    static let flame: [Color] = [0xFFE45C, 0xFFB627, 0xFF7B1C, 0xE8452C].map { Color(hex: $0) }
    static let ember = Color(hex: 0xFF6A00)
    static let eye = Color(hex: 0x1B1B1B)
    static let blush = Color(hex: 0xFF8FA3)
    static let sun = Color(hex: 0xFFE066)
    static let sunEdge = Color(hex: 0xFFC233)
    static let cloud = Color(hex: 0xFFFFFF)
    static let smoke = Color(hex: 0x6E6E6E)
}

/// Deterministic per-pixel noise in 0..<1.
func noise(_ x: Int, _ y: Int, _ seed: Int = 0) -> Double {
    var h = UInt64(bitPattern: Int64(x &* 374_761_393 &+ y &* 668_265_263 &+ seed &* 2_147_483_647))
    h = (h ^ (h >> 13)) &* 1_274_126_177
    h ^= h >> 16
    return Double(h & 0xFFFF) / 65536
}

struct PixelPainter {
    var context: GraphicsContext
    let scale: CGFloat
    let origin: CGPoint

    func fill(_ x: Int, _ y: Int, _ w: Int = 1, _ h: Int = 1, _ color: Color) {
        let rect = CGRect(
            x: self.origin.x + CGFloat(x) * self.scale,
            y: self.origin.y + CGFloat(y) * self.scale,
            width: CGFloat(w) * self.scale,
            height: CGFloat(h) * self.scale)
        self.context.fill(Path(rect), with: .color(color))
    }

    func pick(_ colors: [Color], _ x: Int, _ y: Int, _ seed: Int = 0) -> Color {
        colors[Int(noise(x, y, seed) * Double(colors.count)) % colors.count]
    }
}

// MARK: - Scene

/// Cute Minecraft-style rainforest that burns in proportion to the CO₂ equivalent of the tokens.
struct PixelSceneView: View {
    let impact: Impact

    nonisolated static let width = 80
    nonisolated static let height = 48
    nonisolated static let groundY = 40

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 12.0)) { timeline in
            Canvas { context, size in
                Self.render(context: context, size: size, impact: self.impact,
                            t: timeline.date.timeIntervalSinceReferenceDate)
            }
        }
        .aspectRatio(CGFloat(Self.width) / CGFloat(Self.height), contentMode: .fit)
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .accessibilityLabel(Text(SceneLevel(impact: self.impact).accessibilityText))
    }

    nonisolated static func render(context: GraphicsContext, size: CGSize, impact: Impact, t: Double) {
        let scale = max(1, floor(min(size.width / CGFloat(Self.width), size.height / CGFloat(Self.height))))
        let origin = CGPoint(
            x: (size.width - CGFloat(Self.width) * scale) / 2,
            y: (size.height - CGFloat(Self.height) * scale) / 2)
        let painter = PixelPainter(context: context, scale: scale, origin: origin)
        SceneRenderer(painter: painter, impact: impact, t: t).draw()
    }
}

enum SceneLevel {
    /// Less than one block burned: zoom into a single 16 × 16 leaf block.
    case block(pixels: Double)
    /// Less than one tree burned: one big tree made of blocks.
    case tree(blocks: Double)
    /// Whole trees burned: a forest of mini trees.
    case forest(trees: Double)

    init(impact: Impact) {
        if impact.pixels < Double(Methodology.pixelsPerBlock) {
            self = .block(pixels: impact.pixels)
        } else if impact.blocks < Double(Methodology.blocksPerTree) {
            self = .tree(blocks: impact.blocks)
        } else {
            self = .forest(trees: impact.trees)
        }
    }

    var accessibilityText: String {
        switch self {
        case let .block(pixels): String(format: "%.0f von 256 Pixeln eines Blatt-Blocks verbrannt", pixels)
        case let .tree(blocks): String(format: "%.1f von 40 Blöcken eines Baumes verbrannt", blocks)
        case let .forest(trees): String(format: "%.2f Regenwaldbäume verbrannt", trees)
        }
    }
}

private struct SceneRenderer {
    let painter: PixelPainter
    let impact: Impact
    let t: Double

    private var w: Int { PixelSceneView.width }
    private var h: Int { PixelSceneView.height }
    private var groundY: Int { PixelSceneView.groundY }

    func draw() {
        let level = SceneLevel(impact: self.impact)
        self.drawSky()
        self.drawSun()
        self.drawClouds()
        self.drawGround()
        switch level {
        case let .block(pixels):
            self.drawBlockZoom(burnedPixels: pixels)
        case let .tree(blocks):
            self.drawSideBushes()
            self.drawTree(originX: self.w / 2, groundY: self.groundY, blockSize: 4, burnedBlocks: blocks, face: true)
        case let .forest(trees):
            self.drawForest(trees: trees)
        }
        if self.impact.co2Kg <= 0 {
            self.drawButterflies()
        }
        self.drawParrot()
    }

    // MARK: Background

    private func drawSky() {
        let bandHeight = self.groundY / Palette.skyBands.count + 1
        for (index, color) in Palette.skyBands.enumerated() {
            self.painter.fill(0, index * bandHeight, self.w, bandHeight, color)
        }
        // Haze grows with the fire, capped so the scene stays cute.
        let haze = min(0.35, log10(1 + self.impact.pixels) / 12)
        if haze > 0 {
            self.painter.fill(0, 0, self.w, self.groundY, Color(hex: 0xFFB27A, opacity: haze))
        }
    }

    private func drawSun() {
        let x = 71, y = 3
        self.painter.fill(x + 1, y, 5, 7, Palette.sun)
        self.painter.fill(x, y + 1, 7, 5, Palette.sun)
        self.painter.fill(x, y + 1, 1, 5, Palette.sunEdge)
        self.painter.fill(x + 6, y + 1, 1, 5, Palette.sunEdge)
        let blink = fmod(self.t, 5) < 0.15
        if !blink {
            self.painter.fill(x + 2, y + 3, 1, 1, Palette.eye)
            self.painter.fill(x + 4, y + 3, 1, 1, Palette.eye)
        }
        self.painter.fill(x + 1, y + 4, 1, 1, Palette.blush)
        self.painter.fill(x + 5, y + 4, 1, 1, Palette.blush)
        if self.impact.co2Kg > 0 {
            self.painter.fill(x + 3, y + 5, 1, 1, Palette.eye) // small worried "o"
        } else {
            self.painter.fill(x + 2, y + 5, 3, 1, Palette.eye)
        }
    }

    private func drawClouds() {
        let clouds: [(y: Int, offset: Double, speed: Double)] = [(5, 0, 1.2), (12, 37, 1.7)]
        for cloud in clouds {
            let span = Double(self.w + 16)
            let x = Int(fmod(self.t * cloud.speed + cloud.offset, span)) - 12
            let y = cloud.y
            self.painter.fill(x + 2, y, 5, 1, Palette.cloud)
            self.painter.fill(x, y + 1, 10, 2, Palette.cloud)
            self.painter.fill(x + 1, y + 3, 7, 1, Palette.cloud.opacity(0.85))
        }
    }

    private func drawGround() {
        for x in 0..<self.w {
            for y in self.groundY..<self.h {
                let color = y < self.groundY + 2
                    ? self.painter.pick(Palette.grass, x, y)
                    : self.painter.pick(Palette.dirt, x, y)
                self.painter.fill(x, y, 1, 1, color)
            }
            // Grass blades hanging over the dirt, like the Minecraft grass block side.
            if noise(x, 99) > 0.6 {
                self.painter.fill(x, self.groundY + 2, 1, 1, Palette.grass[1])
            }
        }
    }

    private func drawSideBushes() {
        for x in [4, 68] {
            for dy in 0..<4 {
                for dx in 0..<8 where !(dy == 3 && (dx == 0 || dx == 7)) {
                    self.painter.fill(x + dx, self.groundY - 1 - dy, 1, 1, self.painter.pick(Palette.leaves, x + dx, dy, 3))
                }
            }
        }
    }

    // MARK: Fire

    private func flameColor(_ x: Int, _ y: Int) -> Color {
        let flicker = Int(self.t * 10 + noise(x, y, 7) * 10)
        return Palette.flame[(flicker + Int(noise(x, y) * 4)) % Palette.flame.count]
    }

    /// A flickering flame tongue rising from (x, y).
    private func drawFlameTongue(_ x: Int, _ y: Int, maxHeight: Int) {
        let height = 1 + Int((sin(self.t * 9 + noise(x, y, 5) * 6.28) + 1) / 2 * Double(maxHeight))
        // Hot yellow at the base, red at the tip.
        for dy in 0..<height {
            self.painter.fill(x, y - dy, 1, 1, Palette.flame[min(Palette.flame.count - 1, dy * Palette.flame.count / height)])
        }
    }

    private func drawSmoke(fromX x: Int, y: Int, seed: Int) {
        let life = 18.0
        let phase = fmod(self.t * 4 + noise(x, y, seed) * life, life)
        let py = y - Int(phase)
        let px = x + Int(sin(phase * 0.6 + Double(seed)) * 1.5)
        guard py >= 0 else { return }
        self.painter.fill(px, py, 2, 2, Palette.smoke.opacity(0.55 * (1 - phase / life)))
    }

    private func drawCharred(_ x: Int, _ y: Int) {
        let glow = noise(x, y, 11) > 0.82 && sin(self.t * 4 + noise(x, y) * 6) > 0
        self.painter.fill(x, y, 1, 1, glow ? Palette.ember : self.painter.pick(Palette.charcoal, x, y))
    }

    // MARK: Level 1 – zoom into one block

    private static let texelOrder: [(x: Int, y: Int)] = {
        var texels: [(x: Int, y: Int, key: Double)] = []
        for y in 0..<16 {
            for x in 0..<16 {
                let dx = Double(x) - 7.5, dy = Double(15 - y)
                texels.append((x, y, (dx * dx + dy * dy).squareRoot() + noise(x, y, 42) * 4))
            }
        }
        return texels.sorted { $0.key < $1.key }.map { ($0.x, $0.y) }
    }()

    private func drawBlockZoom(burnedPixels: Double) {
        // Small happy tree on the left; one of its leaf blocks (2 × 2 px here) is magnified on the right.
        let treeX = 13, tiny = 2
        self.drawTree(originX: treeX, groundY: self.groundY, blockSize: tiny, burnedBlocks: 0, face: false)
        let sourceX = treeX + 3 * tiny - tiny / 2, sourceY = self.groundY - (7 + 1) * tiny
        self.painter.fill(sourceX - 1, sourceY - 1, tiny + 2, 1, Palette.cloud)
        self.painter.fill(sourceX - 1, sourceY + tiny, tiny + 2, 1, Palette.cloud)
        self.painter.fill(sourceX - 1, sourceY, 1, tiny, Palette.cloud)
        self.painter.fill(sourceX + tiny, sourceY, 1, tiny, Palette.cloud)

        let size = 2, bx = 34, by = self.groundY - 16 * size - 2
        // Dotted zoom lines from the marked block to the magnified block's corners.
        let fromX = sourceX + tiny + 1
        for step in stride(from: 1, to: 12, by: 2) {
            let f = Double(step) / 12
            let x = fromX + Int(f * Double(bx - 1 - fromX))
            self.painter.fill(x, sourceY - 1 + Int(f * Double(by - sourceY)), 1, 1, Palette.cloud)
            self.painter.fill(x, sourceY + tiny + Int(f * Double(by + 16 * size - sourceY - tiny)), 1, 1, Palette.cloud)
        }
        // Frame.
        self.painter.fill(bx - 1, by - 1, 16 * size + 2, 16 * size + 2, Color(hex: 0x1E3A1F))

        let burned = min(256, Int(burnedPixels.rounded(.up)))
        let fresh = max(3, burned / 6)
        var state = Array(repeating: 0, count: 256) // 0 leaf, 1 charred, 2 burning
        for (index, texel) in Self.texelOrder.prefix(burned).enumerated() {
            state[texel.y * 16 + texel.x] = index >= burned - fresh ? 2 : 1
        }
        for y in 0..<16 {
            for x in 0..<16 {
                let px = bx + x * size, py = by + y * size
                switch state[y * 16 + x] {
                case 1:
                    self.drawCharred(px, py)
                    self.painter.fill(px + 1, py, 1, 2, self.painter.pick(Palette.charcoal, px + 1, py))
                    self.painter.fill(px, py + 1, 1, 1, self.painter.pick(Palette.charcoal, px, py + 1))
                case 2:
                    self.painter.fill(px, py, size, size, self.flameColor(px, py))
                default:
                    self.painter.fill(px, py, size, size, self.painter.pick(Palette.leaves, x, y, 1))
                }
            }
        }
        self.drawBlockFace(bx: bx, by: by, size: size, state: state, worried: burned > 0)
        // Flames and smoke over the burning front.
        for (index, texel) in Self.texelOrder.prefix(burned).enumerated() where index >= burned - fresh {
            if noise(texel.x, texel.y, 3) > 0.5 {
                self.drawFlameTongue(bx + texel.x * size, by + texel.y * size - 1, maxHeight: 3)
            }
            if noise(texel.x, texel.y, 9) > 0.7 {
                self.drawSmoke(fromX: bx + texel.x * size, y: by + texel.y * size - 3, seed: index)
            }
        }
    }

    private func drawBlockFace(bx: Int, by: Int, size: Int, state: [Int], worried: Bool) {
        func texel(_ x: Int, _ y: Int, _ color: Color) {
            guard state[y * 16 + x] == 0 else { return }
            self.painter.fill(bx + x * size, by + y * size, size, size, color)
        }
        let blink = fmod(self.t + 1.3, 4.2) < 0.15
        for (ex, ey) in [(4, 6), (11, 6)] {
            if blink {
                texel(ex, ey + 1, Palette.eye)
                texel(ex + 1, ey + 1, Palette.eye)
            } else {
                texel(ex, ey, Palette.eye)
                texel(ex + 1, ey, Palette.eye)
                texel(ex, ey + 1, Palette.eye)
                texel(ex + 1, ey + 1, Palette.eye)
                texel(ex, ey, Palette.cloud) // eye sparkle
            }
        }
        texel(3, 9, Palette.blush)
        texel(4, 9, Palette.blush)
        texel(12, 9, Palette.blush)
        texel(13, 9, Palette.blush)
        if worried {
            texel(7, 10, Palette.eye)
            texel(8, 10, Palette.eye)
            texel(7, 11, Palette.eye)
            texel(8, 11, Palette.eye)
            texel(13, 4, Color(hex: 0x7FD3FF)) // sweat drop
            texel(13, 5, Color(hex: 0x7FD3FF))
        } else {
            texel(6, 10, Palette.eye)
            texel(9, 10, Palette.eye)
            texel(7, 11, Palette.eye)
            texel(8, 11, Palette.eye)
        }
    }

    // MARK: Level 2 – one tree of blocks

    private func drawTree(originX: Int, groundY: Int, blockSize: Int, burnedBlocks: Double, face: Bool) {
        let order = TreeLayout.burnOrder
        let fullyBurned = min(order.count, Int(burnedBlocks))
        let partial = burnedBlocks - Double(fullyBurned)
        var burnState: [TreeLayout.Block: Double] = [:]
        for (index, block) in order.enumerated() {
            if index < fullyBurned {
                burnState[block] = 1
            } else if index == fullyBurned, partial > 0 {
                burnState[block] = partial
            }
        }
        let recent = Set(order.prefix(fullyBurned + 1).suffix(3))

        for block in TreeLayout.blocks {
            let x0 = originX + block.x * blockSize - blockSize / 2
            let y0 = groundY - (block.y + 1) * blockSize
            let burned = burnState[block] ?? 0
            let texels = blockSize * blockSize
            let burnedTexels = Int((burned * Double(texels)).rounded(.up))
            for ty in 0..<blockSize {
                for tx in 0..<blockSize {
                    let x = x0 + tx, y = y0 + ty
                    // Burn texels bottom-up inside a block.
                    let rank = (blockSize - 1 - ty) * blockSize + tx
                    if rank < burnedTexels {
                        if recent.contains(block), noise(x, y, 2) > 0.45 {
                            self.painter.fill(x, y, 1, 1, self.flameColor(x, y))
                        } else {
                            self.drawCharred(x, y)
                        }
                    } else if block.isLog {
                        let ring = (tx == 0 || tx == blockSize - 1) ? Palette.log[2] : self.painter.pick(Palette.log, x, y)
                        self.painter.fill(x, y, 1, 1, ring)
                    } else {
                        self.painter.fill(x, y, 1, 1, self.painter.pick(Palette.leaves, x, y))
                    }
                }
            }
            if burned > 0, recent.contains(block), blockSize >= 3 {
                self.drawFlameTongue(x0 + Int(noise(block.x, block.y) * Double(blockSize)), y0 - 1, maxHeight: blockSize + 1)
                self.drawSmoke(fromX: x0 + 1, y: y0 - 3, seed: block.x * 31 + block.y)
            }
        }

        guard face else { return }
        // Face on the canopy, row 6: worried as soon as anything burns.
        let faceY = groundY - 7 * blockSize + 1
        let leftEye = TreeLayout.Block(x: -1, y: 6, isLog: false)
        let rightEye = TreeLayout.Block(x: 1, y: 6, isLog: false)
        let worried = burnedBlocks > 0
        let blink = fmod(self.t + 0.7, 3.8) < 0.15
        for eye in [leftEye, rightEye] where burnState[eye] == nil {
            let ex = originX + eye.x * blockSize - 1
            self.painter.fill(ex, faceY + (blink ? 1 : 0), 2, blink ? 1 : 2, Palette.eye)
            if !blink { self.painter.fill(ex, faceY, 1, 1, Palette.cloud) }
        }
        let mouth = TreeLayout.Block(x: 0, y: 5, isLog: false)
        if burnState[mouth] == nil {
            let mx = originX - 1, my = groundY - 6 * blockSize + 1
            if worried {
                self.painter.fill(mx, my, 2, 2, Palette.eye)
            } else {
                self.painter.fill(mx - 1, my, 1, 1, Palette.eye)
                self.painter.fill(mx + 2, my, 1, 1, Palette.eye)
                self.painter.fill(mx, my + 1, 2, 1, Palette.eye)
            }
            self.painter.fill(originX - 2 * blockSize, my, 2, 1, Palette.blush)
            self.painter.fill(originX + 2 * blockSize - 1, my, 2, 1, Palette.blush)
        }
    }

    // MARK: Level 3 – forest

    private func drawForest(trees: Double) {
        let slots = 18
        let unit = trees <= Double(slots) ? 1.0 : (trees / Double(slots)).rounded(.up)
        let icons = trees / unit
        for row in 0..<2 {
            for column in 0..<9 {
                let index = row == 0 ? column * 2 + 1 : column * 2 // front row burns first
                let x = 6 + column * 9 + (row == 0 ? 4 : 0)
                let ground = self.groundY - (row == 0 ? 6 : 0)
                let burned = max(0, min(1, icons - Double(index)))
                self.drawTree(originX: x, groundY: ground, blockSize: 1,
                              burnedBlocks: burned * Double(Methodology.blocksPerTree), face: false)
                if burned > 0 {
                    self.drawFlameTongue(x + Int(noise(index, 1) * 4) - 2, ground - 9, maxHeight: 3)
                    self.drawSmoke(fromX: x, y: ground - 12, seed: index)
                }
            }
        }
    }

    // MARK: Critters

    private func drawParrot() {
        let period = 16.0
        let phase = fmod(self.t, period) / period
        guard phase < 0.6 else { return }
        let x = Int(phase / 0.6 * Double(self.w + 10)) - 5
        let y = 14 + Int(sin(self.t * 3) * 2)
        let flap = Int(self.t * 8) % 2 == 0
        self.painter.fill(x, y, 3, 2, Color(hex: 0xE53935)) // body
        self.painter.fill(x + 3, y, 1, 1, Color(hex: 0xFFD54F)) // beak
        self.painter.fill(x + 2, y, 1, 1, Palette.eye)
        self.painter.fill(x - 1, y + 1, 1, 1, Color(hex: 0x1E88E5)) // tail
        self.painter.fill(x + 1, flap ? y - 1 : y + 2, 1, 1, Color(hex: 0x1E88E5)) // wing
    }

    private func drawButterflies() {
        for index in 0..<2 {
            let x = 20 + index * 34 + Int(sin(self.t * 0.8 + Double(index)) * 8)
            let y = 26 + Int(cos(self.t * 1.3 + Double(index) * 2) * 4)
            let open = Int(self.t * 6 + Double(index)) % 2 == 0
            let color = index == 0 ? Color(hex: 0xFF8FD8) : Color(hex: 0xFFD54F)
            self.painter.fill(x, y, 1, 1, Palette.eye)
            if open {
                self.painter.fill(x - 1, y - 1, 1, 1, color)
                self.painter.fill(x + 1, y - 1, 1, 1, color)
            } else {
                self.painter.fill(x - 1, y, 1, 1, color)
                self.painter.fill(x + 1, y, 1, 1, color)
            }
        }
    }
}
