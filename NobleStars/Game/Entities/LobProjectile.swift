import SpriteKit

/// An arcing projectile (tennis ball) that sails over walls and splashes
/// where it lands. Purely action-driven — no physics body, so nothing
/// blocks it in flight; the scene applies splash damage on landing.
final class LobProjectile: SKNode {
    let owner: Fighter
    let weapon: Weapon
    let damage: Int

    init(owner: Fighter, from start: CGPoint, to target: CGPoint,
         weapon: Weapon, damage: Int,
         onLand: @escaping (LobProjectile) -> Void) {
        self.owner = owner
        self.weapon = weapon
        self.damage = damage
        super.init()

        position = start
        zPosition = ZLayer.ySortBase + ZLayer.ySortRange + 20   // above walls

        let shadow = SKShapeNode(ellipseOf: CGSize(width: 14, height: 7))
        shadow.fillColor = SKColor(white: 0, alpha: 0.3)
        shadow.strokeColor = .clear
        addChild(shadow)

        let ball = SKSpriteNode(imageNamed: "ball_tennis")
        ball.size = CGSize(width: weapon.pelletRadius * 2.4, height: weapon.pelletRadius * 2.4)
        ball.position = CGPoint(x: 0, y: 20)
        ball.run(.repeatForever(.rotate(byAngle: -.pi * 2, duration: 0.7)))
        addChild(ball)

        let distance = hypot(target.x - start.x, target.y - start.y)
        let duration = TimeInterval(distance / weapon.projectileSpeed)

        // The node slides straight to the target while the ball child arcs
        // up and back down, selling the lob.
        let up = SKAction.moveTo(y: 20 + min(90, distance * 0.35), duration: duration / 2)
        up.timingMode = .easeOut
        let down = SKAction.moveTo(y: 14, duration: duration / 2)
        down.timingMode = .easeIn
        ball.run(.sequence([
            .group([.sequence([up, down]),
                    .sequence([.scale(to: 1.5, duration: duration / 2),
                               .scale(to: 1.0, duration: duration / 2)])]),
        ]))

        run(.sequence([
            .move(to: target, duration: duration),
            .run { [weak self] in
                guard let self else { return }
                onLand(self)
                self.removeFromParent()
            },
        ]))
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }
}
