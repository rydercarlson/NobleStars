import SpriteKit

final class GameScene: SKScene, SKPhysicsContactDelegate {
    private let world = SKNode()
    private let hud = SKNode()
    private let cam = SKCameraNode()

    private var arena: ArenaNode!
    private var player: Fighter!
    private var fighters: [Fighter] = []
    private var projectiles: [Projectile] = []

    private let moveJoystick = VirtualJoystick()
    private let aimJoystick = VirtualJoystick()
    private let superButton = SuperButton()
    private var moveTouch: UITouch?
    private var aimTouch: UITouch?
    private var aimingSuper = false

    private let aimLine = SKShapeNode()
    private var lastUpdateTime: TimeInterval = 0

    /// Displacement below which an aim-joystick release counts as a tap (auto-aim).
    private let tapThreshold: CGFloat = 0.3

    // MARK: - Debug hooks (see CLAUDE.md)

    /// NS_AUTOWALK="dx,dy" drives the player without touch input.
    private let autoWalkInput: CGVector? = {
        guard let raw = ProcessInfo.processInfo.environment["NS_AUTOWALK"] else { return nil }
        let parts = raw.split(separator: ",").compactMap { Double($0.trimmingCharacters(in: .whitespaces)) }
        guard parts.count == 2 else { return nil }
        return CGVector(dx: parts[0], dy: parts[1])
    }()

    /// NS_AUTOFIRE="seconds" auto-aim fires on that interval (Super when ready).
    private let autoFireInterval: TimeInterval? = {
        ProcessInfo.processInfo.environment["NS_AUTOFIRE"].flatMap(Double.init)
    }()
    private var lastAutoFire: TimeInterval = 0
    private var shotsFired = 0

    /// NS_DEBUG_HUD=1 shows a live stats readout.
    private let debugLabel: SKLabelNode? = {
        guard ProcessInfo.processInfo.environment["NS_DEBUG_HUD"] != nil else { return nil }
        let label = SKLabelNode(fontNamed: "Menlo")
        label.fontSize = 14
        label.fontColor = .white
        label.horizontalAlignmentMode = .left
        label.verticalAlignmentMode = .top
        return label
    }()

    // MARK: - Setup

    override func didMove(to view: SKView) {
        backgroundColor = SKColor(red: 0.35, green: 0.55, blue: 0.25, alpha: 1)
        physicsWorld.gravity = .zero
        physicsWorld.contactDelegate = self

        addChild(world)

        let map = ArenaMaps.skullCreek
        arena = ArenaNode(map: map)
        world.addChild(arena)

        player = Fighter(color: SKColor(red: 0.25, green: 0.75, blue: 0.95, alpha: 1))
        player.position = map.spawnPoints.first ?? CGPoint(x: map.pixelWidth / 2, y: map.pixelHeight / 2)
        world.addChild(player)
        fighters.append(player)

        spawnDummies(near: player.position)
        for point in map.lootBoxPoints {
            let box = LootBox(mapPixelHeight: map.pixelHeight)
            box.position = point
            box.zPosition = ZLayer.ySorted(baselineY: point.y - 20, mapPixelHeight: map.pixelHeight)
            world.addChild(box)
        }

        aimLine.strokeColor = SKColor(white: 1, alpha: 0.35)
        aimLine.lineWidth = 3
        aimLine.zPosition = ZLayer.groundDecal + 1
        world.addChild(aimLine)

        camera = cam
        cam.position = player.position
        addChild(cam)

        hud.zPosition = ZLayer.hud
        cam.addChild(hud)
        hud.addChild(moveJoystick)
        hud.addChild(aimJoystick)
        hud.addChild(superButton)
        if let debugLabel { hud.addChild(debugLabel) }
        layoutHUD()
    }

    override func didChangeSize(_ oldSize: CGSize) {
        layoutHUD()
    }

    private func layoutHUD() {
        superButton.position = CGPoint(x: size.width / 2 - 150, y: -size.height / 2 + 78)
        debugLabel?.position = CGPoint(x: -size.width / 2 + 70, y: size.height / 2 - 14)
    }

    /// Practice targets until real bots arrive in M3.
    private func spawnDummies(near origin: CGPoint) {
        let ts = GameConstants.tileSize
        let offsets: [CGVector] = [
            CGVector(dx: 5 * ts, dy: -1 * ts),
            CGVector(dx: 7 * ts, dy: -4 * ts),
            CGVector(dx: 3 * ts, dy: -6 * ts),
        ]
        for offset in offsets {
            let dummy = Fighter(color: SKColor(red: 0.9, green: 0.35, blue: 0.3, alpha: 1))
            dummy.position = CGPoint(x: origin.x + offset.dx, y: origin.y + offset.dy)
            world.addChild(dummy)
            fighters.append(dummy)
        }
    }

