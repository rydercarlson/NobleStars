import SpriteKit

/// HUD button showing Super charge; lights up when ready.
final class SuperButton: SKNode {
    static let radius: CGFloat = 42

    private let ring: SKShapeNode
    private let fillArc: SKShapeNode
    private let star: SKLabelNode
    private var lastFraction: CGFloat = -1

    override init() {
        ring = SKShapeNode(circleOfRadius: Self.radius)
        ring.fillColor = SKColor(white: 0.1, alpha: 0.35)
        ring.strokeColor = SKColor(white: 1, alpha: 0.4)
        ring.lineWidth = 3

        fillArc = SKShapeNode()
        fillArc.fillColor = SKColor(red: 1.0, green: 0.75, blue: 0.1, alpha: 0.85)
        fillArc.strokeColor = .clear

        star = SKLabelNode(text: "★")
        star.fontName = "AvenirNext-Bold"
        star.fontSize = 34
        star.verticalAlignmentMode = .center
        star.fontColor = SKColor(white: 1, alpha: 0.5)

        super.init()
        addChild(ring)
        addChild(fillArc)
        addChild(star)
        update(charge: 0)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    func update(charge: CGFloat) {
        let fraction = max(0, min(1, charge))
        guard abs(fraction - lastFraction) > 0.005 else { return }
        lastFraction = fraction

        // Pie-slice fill from 12 o'clock, clockwise.
        let path = CGMutablePath()
        if fraction > 0.001 {
            path.move(to: .zero)
            path.addArc(center: .zero, radius: Self.radius - 3,
                        startAngle: .pi / 2,
                        endAngle: .pi / 2 - fraction * 2 * .pi,
                        clockwise: true)
            path.closeSubpath()
        }
        fillArc.path = path

        let ready = fraction >= 1
        star.fontColor = ready ? SKColor(white: 0.1, alpha: 1) : SKColor(white: 1, alpha: 0.5)
        ring.strokeColor = ready ? SKColor(red: 1.0, green: 0.85, blue: 0.2, alpha: 1) : SKColor(white: 1, alpha: 0.4)
        ring.lineWidth = ready ? 5 : 3
    }

    /// Hit test in this node's coordinate space.
    func contains(localPoint: CGPoint) -> Bool {
        hypot(localPoint.x, localPoint.y) <= Self.radius + 12
    }
}
