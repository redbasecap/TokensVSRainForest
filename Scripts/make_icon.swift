// Renders Resources/AppIcon.png (1024 px): a cute pixel jungle tree with a tiny flame. Run: swift Scripts/make_icon.swift
import AppKit

let size = 1024
let grid = 32
let inset: CGFloat = 100 // macOS icon grid: 824 px body inside 1024
let body = CGFloat(size) - 2 * inset
let cell = body / CGFloat(grid)

func rgb(_ hex: UInt32) -> CGColor {
    CGColor(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255, alpha: 1)
}
func noise(_ x: Int, _ y: Int, _ s: Int) -> Double {
    var h = UInt64(bitPattern: Int64(x &* 374_761_393 &+ y &* 668_265_263 &+ s &* 2_147_483_647))
    h = (h ^ (h >> 13)) &* 1_274_126_177
    h ^= h >> 16
    return Double(h & 0xFFFF) / 65536
}

let space = CGColorSpace(name: CGColorSpace.sRGB)!
let ctx = CGContext(data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: 0, space: space,
                    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
// Flip so y grows downward like the pixel art.
ctx.translateBy(x: 0, y: CGFloat(size))
ctx.scaleBy(x: 1, y: -1)

let rect = CGRect(x: inset, y: inset, width: body, height: body)
let shape = CGPath(roundedRect: rect, cornerWidth: 185, cornerHeight: 185, transform: nil)
// Soft drop shadow.
ctx.saveGState()
ctx.setShadow(offset: CGSize(width: 0, height: 12), blur: 28, color: CGColor(gray: 0, alpha: 0.35))
ctx.addPath(shape); ctx.setFillColor(rgb(0x8ED6FF)); ctx.fillPath()
ctx.restoreGState()
ctx.addPath(shape); ctx.clip()

func px(_ x: Int, _ y: Int, _ c: UInt32, _ w: Int = 1, _ h: Int = 1) {
    ctx.setFillColor(rgb(c))
    ctx.fill(CGRect(x: inset + CGFloat(x) * cell, y: inset + CGFloat(y) * cell,
                    width: CGFloat(w) * cell + 0.5, height: CGFloat(h) * cell + 0.5))
}

// Sky bands.
let bands: [UInt32] = [0x7CCBFF, 0x8ED6FF, 0x9FDDFF, 0xB2E5FF, 0xC6EEFF]
for (i, c) in bands.enumerated() { px(0, i * 5, c, grid, 6) }
// Clouds.
px(3, 5, 0xFFFFFF, 4, 1); px(2, 6, 0xFFFFFF, 7, 2)
px(25, 19, 0xFFFFFF, 3, 1); px(24, 20, 0xFFFFFF, 6, 1)
// Ground: grass + dirt.
for x in 0..<grid {
    for y in 25..<grid {
        let grass: [UInt32] = [0x5BBF4A, 0x4CA83E, 0x6ACD58], dirt: [UInt32] = [0x8B5A2B, 0x7A4B22, 0x9A6634]
        let pal = y < 27 ? grass : dirt
        px(x, y, pal[Int(noise(x, y, 1) * 3) % 3])
    }
    if noise(x, 99, 1) > 0.55 { px(x, 27, 0x4CA83E) }
}
// Trunk.
for y in 17..<25 { for x in 14..<18 { px(x, y, x == 14 || x == 17 ? 0x5A3D22 : (noise(x, y, 2) > 0.5 ? 0x7D5733 : 0x6B4A2B)) } }
// Canopy (blocky, Minecraft-ish).
let leaves: [UInt32] = [0x2E8B3A, 0x3FA34D, 0x57C25F, 0x23702E]
let rows: [(y: Int, from: Int, to: Int)] = [(4, 11, 21), (5, 9, 23), (6, 8, 24), (7, 7, 25), (8, 7, 25), (9, 7, 25),
                                            (10, 7, 25), (11, 7, 25), (12, 7, 25), (13, 7, 25), (14, 8, 24), (15, 9, 23),
                                            (16, 11, 21), (17, 13, 19)]
for r in rows { for x in r.from...r.to { px(x, r.y, leaves[Int(noise(x, r.y, 3) * 4) % 4]) } }
// Highlights on top edge.
for x in stride(from: 11, through: 21, by: 3) { px(x, 4, 0x6ACD58, 2, 1) }
// Face.
px(11, 9, 0x1B1B1B, 2, 3); px(19, 9, 0x1B1B1B, 2, 3)
px(11, 9, 0xFFFFFF); px(19, 9, 0xFFFFFF)
px(9, 12, 0xFF8FA3, 2, 1); px(21, 12, 0xFF8FA3, 2, 1)
px(15, 12, 0x1B1B1B, 2, 2) // little worried "o"
px(23, 8, 0x7FD3FF, 1, 2) // sweat drop
// Flame on the top-right of the canopy.
px(21, 1, 0xE8452C, 2, 1); px(20, 2, 0xFF7B1C, 4, 1); px(20, 3, 0xFFB627, 4, 1); px(21, 4, 0xFFE45C, 3, 1)
px(22, 0, 0xE8452C); px(24, 2, 0xE8452C)
// Parrot friend.
px(4, 14, 0xE53935, 3, 2); px(7, 14, 0xFFD54F); px(6, 14, 0x1B1B1B); px(3, 15, 0x1E88E5); px(5, 13, 0x1E88E5)

let image = ctx.makeImage()!
let rep = NSBitmapImageRep(cgImage: image)
let out = URL(fileURLWithPath: CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "Resources/AppIcon.png")
try FileManager.default.createDirectory(at: out.deletingLastPathComponent(), withIntermediateDirectories: true)
try rep.representation(using: .png, properties: [:])!.write(to: out)
print("wrote \(out.path)")
