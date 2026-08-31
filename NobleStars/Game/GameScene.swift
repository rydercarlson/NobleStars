import SpriteKit
import GameController

final class GameScene: SKScene, SKPhysicsContactDelegate {
    private enum MatchPhase {
        case countdown(endsAt: TimeInterval)
        case playing
        case ended
    }

    /// Which character the player brought into the match.
    var playerKit: FighterKit = .nova

    private let world = SKNode()
    private let hud = SKNode()
    private let cam = SKCameraNode()

    private var arena: ArenaNode!
    private var player: Fighter!
    private var fighters: [Fighter] = []
    private var brains: [BotBrain] = []
    private var projectiles: [Projectile] = []
    private var gasRing: GasRing?
    private var phase: MatchPhase = .countdown(endsAt: 0)

    private let moveJoystick = VirtualJoystick()
    private let aimJoystick = VirtualJoystick()
    private let superButton = SuperButton()
    private var moveTouch: UITouch?
    private var aimTouch: UITouch?
    private var aimingSuper = false

    private let aimLine = SKShapeNode()
    private var lastUpdateTime: TimeInterval = 0

    // HUD
    private let countdownLabel = SKLabelNode(fontNamed: "AvenirNext-Heavy")
    private let playersLeftLabel = SKLabelNode(fontNamed: "AvenirNext-Bold")
    private let killFeedLabel = SKLabelNode(fontNamed: "AvenirNext-Medium")
    private let resultsOverlay = SKNode()

    /// Displacement below which an aim-joystick release counts as a tap (auto-aim).
    private let tapThreshold: CGFloat = 0.3

    // Haptics (real device only; the simulator ignores them).
    private let dealtDamageHaptic = UIImpactFeedbackGenerator(style: .light)
    private let tookDamageHaptic = UIImpactFeedbackGenerator(style: .heavy)

    // Hardware keyboard (playtesting in the simulator / iPad keyboards):
    // WASD to move, Space to fire (auto-aim), E for Super.
    private var spaceWasPressed = false
    private var superKeyWasPressed = false

    private var keyboardMovement: CGVector {
        guard let keys = GCKeyboard.coalesced?.keyboardInput else { return .zero }
        var dx: CGFloat = 0
        var dy: CGFloat = 0
        if keys.button(forKeyCode: .keyW)?.isPressed == true { dy += 1 }
        if keys.button(forKeyCode: .keyS)?.isPressed == true { dy -= 1 }
        if keys.button(forKeyCode: .keyA)?.isPressed == true { dx -= 1 }
        if keys.button(forKeyCode: .keyD)?.isPressed == true { dx += 1 }
        let magnitude = hypot(dx, dy)
        guard magnitude > 0 else { return .zero }
        return CGVector(dx: dx / magnitude, dy: dy / magnitude)
    }

    private func pollKeyboardActions() {
        guard let keys = GCKeyboard.coalesced?.keyboardInput else { return }
        let space = keys.button(forKeyCode: .spacebar)?.isPressed == true
        if space && !spaceWasPressed {
            let aim = autoAimSolution(range: player.weapon.range)
            fireMain(direction: aim.direction, distance: aim.distance)
        }
        spaceWasPressed = space

        let superKey = keys.button(forKeyCode: .keyE)?.isPressed == true
        if superKey && !superKeyWasPressed && player.isSuperReady {
            let aim = autoAimSolution(range: player.superWeapon.range)
            fireSuper(direction: aim.direction, distance: aim.distance)
        }
        superKeyWasPressed = superKey
    }

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

    /// NS_GODMODE=1 makes the player invulnerable, to observe full matches.
    private let godMode = ProcessInfo.processInfo.environment["NS_GODMODE"] != nil

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

        camera = cam
        addChild(cam)

        hud.zPosition = ZLayer.hud
        cam.addChild(hud)
        hud.addChild(moveJoystick)
        hud.addChild(aimJoystick)
        hud.addChild(superButton)

        countdownLabel.fontSize = 90
        countdownLabel.fontColor = .white
        countdownLabel.verticalAlignmentMode = .center
        hud.addChild(countdownLabel)

        playersLeftLabel.fontSize = 22
        playersLeftLabel.fontColor = .white
        playersLeftLabel.horizontalAlignmentMode = .right
        playersLeftLabel.verticalAlignmentMode = .top
        hud.addChild(playersLeftLabel)

