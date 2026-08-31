import SpriteKit

/// Destructible crate that drops a power cube when broken.
final class LootBox: SKNode {
    private(set) var health = 900

    init(mapPixelHeight: CGFloat) {
        super.init()

        let shadow = SKShapeNode(ellipseOf: CGSize(width: 46, height: 16))
        shadow.fillColor = SKColor(white: 0, alpha: 0.25)
        shadow.strokeColor = .clear
        addChild(shadow)

        let crate = SKSpriteNode(imageNamed: "crate")
        crate.size = CGSize(width: 46, height: 46)
        crate.position = CGPoint(x: 0, y: 16)
        addChild(crate)

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
