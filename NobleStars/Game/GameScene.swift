import SpriteKit

final class GameScene: SKScene, SKPhysicsContactDelegate {
    private enum MatchPhase {
        case countdown(endsAt: TimeInterval)
        case playing
        case ended
    }

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
    private var matchStarted = false

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

    private static let botColors: [SKColor] = [
        SKColor(red: 0.9, green: 0.35, blue: 0.3, alpha: 1),
        SKColor(red: 0.95, green: 0.6, blue: 0.2, alpha: 1),
        SKColor(red: 0.85, green: 0.8, blue: 0.25, alpha: 1),
        SKColor(red: 0.4, green: 0.8, blue: 0.35, alpha: 1),
        SKColor(red: 0.3, green: 0.6, blue: 0.5, alpha: 1),
        SKColor(red: 0.5, green: 0.45, blue: 0.9, alpha: 1),
        SKColor(red: 0.75, green: 0.4, blue: 0.9, alpha: 1),
        SKColor(red: 0.95, green: 0.5, blue: 0.7, alpha: 1),
        SKColor(red: 0.6, green: 0.55, blue: 0.45, alpha: 1),
    ]

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
        matchStarted = false
        lastUpdateTime = 0
        shotsFired = 0

        let map = ArenaMaps.skullCreek
        arena = ArenaNode(map: map)
        world.addChild(arena)

        var spawns = map.spawnPoints.shuffled()
        if spawns.isEmpty {
            spawns = [CGPoint(x: map.pixelWidth / 2, y: map.pixelHeight / 2)]
        }

        player = Fighter(color: SKColor(red: 0.25, green: 0.75, blue: 0.95, alpha: 1))
        player.displayName = "You"
        player.position = spawns.removeFirst()
        world.addChild(player)
        fighters.append(player)

        for (index, color) in Self.botColors.enumerated() {
            guard !spawns.isEmpty else { break }
            let bot = Fighter(color: color)
            bot.displayName = "Bot \(index + 1)"
            bot.position = spawns.removeFirst()
            world.addChild(bot)
            fighters.append(bot)
            brains.append(BotBrain(fighter: bot))
        }

        for point in map.lootBoxPoints {
            let box = LootBox(mapPixelHeight: map.pixelHeight)
            box.position = point
            box.zPosition = ZLayer.ySorted(baselineY: point.y - 20, mapPixelHeight: map.pixelHeight)
            world.addChild(box)
        }

        aimLine.path = nil
        aimLine.lineWidth = 3
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

    // MARK: - Firing

    private var isPlaying: Bool {
        if case .playing = phase { return true }
        return false
    }

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
        guard isPlaying, !player.isDead, player.consumeAmmo() else { return }
        shotsFired += 1
        fire(from: player, weapon: player.weapon, direction: direction)
    }

    private func fireSuper(direction: CGVector) {
        guard isPlaying, !player.isDead, player.consumeSuper() else { return }
        fire(from: player, weapon: player.superWeapon, direction: direction)
        superButton.update(charge: 0)
    }

    /// Direction to the nearest visible enemy in range, else the player's facing.
    private func autoAimDirection(range: CGFloat) -> CGVector {
        guard let enemy = nearestVisibleEnemy(of: player, within: range * 1.1) else {
            return player.facing
        }
        let dx = enemy.position.x - player.position.x
        let dy = enemy.position.y - player.position.y
        let distance = hypot(dx, dy)
        return CGVector(dx: dx / distance, dy: dy / distance)
    }

    // MARK: - Input

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        if case .ended = phase {
            startMatch()
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
                if godMode, fighter === player {
                    projectile.explode()
                    return
                }
                fighter.takeDamage(projectile.damage, at: lastUpdateTime)
                projectile.owner.chargeSuper(damageDealt: projectile.damage)
                if fighter.isDead {
                    eliminate(fighter, by: projectile.owner.displayName)
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
        title.position = CGPoint(x: 0, y: 40)
        resultsOverlay.addChild(title)

        let subtitle = SKLabelNode(fontNamed: "AvenirNext-Bold")
        subtitle.fontSize = 28
        subtitle.fontColor = .white
        subtitle.text = "You placed #\(rank) of 10"
        subtitle.position = CGPoint(x: 0, y: -10)
        resultsOverlay.addChild(subtitle)

        let hint = SKLabelNode(fontNamed: "AvenirNext-Medium")
        hint.fontSize = 20
        hint.fontColor = SKColor(white: 1, alpha: 0.8)
        hint.text = "Tap anywhere to play again"
        hint.position = CGPoint(x: 0, y: -60)
        hint.run(.repeatForever(.sequence([.fadeAlpha(to: 0.4, duration: 0.7),
                                           .fadeAlpha(to: 0.9, duration: 0.7)])))
        resultsOverlay.addChild(hint)

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
            fighter.setHidden(inBush: arena.map.tile(at: fighter.position) == .bush)
        }

        debugLabel?.text = String(
            format: "shots:%d ammo:%.2f super:%.2f alive:%d projectiles:%d gasInset:%d",
            shotsFired, player.ammo, player.superCharge,
            fighters.count, projectiles.count, gasRing?.inset ?? 0
        )
    }

    private func runPlaying(dt: TimeInterval, currentTime: TimeInterval) {
        if !player.isDead {
            player.applyMovement(autoWalkInput ?? moveJoystick.value)
            if aimTouch != nil, hypot(aimJoystick.value.dx, aimJoystick.value.dy) > 0.15 {
                player.face(aimJoystick.value)
            }
        }

        // Bots think and act.
        for brain in brains {
            let decision = brain.decide(now: currentTime, scene: self)
            brain.fighter.applyMovement(decision.move)
            if let direction = decision.fireDirection {
                if decision.useSuper, brain.fighter.consumeSuper() {
                    fire(from: brain.fighter, weapon: brain.fighter.superWeapon, direction: direction)
                } else if brain.fighter.consumeAmmo() {
                    fire(from: brain.fighter, weapon: brain.fighter.weapon, direction: direction)
                }
            }
        }

        for fighter in fighters {
            fighter.tick(dt: dt, currentTime: currentTime)
        }

        // Gas shrink + damage (kills anyone it finishes off).
        if let gasRing {
            let vulnerable = godMode ? fighters.filter { $0 !== player } : fighters
            let damaged = gasRing.tick(now: currentTime, fighters: vulnerable)
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
