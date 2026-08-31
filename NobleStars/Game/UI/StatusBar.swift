import SpriteKit

/// Floating health + ammo display above a fighter's head.
final class StatusBar: SKNode {
    private let barWidth: CGFloat = 46
    private let healthFill: SKSpriteNode
    private let healthBack: SKSpriteNode
    private var ammoPipFills: [SKSpriteNode] = []
    private var pipWidth: CGFloat = 0
    private let pipColor = SKColor(red: 1.0, green: 0.65, blue: 0.1, alpha: 1)
    private let pipEmpty = SKColor(white: 0.15, alpha: 0.55)

    init(healthColor: SKColor) {
        healthBack = SKSpriteNode(color: SKColor(white: 0.12, alpha: 0.7),
                                  size: CGSize(width: barWidth, height: 7))
        healthFill = SKSpriteNode(color: healthColor,
                                  size: CGSize(width: barWidth - 2, height: 5))
        super.init()

        addChild(healthBack)
        healthFill.anchorPoint = CGPoint(x: 0, y: 0.5)
        healthFill.position = CGPoint(x: -(barWidth - 2) / 2, y: 0)
        addChild(healthFill)

        let pipCount = Int(CombatTuning.maxAmmo)
        let gap: CGFloat = 2
        pipWidth = (barWidth - 2 - gap * CGFloat(pipCount - 1)) / CGFloat(pipCount)
        for i in 0..<pipCount {
            let x = -(barWidth - 2) / 2 + CGFloat(i) * (pipWidth + gap)
            // Dark backing pip that the orange fill loads up over, left to right.
            let back = SKSpriteNode(color: pipEmpty, size: CGSize(width: pipWidth, height: 3.5))
            back.anchorPoint = CGPoint(x: 0, y: 0.5)
            back.position = CGPoint(x: x, y: -7)
            addChild(back)

            let fill = SKSpriteNode(color: pipColor, size: CGSize(width: pipWidth, height: 3.5))
            fill.anchorPoint = CGPoint(x: 0, y: 0.5)
            fill.position = CGPoint(x: x, y: -7)
            addChild(fill)
            ammoPipFills.append(fill)
        }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    func update(health: Int, maxHealth: Int, ammo: CGFloat) {
        let fraction = maxHealth > 0 ? CGFloat(health) / CGFloat(maxHealth) : 0
        healthFill.xScale = max(0, min(1, fraction))
        for (i, fill) in ammoPipFills.enumerated() {
            // Each pip fills left-to-right as its share of ammo recharges.
            fill.xScale = max(0, min(1, ammo - CGFloat(i)))
        }
    }
}
