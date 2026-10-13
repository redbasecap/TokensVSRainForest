import Foundation

/// The blocky jungle tree drawn in the app. Its block count defines `Methodology.blocksPerTree`.
public enum TreeLayout {
    public struct Block: Hashable, Sendable {
        /// Column relative to the trunk (negative = left).
        public let x: Int
        /// Row from the ground up.
        public let y: Int
        public let isLog: Bool

        public init(x: Int, y: Int, isLog: Bool) {
            self.x = x
            self.y = y
            self.isLog = isLog
        }
    }

    public static let trunkHeight = 5

    /// Canopy rows from bottom to top as (row, half-width). The trunk passes through the first row.
    private static let canopy: [(y: Int, halfWidth: Int)] = [(4, 3), (5, 3), (6, 3), (7, 3), (8, 2), (9, 1)]

    public static let blocks: [Block] = {
        var blocks = (0..<trunkHeight).map { Block(x: 0, y: $0, isLog: true) }
        for row in canopy {
            for x in -row.halfWidth...row.halfWidth where !(x == 0 && row.y < trunkHeight) {
                blocks.append(Block(x: x, y: row.y, isLog: false))
            }
        }
        return blocks
    }()

    /// Burn order: fire eats the canopy from the top down, the trunk goes last.
    public static let burnOrder: [Block] = blocks.sorted { lhs, rhs in
        if lhs.isLog != rhs.isLog { return !lhs.isLog }
        if lhs.y != rhs.y { return lhs.y > rhs.y }
        return abs(lhs.x) > abs(rhs.x) || (abs(lhs.x) == abs(rhs.x) && lhs.x < rhs.x)
    }

    public static let width = 2 * (canopy.map(\.halfWidth).max() ?? 0) + 1
    public static let height = (canopy.map(\.y).max() ?? 0) + 1
}
