import SpriteKit

/// The Showdown poison gas: the safe zone shrinks inward on a timer and
/// anyone outside it takes periodic damage.
final class GasRing {
    /// Tiles trimmed from each side of the map so far.
    private(set) var inset = 0
    private let map: ArenaMap
    private let overlay = SKNode()

    private var nextShrinkAt: TimeInterval
    private var nextDamageTickAt: TimeInterval = 0

    private static let firstShrinkDelay: TimeInterval = 18
    private static let shrinkInterval: TimeInterval = 12
    private static let tilesPerShrink = 2
    /// The gas eventually swallows the whole map so matches can't stalemate
    /// (e.g. two survivors camping in bushes, invisible to each other).
    private static let minSafeTiles = 0
    private static let damagePerTick = 500
    private static let tickInterval: TimeInterval = 1.0

    init(map: ArenaMap, startTime: TimeInterval, parent: SKNode) {
        self.map = map
        nextShrinkAt = startTime + Self.firstShrinkDelay
        overlay.zPosition = ZLayer.bushCanopy + 50
        parent.addChild(overlay)
    }

    /// Safe zone in world points.
    var safeRect: CGRect {
        let ts = GameConstants.tileSize
        let margin = CGFloat(inset) * ts
        return CGRect(x: margin, y: margin,
                      width: map.pixelWidth - margin * 2,
                      height: map.pixelHeight - margin * 2)
    }

    var safeCenter: CGPoint {
        CGPoint(x: map.pixelWidth / 2, y: map.pixelHeight / 2)
    }

    /// True once the shrinking margins meet and no safe zone remains.
    /// (Checked directly on the inset because CGRect normalizes negative
    /// sizes — a negative-width safeRect reads back as a phantom positive
    /// rect near the center.)
    var isFullyClosed: Bool {
        CGFloat(inset) * GameConstants.tileSize * 2 >= min(map.pixelWidth, map.pixelHeight)
    }

    func contains(_ point: CGPoint) -> Bool {
        guard !isFullyClosed else { return false }
        return safeRect.contains(point)
    }

    /// Advances the gas. Returns fighters damaged this tick (for kill handling).
    func tick(now: TimeInterval, fighters: [Fighter]) -> [Fighter] {
        let maxInset = (min(map.columns, map.rows) - Self.minSafeTiles) / 2
        if now >= nextShrinkAt, inset < maxInset {
            inset += Self.tilesPerShrink
            nextShrinkAt = now + Self.shrinkInterval
            rebuildOverlay()
        }

        guard now >= nextDamageTickAt else { return [] }
        nextDamageTickAt = now + Self.tickInterval
        guard inset > 0 else { return [] }

        var damaged: [Fighter] = []
        for fighter in fighters where !fighter.isDead && !contains(fighter.position) {
            fighter.takeDamage(Self.damagePerTick, at: now)
            damaged.append(fighter)
        }
        NSLog("NOBLESTARS gas tick inset=%d candidates=%d damaged=%d",
              inset, fighters.count, damaged.count)
        return damaged
    }

    private func rebuildOverlay() {
        overlay.removeAllChildren()
        let gasColor = SKColor(red: 0.55, green: 0.75, blue: 0.2, alpha: 0.4)
        let rect = safeRect
        let w = map.pixelWidth
        let h = map.pixelHeight

        let bands: [CGRect] = [
            CGRect(x: 0, y: rect.maxY, width: w, height: h - rect.maxY),      // top
            CGRect(x: 0, y: 0, width: w, height: rect.minY),                  // bottom
            CGRect(x: 0, y: rect.minY, width: rect.minX, height: rect.height),          // left
            CGRect(x: rect.maxX, y: rect.minY, width: w - rect.maxX, height: rect.height), // right
        ]
        for band in bands where band.width > 0.5 && band.height > 0.5 {
            let node = SKSpriteNode(color: gasColor, size: band.size)
            node.anchorPoint = .zero
            node.position = band.origin
            overlay.addChild(node)
        }
    }
}
