import SpriteKit

/// Destructible crate that drops a power cube when broken.
final class LootBox: SKNode {
    private(set) var health = 900
    private let crate: SKShapeNode

    init(mapPixelHeight: CGFloat) {
        let size: CGFloat = 42
        crate = SKShapeNode(rectOf: CGSize(width: size, height: size), cornerRadius: 6)
        crate.fillColor = SKColor(red: 0.8, green: 0.6, blue: 0.25, alpha: 1)
        crate.strokeColor = SKColor(red: 0.5, green: 0.35, blue: 0.12, alpha: 1)
        crate.lineWidth = 3
        crate.position = CGPoint(x: 0, y: 14)

        super.init()

        let shadow = SKShapeNode(ellipseOf: CGSize(width: 46, height: 16))
        shadow.fillColor = SKColor(white: 0, alpha: 0.25)
        shadow.strokeColor = .clear
        addChild(shadow)
        addChild(crate)

        // Cross straps for a crate look.
        let strapV = SKSpriteNode(color: SKColor(red: 0.55, green: 0.4, blue: 0.15, alpha: 1),
                                  size: CGSize(width: 8, height: 42))
        strapV.position = crate.position
        addChild(strapV)
        let strapH = SKSpriteNode(color: SKColor(red: 0.55, green: 0.4, blue: 0.15, alpha: 1),
                                  size: CGSize(width: 42, height: 8))
        strapH.position = crate.position
        addChild(strapH)

        let body = SKPhysicsBody(rectangleOf: CGSize(width: 44, height: 40),
                                 center: CGPoint(x: 0, y: 10))
        body.isDynamic = false
        body.categoryBitMask = PhysicsCategory.lootBox
        physicsBody = body
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    /// Returns true if the box broke.
    func takeDamage(_ amount: Int) -> Bool {
        health -= amount
        run(.sequence([.scale(to: 0.88, duration: 0.05), .scale(to: 1.0, duration: 0.05)]))
        return health <= 0
    }
}

/// Pickup dropped by a broken loot box: +health and +damage for the collector.
final class PowerCube: SKNode {
    override init() {
        super.init()

        let cube = SKShapeNode(rectOf: CGSize(width: 22, height: 22), cornerRadius: 4)
        cube.fillColor = SKColor(red: 0.75, green: 0.3, blue: 0.9, alpha: 1)
        cube.strokeColor = SKColor(red: 0.45, green: 0.15, blue: 0.6, alpha: 1)
        cube.lineWidth = 3
        cube.position = CGPoint(x: 0, y: 12)
        addChild(cube)

        cube.run(.repeatForever(.sequence([
            .moveBy(x: 0, y: 6, duration: 0.5),
            .moveBy(x: 0, y: -6, duration: 0.5),
        ])))

        let body = SKPhysicsBody(circleOfRadius: 16)
        body.isDynamic = false
        body.categoryBitMask = PhysicsCategory.pickup
        body.contactTestBitMask = PhysicsCategory.fighter
        physicsBody = body
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }
}