    // MARK: - Firing

    private func fire(from fighter: Fighter, weapon: Weapon, direction: CGVector) {
        let magnitude = hypot(direction.dx, direction.dy)
        guard magnitude > 0.001 else { return }
        let unit = CGVector(dx: direction.dx / magnitude, dy: direction.dy / magnitude)
        fighter.face(unit)

        let damage = Int(CGFloat(weapon.pelletDamage) * fighter.damageMultiplier)
        let baseAngle = atan2(unit.dy, unit.dx)
        let spread = weapon.spreadDegrees * .pi / 180
        let count = weapon.pelletCount
        let muzzle = CGPoint(x: fighter.position.x + unit.dx * (fighter.bodyRadius + 10),
                             y: fighter.position.y + unit.dy * (fighter.bodyRadius + 10) + 18)

        for i in 0..<count {
            let t = count > 1 ? CGFloat(i) / CGFloat(count - 1) - 0.5 : 0
            let angle = baseAngle + t * spread
            let pelletDirection = CGVector(dx: cos(angle), dy: sin(angle))
            let pellet = Projectile(owner: fighter, position: muzzle,
                                    direction: pelletDirection, weapon: weapon,
                                    damage: damage,
                                    color: SKColor(red: 1.0, green: 0.85, blue: 0.3, alpha: 1))
            world.addChild(pellet)
            projectiles.append(pellet)
        }
    }

    private func fireMain(direction: CGVector) {
        guard !player.isDead, player.consumeAmmo() else { return }
        shotsFired += 1
        fire(from: player, weapon: player.weapon, direction: direction)
    }

    private func fireSuper(direction: CGVector) {
        guard !player.isDead, player.consumeSuper() else { return }
        fire(from: player, weapon: player.superWeapon, direction: direction)
        superButton.update(charge: 0)
    }

    /// Direction to the nearest living enemy in range with line of sight,
    /// else the player's facing.
    private func autoAimDirection(range: CGFloat) -> CGVector {
        var best: (distance: CGFloat, direction: CGVector)?
        for enemy in fighters where enemy !== player && !enemy.isDead {
            let dx = enemy.position.x - player.position.x
            let dy = enemy.position.y - player.position.y
            let distance = hypot(dx, dy)
            guard distance < range * 1.1, distance > 1 else { continue }
            guard hasLineOfSight(from: player.position, to: enemy.position) else { continue }
            if best == nil || distance < best!.distance {
                best = (distance, CGVector(dx: dx / distance, dy: dy / distance))
            }
        }
        return best?.direction ?? player.facing
    }

    private func hasLineOfSight(from start: CGPoint, to end: CGPoint) -> Bool {
        var blocked = false
        physicsWorld.enumerateBodies(alongRayStart: start, end: end) { body, _, _, stop in
            if body.categoryBitMask & PhysicsCategory.wall != 0 {
                blocked = true
                stop.pointee = true
            }
        }
        return !blocked
    }

