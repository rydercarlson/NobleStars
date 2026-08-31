import SpriteKit

/// A fighter in the arena — the player or a bot. Visuals are placeholder
/// shapes until the M4 art pass; the node's position is the fighter's feet.
final class Fighter: SKNode {
    let bodyRadius: CGFloat = 20
    var moveSpeed: CGFloat = 340

    private let bodyNode: SKShapeNode
    private let shadowNode: SKShapeNode

    /// Direction the fighter is facing, for the aim indicator.
    private(set) var facing = CGVector(dx: 0, dy: -1)
    private let facingDot: SKShapeNode

    init(color: SKColor) {
        shadowNode = SKShapeNode(ellipseOf: CGSize(width: 40, height: 18))
        shadowNode.fillColor = SKColor(white: 0, alpha: 0.25)
        shadowNode.strokeColor = .clear
        shadowNode.zPosition = -1

        bodyNode = SKShapeNode(circleOfRadius: bodyRadius)
        bodyNode.fillColor = color
        bodyNode.strokeColor = SKColor(white: 0.1, alpha: 1)
        bodyNode.lineWidth = 3
        bodyNode.position = CGPoint(x: 0, y: 18)

        facingDot = SKShapeNode(circleOfRadius: 6)
        facingDot.fillColor = SKColor(white: 0.95, alpha: 1)
        facingDot.strokeColor = SKColor(white: 0.1, alpha: 1)
        facingDot.lineWidth = 2

        super.init()

        addChild(shadowNode)
        addChild(bodyNode)
        bodyNode.addChild(facingDot)
        updateFacingDot()

        let body = SKPhysicsBody(circleOfRadius: bodyRadius)
        body.allowsRotation = false
        body.friction = 0
        body.restitution = 0
        body.linearDamping = 0
        body.categoryBitMask = PhysicsCategory.fighter
        body.collisionBitMask = PhysicsCategory.wall | PhysicsCategory.water | PhysicsCategory.fighter
        physicsBody = body
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    /// Drive movement from a joystick vector (magnitude 0...1).
    func applyMovement(_ input: CGVector) {
        guard let body = physicsBody else { return }
        body.velocity = CGVector(dx: input.dx * moveSpeed, dy: input.dy * moveSpeed)
        let magnitude = hypot(input.dx, input.dy)
        if magnitude > 0.1 {
            facing = CGVector(dx: input.dx / magnitude, dy: input.dy / magnitude)
            updateFacingDot()
        }
    }

    /// Fade when standing in a bush.
    func setHidden(inBush: Bool) {
        let target: CGFloat = inBush ? 0.45 : 1.0
        if abs(alpha - target) > 0.01 {
            run(.fadeAlpha(to: target, duration: 0.15))
        }
    }

    private func updateFacingDot() {
        facingDot.position = CGPoint(x: facing.dx * bodyRadius * 0.65,
                                     y: facing.dy * bodyRadius * 0.65)
    }
}