        killFeedLabel.fontSize = 16
        killFeedLabel.fontColor = SKColor(white: 1, alpha: 0.9)
        killFeedLabel.horizontalAlignmentMode = .right
        killFeedLabel.verticalAlignmentMode = .top
        hud.addChild(killFeedLabel)

        if let debugLabel { hud.addChild(debugLabel) }

        // Debug: NS_KIT=tony|henry|nova forces the player's character.
        if let raw = ProcessInfo.processInfo.environment["NS_KIT"],
           let kit = FighterKit.named(raw) {
            playerKit = kit
        }

        layoutHUD()
        startMatch()
    }

    /// Builds (or rebuilds) the whole match. Also used for play-again.
    private func startMatch() {
        world.removeAllChildren()
        fighters.removeAll()
        brains.removeAll()
        projectiles.removeAll()
        resultsOverlay.removeFromParent()
        gasRing = nil
        lastUpdateTime = 0
        shotsFired = 0

        let map = ArenaMaps.skullCreek
        arena = ArenaNode(map: map)
        world.addChild(arena)

        var spawns = map.spawnPoints.shuffled()
        if spawns.isEmpty {
            spawns = [CGPoint(x: map.pixelWidth / 2, y: map.pixelHeight / 2)]
        }

        player = Fighter(kit: playerKit)
        player.displayName = "You"
        player.position = spawns.removeFirst()
        world.addChild(player)
        fighters.append(player)

        var botIndex = 1
        while !spawns.isEmpty && botIndex <= 9 {
            let kit = FighterKit.all.randomElement() ?? .nova
            let bot = Fighter(kit: kit)
            bot.displayName = "\(kit.name) \(botIndex)"
            bot.position = spawns.removeFirst()
            world.addChild(bot)
            fighters.append(bot)
            brains.append(BotBrain(fighter: bot))
            botIndex += 1
        }

        for point in map.lootBoxPoints {
            let box = LootBox(mapPixelHeight: map.pixelHeight)
            box.position = point
            box.zPosition = ZLayer.ySorted(baselineY: point.y - 20, mapPixelHeight: map.pixelHeight)
            world.addChild(box)
        }

        aimLine.path = nil
        aimLine.zPosition = ZLayer.groundDecal + 1
        world.addChild(aimLine)

        cam.position = player.position
        phase = .countdown(endsAt: 0)   // real end time set on first update
        countdownLabel.isHidden = false
        updatePlayersLeftLabel()
        killFeedLabel.text = ""
        superButton.update(charge: 0)
    }

    override func didChangeSize(_ oldSize: CGSize) {
        layoutHUD()
    }

    private func layoutHUD() {
        superButton.position = CGPoint(x: size.width / 2 - 150, y: -size.height / 2 + 78)
        countdownLabel.position = CGPoint(x: 0, y: 40)
        playersLeftLabel.position = CGPoint(x: size.width / 2 - 24, y: size.height / 2 - 16)
        killFeedLabel.position = CGPoint(x: size.width / 2 - 24, y: size.height / 2 - 48)
        debugLabel?.position = CGPoint(x: -size.width / 2 + 70, y: size.height / 2 - 14)
    }

    // MARK: - Bot senses (used by BotBrain)

    var gasSafeCenter: CGPoint {
        gasRing?.safeCenter ?? CGPoint(x: arena.map.pixelWidth / 2, y: arena.map.pixelHeight / 2)
    }

    func gasContains(_ point: CGPoint) -> Bool {
        gasRing?.contains(point) ?? true
    }

    /// Visibility rule shared by player auto-aim and bots: line of sight,
    /// and fighters deep in a bush are invisible beyond point-blank range.
    func canSee(from viewer: Fighter, target: Fighter) -> Bool {
        let dx = target.position.x - viewer.position.x
        let dy = target.position.y - viewer.position.y
        let distance = hypot(dx, dy)
        if arena.map.tile(at: target.position) == .bush,
           distance > GameConstants.tileSize * 2 {
            return false
        }
        return hasLineOfSight(from: viewer.position, to: target.position)
    }

    func nearestVisibleEnemy(of viewer: Fighter, within range: CGFloat) -> Fighter? {
        var best: (distance: CGFloat, fighter: Fighter)?
        for enemy in fighters where enemy !== viewer && !enemy.isDead {
            let distance = hypot(enemy.position.x - viewer.position.x,
                                 enemy.position.y - viewer.position.y)
            guard distance < range, distance > 1 else { continue }
            guard canSee(from: viewer, target: enemy) else { continue }
            if best == nil || distance < best!.distance {
                best = (distance, enemy)
            }
        }
        return best?.fighter
    }

    /// Nearest loot box or power cube within a scavenging radius.
    func nearestLoot(to point: CGPoint) -> CGPoint? {
        var best: (distance: CGFloat, point: CGPoint)?
        let radius = GameConstants.tileSize * 9
        for node in world.children where node is LootBox || node is PowerCube {
            let distance = hypot(node.position.x - point.x, node.position.y - point.y)
            guard distance < radius, gasContains(node.position) else { continue }
            if best == nil || distance < best!.distance {
                best = (distance, node.position)
            }
        }
        return best?.point
    }

    func randomWanderPoint(near origin: CGPoint) -> CGPoint {
        let ts = GameConstants.tileSize
        for _ in 0..<8 {
            let angle = CGFloat.random(in: 0..<(2 * .pi))
            let radius = CGFloat.random(in: 3...6) * ts
            let candidate = CGPoint(x: origin.x + cos(angle) * radius,
                                    y: origin.y + sin(angle) * radius)
            if !arena.map.tile(at: candidate).blocksMovement, gasContains(candidate) {
                return candidate
            }
        }
        return gasSafeCenter
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

    // MARK: - Damage plumbing

    /// Central damage path: haptics, Super charge, knockback, elimination.
    func dealDamage(_ amount: Int, to target: Fighter, from attacker: Fighter,
                    knockbackDirection: CGVector? = nil, knockbackStrength: CGFloat = 0) {
        guard !target.isDead else { return }
        if godMode, target === player { return }
        target.takeDamage(amount, at: lastUpdateTime)
        if let direction = knockbackDirection, knockbackStrength > 0 {
            target.receiveKnockback(direction: direction, strength: knockbackStrength)
        }
        if target === player {
            tookDamageHaptic.impactOccurred()
        } else if attacker === player {
            dealtDamageHaptic.impactOccurred(intensity: 0.7)
        }
        attacker.chargeSuper(damageDealt: amount)
        if target.isDead {
            eliminate(target, by: attacker.displayName)
        }
    }

    private func damageLootBox(_ box: LootBox, amount: Int) {
        if box.takeDamage(amount) {
            let cube = PowerCube()
            cube.position = box.position
            cube.zPosition = box.zPosition
            world.addChild(cube)
            box.removeFromParent()
        }
    }

    // MARK: - Attacks

    /// Dispatch one attack of any style.
    private func performAttack(from fighter: Fighter, weapon: Weapon,
                               direction: CGVector, distance: CGFloat) {
        let magnitude = hypot(direction.dx, direction.dy)
        guard magnitude > 0.001 else { return }
        let unit = CGVector(dx: direction.dx / magnitude, dy: direction.dy / magnitude)
        fighter.face(unit)
        fighter.playAttackAnimation(weapon: weapon, direction: unit)

        switch weapon.style {
        case .pellets:
            spawnPellets(from: fighter, weapon: weapon, unit: unit)
        case .lob:
            spawnLob(from: fighter, weapon: weapon, unit: unit, distance: distance)
        case .melee:
            meleeSwipe(from: fighter, weapon: weapon, unit: unit)
        case .dash:
            fighter.beginDash(weapon: weapon, direction: unit)
        }
    }

    private func spawnPellets(from fighter: Fighter, weapon: Weapon, unit: CGVector) {
        let damage = Int(CGFloat(weapon.pelletDamage) * fighter.damageMultiplier)
        let baseAngle = atan2(unit.dy, unit.dx)
        let spread = weapon.spreadDegrees * .pi / 180
        let count = weapon.pelletCount
        let muzzle = CGPoint(x: fighter.position.x + unit.dx * (fighter.bodyRadius + 10),
                             y: fighter.position.y + unit.dy * (fighter.bodyRadius + 10) + 18)

        // Super shells look the part: big and red-hot.
        let color = weapon.destroysWalls
            ? SKColor(red: 1.0, green: 0.45, blue: 0.15, alpha: 1)
            : SKColor(red: 1.0, green: 0.85, blue: 0.3, alpha: 1)

        for i in 0..<count {
            let t = count > 1 ? CGFloat(i) / CGFloat(count - 1) - 0.5 : 0
            let angle = baseAngle + t * spread
            let pelletDirection = CGVector(dx: cos(angle), dy: sin(angle))
            let pellet = Projectile(owner: fighter, position: muzzle,
                                    direction: pelletDirection, weapon: weapon,
                                    damage: damage, color: color)
            world.addChild(pellet)
            projectiles.append(pellet)
        }
    }

    private func spawnLob(from fighter: Fighter, weapon: Weapon, unit: CGVector, distance: CGFloat) {
        let damage = Int(CGFloat(weapon.pelletDamage) * fighter.damageMultiplier)
        let throwDistance = min(max(distance, GameConstants.tileSize * 1.5), weapon.range)
        let start = CGPoint(x: fighter.position.x, y: fighter.position.y + 4)
        let target = CGPoint(x: fighter.position.x + unit.dx * throwDistance,
                             y: fighter.position.y + unit.dy * throwDistance)
        let ball = LobProjectile(
            owner: fighter, from: start, to: target, weapon: weapon, damage: damage
        ) { [weak self] lob in
            self?.lobLanded(lob)
        }
        world.addChild(ball)
    }

    private func lobLanded(_ lob: LobProjectile) {
        let radius = lob.weapon.aoeRadius
        let center = lob.position

        // Splash ring.
        let ring = SKShapeNode(circleOfRadius: radius)
        ring.fillColor = SKColor(red: 0.95, green: 0.9, blue: 0.3, alpha: 0.35)
        ring.strokeColor = SKColor(red: 0.7, green: 0.65, blue: 0.1, alpha: 0.8)
        ring.lineWidth = 3
        ring.position = center
        ring.zPosition = ZLayer.groundDecal + 2
        world.addChild(ring)
        ring.run(.sequence([.fadeOut(withDuration: 0.3), .removeFromParent()]))

        for target in fighters where target !== lob.owner && !target.isDead {
            let d = hypot(target.position.x - center.x, target.position.y - center.y)
            if d <= radius + target.bodyRadius {
                dealDamage(lob.damage, to: target, from: lob.owner)
            }
        }
        for node in world.children {
            guard let box = node as? LootBox else { continue }
            let d = hypot(box.position.x - center.x, box.position.y - center.y)
            if d <= radius + 24 {
                damageLootBox(box, amount: lob.damage)
            }
        }
    }

    private func meleeSwipe(from fighter: Fighter, weapon: Weapon, unit: CGVector) {
        let damage = Int(CGFloat(weapon.pelletDamage) * fighter.damageMultiplier)
        let baseAngle = atan2(unit.dy, unit.dx)
        let halfArc = weapon.spreadDegrees * .pi / 180 / 2

        func inArc(_ point: CGPoint, reach: CGFloat) -> Bool {
            let dx = point.x - fighter.position.x
            let dy = point.y - fighter.position.y
            let d = hypot(dx, dy)
            guard d <= weapon.range + reach else { return false }
            let delta = atan2(sin(atan2(dy, dx) - baseAngle), cos(atan2(dy, dx) - baseAngle))
            return abs(delta) <= halfArc
        }

        for target in fighters where target !== fighter && !target.isDead {
            guard inArc(target.position, reach: target.bodyRadius) else { continue }
            guard hasLineOfSight(from: fighter.position, to: target.position) else { continue }
            dealDamage(damage, to: target, from: fighter,
                       knockbackDirection: unit, knockbackStrength: weapon.knockback)
        }
        for node in world.children {
            guard let box = node as? LootBox, inArc(box.position, reach: 24) else { continue }
            damageLootBox(box, amount: damage)
        }

        // Swipe visual: the paddle itself sweeps across the arc, with a
        // faint trailing arc line for motion.
        let paddle = SKSpriteNode(imageNamed: fighter.kit.weaponImage)
        paddle.anchorPoint = CGPoint(x: -0.02, y: 0.5)
        paddle.setScale(weapon.range / 120)
        paddle.position = CGPoint(x: fighter.position.x, y: fighter.position.y + 14)
        paddle.zPosition = fighter.zPosition + 2
        paddle.zRotation = baseAngle - halfArc
        world.addChild(paddle)
        paddle.run(.sequence([
            .rotate(byAngle: 2 * halfArc, duration: 0.14),
            .fadeOut(withDuration: 0.10),
            .removeFromParent(),
        ]))

        let trail = SKShapeNode()
        let trailPath = CGMutablePath()
        trailPath.addArc(center: .zero, radius: weapon.range * 0.85,
                         startAngle: baseAngle - halfArc, endAngle: baseAngle + halfArc,
                         clockwise: false)
        trail.path = trailPath
        trail.strokeColor = SKColor(white: 1, alpha: 0.35)
        trail.lineWidth = 4
        trail.position = paddle.position
        trail.zPosition = fighter.zPosition + 1
        world.addChild(trail)
        trail.run(.sequence([.fadeOut(withDuration: 0.22), .removeFromParent()]))
    }

    /// Per-frame dash progress: damage on contact, water crossing, ending.
    private func updateDashes(dt: TimeInterval) {
        for fighter in fighters {
            guard var dash = fighter.dashState else { continue }
            if dash.windup > 0 {
                dash.windup -= dt
                fighter.dashState = dash
                continue
            }
            dash.remaining -= dash.weapon.projectileSpeed * CGFloat(dt)

            let tile = arena.map.tile(at: fighter.position)
            if tile == .water { dash.crossedWater = true }

            for enemy in fighters where enemy !== fighter && !enemy.isDead {
                let id = ObjectIdentifier(enemy)
                guard !dash.alreadyHit.contains(id) else { continue }
                let d = hypot(enemy.position.x - fighter.position.x,
                              enemy.position.y - fighter.position.y)
                if d < fighter.bodyRadius + enemy.bodyRadius + 8 {
                    dash.alreadyHit.insert(id)
                    let multiplier = dash.crossedWater ? dash.weapon.waterDamageMultiplier : 1
                    let damage = Int(CGFloat(dash.weapon.pelletDamage) * multiplier * fighter.damageMultiplier)
                    dealDamage(damage, to: enemy, from: fighter,
                               knockbackDirection: dash.direction,
                               knockbackStrength: dash.weapon.knockback)
                }
            }

            // Keep dashing while over water (so Henry lands on solid ground),
            // with a sanity cap so a long river can't extend it forever.
            if dash.remaining <= 0 && tile != .water {
                fighter.endDash()
            } else if dash.remaining < -4 * GameConstants.tileSize {
                fighter.endDash()
            } else {
                fighter.dashState = dash
            }
        }
    }

    // MARK: - Firing entry points

    private var isPlaying: Bool {
        if case .playing = phase { return true }
        return false
    }

    private func fireMain(direction: CGVector, distance: CGFloat) {
        guard isPlaying, !player.isDead, !player.isDashing, player.consumeAmmo() else { return }
        shotsFired += 1
        performAttack(from: player, weapon: player.weapon, direction: direction, distance: distance)
    }

    private func fireSuper(direction: CGVector, distance: CGFloat) {
        guard isPlaying, !player.isDead, !player.isDashing, player.consumeSuper() else { return }
        performAttack(from: player, weapon: player.superWeapon, direction: direction, distance: distance)
        superButton.update(charge: 0)
    }

    /// Auto-aim: direction and distance to the nearest visible enemy,
    /// falling back to the player's facing at full range.
    private func autoAimSolution(range: CGFloat) -> (direction: CGVector, distance: CGFloat) {
        guard let enemy = nearestVisibleEnemy(of: player, within: range * 1.1) else {
            return (player.facing, range)
        }
        let dx = enemy.position.x - player.position.x
        let dy = enemy.position.y - player.position.y
        let distance = hypot(dx, dy)
        return (CGVector(dx: dx / distance, dy: dy / distance), distance)
    }

    // MARK: - Input

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        if case .ended = phase {
            handleResultsTap(touches)
            return
        }
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

    private func handleResultsTap(_ touches: Set<UITouch>) {
        guard let touch = touches.first else { return }
        let location = touch.location(in: hud)
        let tapped = hud.nodes(at: location)
        if tapped.contains(where: { $0.name == "menuButton" }) {
            let menu = MenuScene(size: size)
            menu.scaleMode = scaleMode
            view?.presentScene(menu, transition: .fade(withDuration: 0.4))
        } else {
            startMatch()
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
                let direction: CGVector
                let distance: CGFloat
                if magnitude >= tapThreshold {
                    direction = value
                    distance = magnitude * weapon.range   // joystick throw controls lob distance
                } else {
                    (direction, distance) = autoAimSolution(range: weapon.range)
                }
                if wasSuper {
                    fireSuper(direction: direction, distance: distance)
                } else {
                    fireMain(direction: direction, distance: distance)
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
                let id = ObjectIdentifier(fighter)
                guard !projectile.alreadyHit.contains(id) else { return }
                projectile.alreadyHit.insert(id)
                dealDamage(projectile.damage, to: fighter, from: projectile.owner,
                           knockbackDirection: projectile.travelDirection,
                           knockbackStrength: projectile.weapon.knockback)
                if !projectile.weapon.piercesFighters {
                    projectile.explode()
                }
            } else if let box = other as? LootBox {
                damageLootBox(box, amount: projectile.damage)
                projectile.explode()
            } else if projectile.destroysWalls, let wall = other, wall.name == "wallBreakable" {
                smashWall(wall)   // the shell plows on through
            } else {
                // Border wall or anything else solid.
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

    /// A Super shell blows an interior wall apart.
    private func smashWall(_ wall: SKNode) {
        guard wall.parent != nil else { return }
        for _ in 0..<6 {
            let debris = SKShapeNode(rectOf: CGSize(width: .random(in: 6...14),
                                                    height: .random(in: 6...14)),
                                     cornerRadius: 2)
            debris.fillColor = SKColor(red: 0.55, green: 0.4, blue: 0.27, alpha: 1)
            debris.strokeColor = .clear
            debris.position = CGPoint(x: wall.position.x + .random(in: -20...20),
                                      y: wall.position.y + .random(in: 10...50))
            debris.zPosition = wall.zPosition + 1
            world.addChild(debris)
            debris.run(.sequence([
                .group([
                    .moveBy(x: .random(in: -40...40), y: .random(in: -30...30), duration: 0.35),
                    .fadeOut(withDuration: 0.35),
                    .rotate(byAngle: .random(in: -2...2), duration: 0.35),
                ]),
                .removeFromParent(),
            ]))
        }
        wall.removeFromParent()
    }

    // MARK: - Match flow

    private func eliminate(_ fighter: Fighter, by killerName: String?) {
        NSLog("NOBLESTARS eliminated %@ (by %@), %d remain",
              fighter.displayName, killerName ?? "gas", fighters.count - 1)
        let rankAtDeath = fighters.count
        fighters.removeAll { $0 === fighter }
        brains.removeAll { $0.fighter === fighter }
        fighter.die()
        updatePlayersLeftLabel()
        showKillFeed(victim: fighter.displayName, killer: killerName)

        if fighter === player {
            endMatch(rank: rankAtDeath, victory: false)
        } else if fighters.count == 1, fighters.first === player {
            endMatch(rank: 1, victory: true)
        }
    }

    private func endMatch(rank: Int, victory: Bool) {
        phase = .ended
        moveTouch = nil
        aimTouch = nil
        moveJoystick.end()
        aimJoystick.end()
        aimLine.path = nil

        resultsOverlay.removeAllChildren()
        let dim = SKSpriteNode(color: SKColor(white: 0, alpha: 0.55),
                               size: CGSize(width: 4000, height: 4000))
        resultsOverlay.addChild(dim)

        let title = SKLabelNode(fontNamed: "AvenirNext-Heavy")
        title.fontSize = 54
        title.fontColor = victory
            ? SKColor(red: 1.0, green: 0.85, blue: 0.2, alpha: 1)
            : SKColor(red: 0.95, green: 0.4, blue: 0.35, alpha: 1)
        title.text = victory ? "VICTORY!" : "DEFEATED"
        title.position = CGPoint(x: 0, y: 50)
        resultsOverlay.addChild(title)

        let subtitle = SKLabelNode(fontNamed: "AvenirNext-Bold")
        subtitle.fontSize = 28
        subtitle.fontColor = .white
        subtitle.text = "You placed #\(rank) of 10"
        subtitle.position = CGPoint(x: 0, y: 0)
        resultsOverlay.addChild(subtitle)

        let hint = SKLabelNode(fontNamed: "AvenirNext-Medium")
        hint.fontSize = 20
        hint.fontColor = SKColor(white: 1, alpha: 0.8)
        hint.text = "Tap anywhere to play again"
        hint.position = CGPoint(x: 0, y: -50)
        hint.run(.repeatForever(.sequence([.fadeAlpha(to: 0.4, duration: 0.7),
                                           .fadeAlpha(to: 0.9, duration: 0.7)])))
        resultsOverlay.addChild(hint)

        let menuButton = SKLabelNode(fontNamed: "AvenirNext-Bold")
        menuButton.fontSize = 22
        menuButton.fontColor = SKColor(red: 0.5, green: 0.85, blue: 1.0, alpha: 1)
        menuButton.text = "CHARACTER SELECT"
        menuButton.name = "menuButton"
        menuButton.position = CGPoint(x: 0, y: -100)
        resultsOverlay.addChild(menuButton)

        hud.addChild(resultsOverlay)
    }

    private func updatePlayersLeftLabel() {
        playersLeftLabel.text = "\(fighters.count) LEFT"
    }

    private func showKillFeed(victim: String, killer: String?) {
        killFeedLabel.removeAllActions()
        killFeedLabel.alpha = 1
        killFeedLabel.text = killer.map { "\($0) eliminated \(victim)" } ?? "\(victim) died in the gas"
        killFeedLabel.run(.sequence([.wait(forDuration: 3), .fadeOut(withDuration: 0.6)]))
    }

    // MARK: - Game loop

    override func update(_ currentTime: TimeInterval) {
        let dt = lastUpdateTime > 0 ? min(currentTime - lastUpdateTime, 1.0 / 20.0) : 0
        lastUpdateTime = currentTime

        switch phase {
        case .countdown(let endsAt):
            if endsAt == 0 {
                phase = .countdown(endsAt: currentTime + 3.5)
            } else if currentTime >= endsAt {
                phase = .playing
                countdownLabel.run(.sequence([.wait(forDuration: 0.5), .fadeOut(withDuration: 0.3),
                                              .run { [countdownLabel] in
                                                  countdownLabel.isHidden = true
                                                  countdownLabel.alpha = 1
                                              }]))
                countdownLabel.text = "FIGHT!"
                gasRing = GasRing(map: arena.map, startTime: currentTime, parent: world)
            } else {
                let remaining = Int(ceil(endsAt - currentTime))
                countdownLabel.text = "\(remaining)"
            }
            // Fighters hold still during the countdown.
            for fighter in fighters {
                fighter.applyMovement(.zero)
            }
        case .playing:
            runPlaying(dt: dt, currentTime: currentTime)
        case .ended:
            break
        }

        // Always keep depth-sort and cosmetics fresh.
        for fighter in fighters {
            fighter.zPosition = ZLayer.ySorted(baselineY: fighter.position.y,
                                               mapPixelHeight: arena.map.pixelHeight)
            fighter.setConcealment(alpha: concealmentAlpha(for: fighter))
        }
        arena.updateBushReveal(around: player.position,
                               isInBush: arena.map.tile(at: player.position) == .bush)

        debugLabel?.text = String(
            format: "shots:%d ammo:%.2f super:%.2f alive:%d projectiles:%d gasInset:%d",
            shotsFired, player.ammo, player.superCharge,
            fighters.count, projectiles.count, gasRing?.inset ?? 0
        )
    }

    /// You always see yourself faintly in a bush; hidden enemies are fully
    /// invisible until you're right on top of them.
    private func concealmentAlpha(for fighter: Fighter) -> CGFloat {
        guard arena.map.tile(at: fighter.position) == .bush else { return 1.0 }
        if fighter === player { return 0.55 }
        let distance = hypot(fighter.position.x - player.position.x,
                             fighter.position.y - player.position.y)
        return distance < GameConstants.tileSize * 2 ? 0.5 : 0.0
    }

    private func runPlaying(dt: TimeInterval, currentTime: TimeInterval) {
        if !player.isDead {
            let keyboard = keyboardMovement
            let movement = autoWalkInput
                ?? (hypot(keyboard.dx, keyboard.dy) > 0 ? keyboard : moveJoystick.value)
            player.applyMovement(movement)
            if aimTouch != nil, hypot(aimJoystick.value.dx, aimJoystick.value.dy) > 0.15 {
                player.face(aimJoystick.value)
            }
            pollKeyboardActions()
        }

        // Bots think and act.
        for brain in brains {
            let decision = brain.decide(now: currentTime, scene: self)
            brain.fighter.applyMovement(decision.move)
            if let direction = decision.fireDirection, !brain.fighter.isDashing {
                if decision.useSuper, brain.fighter.consumeSuper() {
                    performAttack(from: brain.fighter, weapon: brain.fighter.superWeapon,
                                  direction: direction, distance: decision.fireDistance)
                } else if !decision.useSuper, brain.fighter.consumeAmmo() {
                    performAttack(from: brain.fighter, weapon: brain.fighter.weapon,
                                  direction: direction, distance: decision.fireDistance)
                }
            }
        }

        updateDashes(dt: dt)

        for fighter in fighters {
            fighter.tick(dt: dt, currentTime: currentTime)
        }

        // Gas shrink + damage (kills anyone it finishes off).
        if let gasRing {
            let vulnerable = godMode ? fighters.filter { $0 !== player } : fighters
            let damaged = gasRing.tick(now: currentTime, fighters: vulnerable)
            if damaged.contains(where: { $0 === player }) {
                tookDamageHaptic.impactOccurred()
            }
            for fighter in damaged where fighter.isDead {
                eliminate(fighter, by: nil)
            }
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
    }

    /// Aim indicator: a filled cone matching the weapon's spread (or reach),
    /// ending exactly where the attack expires.
    private func updateAimLine() {
        guard aimTouch != nil, !player.isDead,
              hypot(aimJoystick.value.dx, aimJoystick.value.dy) >= tapThreshold else {
            aimLine.path = nil
            return
        }
        let weapon = aimingSuper ? player.superWeapon : player.weapon
        let start = CGPoint(x: player.position.x, y: player.position.y + 18)
        let facingAngle = atan2(player.facing.dy, player.facing.dx)
        let spreadDegrees = max(weapon.spreadDegrees, 10)
        let halfSpread = spreadDegrees * .pi / 180 / 2

        let path = CGMutablePath()
        if weapon.style == .lob {
            // Show the landing zone instead of a cone.
            let magnitude = hypot(aimJoystick.value.dx, aimJoystick.value.dy)
            let throwDistance = min(max(magnitude * weapon.range, GameConstants.tileSize * 1.5), weapon.range)
            let center = CGPoint(x: start.x + player.facing.dx * throwDistance,
                                 y: start.y + player.facing.dy * throwDistance)
            path.addEllipse(in: CGRect(x: center.x - weapon.aoeRadius, y: center.y - weapon.aoeRadius,
                                       width: weapon.aoeRadius * 2, height: weapon.aoeRadius * 2))
        } else {
            path.move(to: start)
            path.addArc(center: start, radius: weapon.range,
                        startAngle: facingAngle - halfSpread,
                        endAngle: facingAngle + halfSpread,
                        clockwise: false)
            path.closeSubpath()
        }
        aimLine.path = path
        aimLine.lineWidth = 1.5
        if aimingSuper {
            aimLine.fillColor = SKColor(red: 1.0, green: 0.6, blue: 0.15, alpha: 0.22)
            aimLine.strokeColor = SKColor(red: 1.0, green: 0.7, blue: 0.2, alpha: 0.6)
        } else {
            aimLine.fillColor = SKColor(white: 1, alpha: 0.16)
            aimLine.strokeColor = SKColor(white: 1, alpha: 0.45)
        }
    }

    private func runAutoFireIfNeeded(_ currentTime: TimeInterval) {
        guard let interval = autoFireInterval,
              currentTime - lastAutoFire >= interval, !player.isDead else { return }
        lastAutoFire = currentTime
        if player.isSuperReady {
            let aim = autoAimSolution(range: player.superWeapon.range)
            fireSuper(direction: aim.direction, distance: aim.distance)
        } else {
            let aim = autoAimSolution(range: player.weapon.range)
            fireMain(direction: aim.direction, distance: aim.distance)
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
