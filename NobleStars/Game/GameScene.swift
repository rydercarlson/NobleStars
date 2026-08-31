import SpriteKit

final class GameScene: SKScene {
    private let world = SKNode()
    private let hud = SKNode()
    private let cam = SKCameraNode()

    private var arena: ArenaNode!
    private var player: Fighter!

    private let moveJoystick = VirtualJoystick()
    private var moveTouch: UITouch?

    /// Debug: launch with NS_AUTOWALK="dx,dy" (e.g. via SIMCTL_CHILD_NS_AUTOWALK) to
    /// drive the player without touch input, for automated verification.
    private let autoWalkInput: CGVector? = {
        guard let raw = ProcessInfo.processInfo.environment["NS_AUTOWALK"] else { return nil }
        let parts = raw.split(separator: ",").compactMap { Double($0.trimmingCharacters(in: .whitespaces)) }
        guard parts.count == 2 else { return nil }
        return CGVector(dx: parts[0], dy: parts[1])
    }()

    override func didMove(to view: SKView) {
        backgroundColor = SKColor(red: 0.35, green: 0.55, blue: 0.25, alpha: 1)
        physicsWorld.gravity = .zero

        addChild(world)

        let map = ArenaMaps.skullCreek
        arena = ArenaNode(map: map)
        world.addChild(arena)

        player = Fighter(color: SKColor(red: 0.25, green: 0.75, blue: 0.95, alpha: 1))
        player.position = map.spawnPoints.first ?? CGPoint(x: map.pixelWidth / 2, y: map.pixelHeight / 2)
        world.addChild(player)

        camera = cam
        cam.position = player.position
        addChild(cam)

        hud.zPosition = ZLayer.hud
        cam.addChild(hud)
        hud.addChild(moveJoystick)
    }

    // MARK: - Input

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        for touch in touches {
            let hudPoint = touch.location(in: hud)
            // Left half of the screen controls movement.
            if moveTouch == nil && hudPoint.x < 0 {
                moveTouch = touch
                moveJoystick.begin(at: hudPoint)
            }
        }
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        for touch in touches where touch === moveTouch {
            moveJoystick.move(to: touch.location(in: hud))
        }
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        endTouches(touches)
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
        endTouches(touches)
    }

    private func endTouches(_ touches: Set<UITouch>) {
        for touch in touches where touch === moveTouch {
            moveTouch = nil
            moveJoystick.end()
        }
    }

    // MARK: - Game loop

    override func update(_ currentTime: TimeInterval) {
        player.applyMovement(autoWalkInput ?? moveJoystick.value)
        player.zPosition = ZLayer.ySorted(baselineY: player.position.y,
                                          mapPixelHeight: arena.map.pixelHeight)
        player.setHidden(inBush: arena.map.tile(at: player.position) == .bush)
    }

    override func didFinishUpdate() {
        followPlayer()
    }

    private func followPlayer() {
        let target = player.position
        var next = CGPoint(
            x: cam.position.x + (target.x - cam.position.x) * 0.12,
            y: cam.position.y + (target.y - cam.position.y) * 0.12
        )

        // Clamp the viewport inside the map.
        let halfW = size.width / 2 * cam.xScale
        let halfH = size.height / 2 * cam.yScale
        let map = arena.map
        if map.pixelWidth > halfW * 2 {
            next.x = min(max(next.x, halfW), map.pixelWidth - halfW)
        } else {
            next.x = map.pixelWidth / 2
        }
        if map.pixelHeight > halfH * 2 {
            next.y = min(max(next.y, halfH), map.pixelHeight - halfH)
        } else {
            next.y = map.pixelHeight / 2
        }
        cam.position = next
    }
}
