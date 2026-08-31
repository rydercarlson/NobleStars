import SpriteKit

/// Floating health + ammo display above a fighter's head.
final class StatusBar: SKNode {
    private let barWidth: CGFloat = 46
    private let healthFill: SKSpriteNode
    private let healthBack: SKSpriteNode
    private var ammoPips: [SKSpriteNode] = []
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
        let pipWidth = (barWidth - 2 - gap * CGFloat(pipCount - 1)) / CGFloat(pipCount)
        for i in 0..<pipCount {
            let pip = SKSpriteNode(color: pipColor, size: CGSize(width: pipWidth, height: 3.5))
            pip.anchorPoint = CGPoint(x: 0, y: 0.5)
            pip.position = CGPoint(x: -(barWidth - 2) / 2 + CGFloat(i) * (pipWidth + gap), y: -7)
            addChild(pip)
            ammoPips.append(pip)
        }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    func update(health: Int, maxHealth: Int, ammo: CGFloat) {
        let fraction = maxHealth > 0 ? CGFloat(health) / CGFloat(maxHealth) : 0
        healthFill.xScale = max(0, min(1, fraction))
        for (i, pip) in ammoPips.enumerated() {
            pip.color = ammo >= CGFloat(i + 1) ? pipColor : pipEmpty
        }
    }
}
