import CoreGraphics

enum GameConstants {
    /// Side length of one arena tile in points.
    static let tileSize: CGFloat = 64
    /// How tall a wall block is drawn beyond its tile footprint (the fake-3D front face).
    static let wallFaceHeight: CGFloat = 24
}

/// zPosition bands. Y-sorted entities live between `ySortBase` and `ySortBase + ySortRange`.
enum ZLayer {
    static let ground: CGFloat = 0
    static let groundDecal: CGFloat = 10
    static let shadow: CGFloat = 50
    static let ySortBase: CGFloat = 100
    static let ySortRange: CGFloat = 500
    static let bushCanopy: CGFloat = 700
    static let hud: CGFloat = 1000

    /// Convert a node's baseline (feet) world y into a zPosition so lower-on-screen draws in front.
    static func ySorted(baselineY: CGFloat, mapPixelHeight: CGFloat) -> CGFloat {
        let t = 1 - (baselineY / max(mapPixelHeight, 1))
        return ySortBase + t * ySortRange
    }
}

struct PhysicsCategory {
    static let none: UInt32 = 0
    static let fighter: UInt32 = 1 << 0
    static let wall: UInt32 = 1 << 1
    static let water: UInt32 = 1 << 2
    static let projectile: UInt32 = 1 << 3
    static let lootBox: UInt32 = 1 << 4
    static let pickup: UInt32 = 1 << 5
}