    // MARK: - Input

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        for touch in touches {
            let hudPoint = touch.location(in: hud)
            let inSuper = superButton.contains(localPoint: CGPoint(x: hudPoint.x - superButton.position.x,
                                                                   y: hudPoint.y - superButton.position.y))
            if inSuper && player.isSuperReady && aimTouch == nil {
                // Drag from the super button to aim it; release fires.
                aimTouch = touch
                aimingSuper = true
                aimJoystick.begin(at: hudPoint)
            } else if hudPoint.x < 0 && moveTouch == nil {
                moveTouch = touch
                moveJoystick.begin(at: hudPoint)
            } else if hudPoint.x >= 0 && aimTouch == nil {
                aimTouch = touch
                aimingSuper = false
                aimJoystick.begin(at: hudPoint)
            }
        }
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        for touch in touches {
            if touch === moveTouch {
                moveJoystick.move(to: touch.location(in: hud))
            } else if touch === aimTouch {
                aimJoystick.move(to: touch.location(in: hud))
            }
        }
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        endTouches(touches)
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
        endTouches(touches)
    }

    private func endTouches(_ touches: Set<UITouch>) {
        for touch in touches {
            if touch === moveTouch {
                moveTouch = nil
                moveJoystick.end()
            } else if touch === aimTouch {
                let value = aimJoystick.value
                let wasSuper = aimingSuper
                aimTouch = nil
                aimingSuper = false
                aimJoystick.end()

                let weapon = wasSuper ? player.superWeapon : player.weapon
                let magnitude = hypot(value.dx, value.dy)
                let direction = magnitude >= tapThreshold ? value : autoAimDirection(range: weapon.range)
                if wasSuper {
                    fireSuper(direction: direction)
                } else {
                    fireMain(direction: direction)
                }
            }
        }
    }

    // MARK: - Contacts

    func didBegin(_ contact: SKPhysicsContact) {
        let nodes = [contact.bodyA.node, contact.bodyB.node]

        if let projectile = nodes.compactMap({ $0 as? Projectile }).first {
            guard projectile.parent != nil else { return }
            let other = nodes.first { !($0 is Projectile) } ?? nil

            if let fighter = other as? Fighter {
                guard fighter !== projectile.owner, !fighter.isDead else { return }
                fighter.takeDamage(projectile.damage, at: lastUpdateTime)
                projectile.owner.chargeSuper(damageDealt: projectile.damage)
                if fighter.isDead {
                    fighters.removeAll { $0 === fighter }
                    fighter.die()
                }
                projectile.explode()
            } else if let box = other as? LootBox {
                if box.takeDamage(projectile.damage) {
                    let cube = PowerCube()
                    cube.position = box.position
                    cube.zPosition = box.zPosition
                    world.addChild(cube)
                    box.removeFromParent()
                }
                projectile.explode()
            } else {
                // Wall or anything else solid.
                projectile.explode()
            }
            return
        }

        // Fighter walks over a power cube.
        if let fighter = nodes.compactMap({ $0 as? Fighter }).first,
           let cube = nodes.compactMap({ $0 as? PowerCube }).first,
           cube.parent != nil {
            fighter.collectPowerCube()
            cube.removeFromParent()
        }
    }

    // MARK: - Game loop

    override func update(_ currentTime: TimeInterval) {
        let dt = lastUpdateTime > 0 ? min(currentTime - lastUpdateTime, 1.0 / 20.0) : 0
        lastUpdateTime = currentTime

        if !player.isDead {
            player.applyMovement(autoWalkInput ?? moveJoystick.value)
            if aimTouch != nil, hypot(aimJoystick.value.dx, aimJoystick.value.dy) > 0.15 {
                player.face(aimJoystick.value)
            }
        }

        for fighter in fighters {
            fighter.tick(dt: dt, currentTime: currentTime)
            fighter.zPosition = ZLayer.ySorted(baselineY: fighter.position.y,
                                               mapPixelHeight: arena.map.pixelHeight)
            fighter.setHidden(inBush: arena.map.tile(at: fighter.position) == .bush)
        }

        // Expire pellets that flew their full range.
        projectiles.removeAll { projectile in
            if projectile.parent == nil { return true }
            if projectile.isBeyondRange {
                projectile.explode()
                return true
            }
            return false
        }

        updateAimLine()
        superButton.update(charge: player.superCharge)
        runAutoFireIfNeeded(currentTime)

        debugLabel?.text = String(
            format: "shots:%d ammo:%.2f super:%.2f enemies:%d projectiles:%d",
            shotsFired, player.ammo, player.superCharge, fighters.count - 1, projectiles.count
        )
    }

    private func updateAimLine() {
        guard aimTouch != nil, !player.isDead,
              hypot(aimJoystick.value.dx, aimJoystick.value.dy) >= tapThreshold else {
            aimLine.path = nil
            return
        }
        let weapon = aimingSuper ? player.superWeapon : player.weapon
        let path = CGMutablePath()
        let start = CGPoint(x: player.position.x, y: player.position.y + 18)
        path.move(to: start)
        path.addLine(to: CGPoint(x: start.x + player.facing.dx * weapon.range,
                                 y: start.y + player.facing.dy * weapon.range))
        aimLine.path = path
        aimLine.strokeColor = aimingSuper
            ? SKColor(red: 1.0, green: 0.8, blue: 0.2, alpha: 0.55)
            : SKColor(white: 1, alpha: 0.35)
    }

    private func runAutoFireIfNeeded(_ currentTime: TimeInterval) {
        guard let interval = autoFireInterval,
              currentTime - lastAutoFire >= interval, !player.isDead else { return }
        lastAutoFire = currentTime
        if player.isSuperReady {
            fireSuper(direction: autoAimDirection(range: player.superWeapon.range))
        } else {
            fireMain(direction: autoAimDirection(range: player.weapon.range))
        }
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
