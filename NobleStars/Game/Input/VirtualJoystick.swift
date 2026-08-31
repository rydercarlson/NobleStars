import SpriteKit

/// A floating virtual joystick: appears where the touch lands, knob follows
/// the finger up to `maxRadius`, hides on release.
final class VirtualJoystick: SKNode {
    private let base: SKShapeNode
    private let knob: SKShapeNode
    private let maxRadius: CGFloat = 55

    /// Normalized output, magnitude 0...1. Zero when inactive.
    private(set) var value: CGVector = .zero
    private(set) var isActive = false

    override init() {
        base = SKShapeNode(circleOfRadius: 55)
        base.fillColor = SKColor(white: 1, alpha: 0.12)
        base.strokeColor = SKColor(white: 1, alpha: 0.35)
        base.lineWidth = 2

        knob = SKShapeNode(circleOfRadius: 26)
        knob.fillColor = SKColor(white: 1, alpha: 0.4)
        knob.strokeColor = SKColor(white: 1, alpha: 0.6)
        knob.lineWidth = 2

        super.init()
        addChild(base)
        addChild(knob)
        isHidden = true
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    /// Position in the parent (HUD) coordinate space.
    func begin(at point: CGPoint) {
        position = point
        knob.position = .zero
        value = .zero
        isActive = true
        isHidden = false
    }

    func move(to point: CGPoint) {
        guard isActive else { return }
        let local = CGPoint(x: point.x - position.x, y: point.y - position.y)
        let distance = hypot(local.x, local.y)
        let clamped = min(distance, maxRadius)
        guard distance > 0.001 else {
            knob.position = .zero
            value = .zero
            return
        }
        let unitX = local.x / distance
        let unitY = local.y / distance
        knob.position = CGPoint(x: unitX * clamped, y: unitY * clamped)
        value = CGVector(dx: unitX * (clamped / maxRadius),
                         dy: unitY * (clamped / maxRadius))
    }

    func end() {
        isActive = false
        isHidden = true
        value = .zero
        knob.position = .zero
    }
}
