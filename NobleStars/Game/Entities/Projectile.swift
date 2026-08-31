import SpriteKit

/// One bullet/pellet in flight. Moves via physics velocity; the scene removes
/// it on contact or when it exceeds its range.
final class Projectile: SKNode {
    let owner: Fighter
    let damage: Int
    private let maxDistanceSquared: CGFloat
    private let origin: CGPoint

    init(owner: Fighter, position: CGPoint, direction: CGVector, weapon: Weapon, damage: Int, color: SKColor) {
        self.owner = owner
        self.damage = damage
        self.origin = position
        self.maxDistanceSquared = weapon.range * weapon.range
        super.init()

        self.position = position
        zPosition = ZLayer.ySortBase + ZLayer.ySortRange + 10  // fly above everything ground-level

        let dot = SKShapeNode(circleOfRadius: weapon.pelletRadius)
        dot.fillColor = color
        dot.strokeColor = SKColor(white: 0.1, alpha: 0.8)
        dot.lineWidth = 1.5
        addChild(dot)

        let body = SKPhysicsBody(circleOfRadius: weapon.pelletRadius)
        body.affectedByGravity = false
        body.allowsRotation = false
        body.linearDamping = 0
        body.categoryBitMask = PhysicsCategory.projectile
        body.collisionBitMask = PhysicsCategory.none
        body.contactTestBitMask = PhysicsCategory.wall | PhysicsCategory.fighter | PhysicsCategory.lootBox
        body.usesPreciseCollisionDetection = true
        physicsBody = body

        body.velocity = CGVector(dx: direction.dx * weapon.projectileSpeed,
                                 dy: direction.dy * weapon.projectileSpeed)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    var isBeyondRange: Bool {
        let dx = position.x - origin.x
        let dy = position.y - origin.y
        return dx * dx + dy * dy > maxDistanceSquared
    }

    func explode() {
        physicsBody = nil
        // Leave a brief impact puff where the pellet died.
        if let parent {
            let puff = SKShapeNode(circleOfRadius: 8)
            puff.fillColor = SKColor(white: 1, alpha: 0.7)
            puff.strokeColor = .clear
            puff.position = position
            puff.zPosition = zPosition
            parent.addChild(puff)
            puff.run(.sequence([
                .group([.fadeOut(withDuration: 0.18), .scale(to: 1.8, duration: 0.18)]),
                .removeFromParent(),
            ]))
        }
        removeFromParent()
    }
}
