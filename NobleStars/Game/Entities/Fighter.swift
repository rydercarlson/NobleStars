import SpriteKit

/// A fighter in the arena — the player or a bot. Visuals are placeholder
/// shapes until the M4 art pass; the node's position is the fighter's feet.
final class Fighter: SKNode {
    let bodyRadius: CGFloat = 20
    var moveSpeed: CGFloat = 250
    let kit: FighterKit
    var weapon: Weapon { kit.weapon }
    var superWeapon: Weapon { kit.superWeapon }
    let bodyColor: SKColor
    var displayName = "Fighter"

    private(set) var maxHealth = CombatTuning.baseMaxHealth
    private(set) var health = CombatTuning.baseMaxHealth
    private(set) var ammo = CombatTuning.maxAmmo
    private(set) var superCharge: CGFloat = 0   // 0...1
    private(set) var powerCubes = 0
    private(set) var lastDamageTime: TimeInterval = 0
    var isDead: Bool { health <= 0 }

    /// Damage multiplier from power cubes.
    var damageMultiplier: CGFloat { 1 + CombatTuning.damageBonusPerPowerCube * CGFloat(powerCubes) }
    var isSuperReady: Bool { superCharge >= 1 }

    private let bodyNode: SKShapeNode
    private let shadowNode: SKShapeNode
    private let statusBar: StatusBar

    /// Direction the fighter is facing, for aiming and the facing indicator.
    private(set) var facing = CGVector(dx: 0, dy: -1)
    private let facingDot: SKShapeNode

    init(kit: FighterKit) {
        self.kit = kit
        let color = kit.color
        bodyColor = color

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

        statusBar = StatusBar(healthColor: color)
        statusBar.position = CGPoint(x: 0, y: 52)

        super.init()

        addChild(shadowNode)
        addChild(bodyNode)
        bodyNode.addChild(facingDot)
        addChild(statusBar)
        updateFacingDot()
        refreshStatusBar()

        let body = SKPhysicsBody(circleOfRadius: bodyRadius)
        body.allowsRotation = false
        body.friction = 0
        body.restitution = 0
        body.linearDamping = 0
        body.categoryBitMask = PhysicsCategory.fighter
        body.collisionBitMask = PhysicsCategory.wall | PhysicsCategory.water | PhysicsCategory.fighter | PhysicsCategory.lootBox
        body.contactTestBitMask = PhysicsCategory.pickup
        physicsBody = body
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    // MARK: - Movement & facing

    /// Residual shove from knockback hits; decays every tick.
    private var knockbackVelocity = CGVector.zero

    // MARK: - Dash Super

    struct DashState {
        let weapon: Weapon
        let direction: CGVector
        var remaining: CGFloat
        var alreadyHit: Set<ObjectIdentifier> = []
        var crossedWater = false
    }
    var dashState: DashState?
    var isDashing: Bool { dashState != nil }

    func beginDash(weapon: Weapon, direction: CGVector) {
        dashState = DashState(weapon: weapon, direction: direction, remaining: weapon.range)
        face(direction)
        // Dash can cross water.
        physicsBody?.collisionBitMask = PhysicsCategory.wall
    }

    func endDash() {
        dashState = nil
        physicsBody?.collisionBitMask =
            PhysicsCategory.wall | PhysicsCategory.water | PhysicsCategory.fighter | PhysicsCategory.lootBox
    }

    /// Drive movement from a joystick vector (magnitude 0...1).
    func applyMovement(_ input: CGVector) {
        guard let body = physicsBody else { return }
        if let dash = dashState {
            body.velocity = CGVector(dx: dash.direction.dx * dash.weapon.projectileSpeed,
                                     dy: dash.direction.dy * dash.weapon.projectileSpeed)
            return
        }
        body.velocity = CGVector(dx: input.dx * moveSpeed + knockbackVelocity.dx,
                                 dy: input.dy * moveSpeed + knockbackVelocity.dy)
        let magnitude = hypot(input.dx, input.dy)
        if magnitude > 0.1 {
            face(CGVector(dx: input.dx / magnitude, dy: input.dy / magnitude))
        }
    }

    func receiveKnockback(direction: CGVector, strength: CGFloat) {
        knockbackVelocity = CGVector(dx: knockbackVelocity.dx + direction.dx * strength,
                                     dy: knockbackVelocity.dy + direction.dy * strength)
    }

    func face(_ direction: CGVector) {
        let magnitude = hypot(direction.dx, direction.dy)
        guard magnitude > 0.001 else { return }
        facing = CGVector(dx: direction.dx / magnitude, dy: direction.dy / magnitude)
        updateFacingDot()
    }

    /// Bush concealment. You always see yourself faintly; enemies deep in a
    /// bush disappear completely unless they're right next to the viewer.
    func setConcealment(alpha target: CGFloat) {
        if abs(alpha - target) > 0.01 {
            run(.fadeAlpha(to: target, duration: 0.15))
        }
    }

    // MARK: - Combat

    /// Spend one ammo if available. Returns whether the shot may fire.
    func consumeAmmo() -> Bool {
        guard ammo >= 1 else { return false }
        ammo -= 1
        refreshStatusBar()
        return true
    }

    func consumeSuper() -> Bool {
        guard isSuperReady else { return false }
        superCharge = 0
        return true
    }

    func chargeSuper(damageDealt: Int) {
        superCharge = min(1, superCharge + CGFloat(damageDealt) / CombatTuning.superChargeDamage)
    }

    /// Damage accumulated toward the next popup so one shotgun volley shows
    /// a single satisfying number instead of five overlapping ones.
    private var pendingDamagePopup = 0

    func takeDamage(_ amount: Int, at time: TimeInterval) {
        guard !isDead else { return }
        health = max(0, health - amount)
        lastDamageTime = time
        pendingDamagePopup += amount
        refreshStatusBar()
        // Hit flash.
        bodyNode.run(.sequence([
            .run { [bodyNode] in bodyNode.fillColor = SKColor(white: 1, alpha: 1) },
            .wait(forDuration: 0.07),
            .run { [bodyNode, bodyColor] in bodyNode.fillColor = bodyColor },
        ]))
    }

    private func emitDamageNumber(_ amount: Int) {
        let label = SKLabelNode(fontNamed: "AvenirNext-Heavy")
        label.text = "\(amount)"
        label.fontSize = 24
        label.fontColor = SKColor(red: 1.0, green: 0.25, blue: 0.2, alpha: 1)
        label.position = CGPoint(x: CGFloat.random(in: -10...10), y: 44)
        label.zPosition = 6
        label.setScale(0.5)
        addChild(label)
        label.run(.sequence([
            .group([
                .scale(to: 1.0, duration: 0.12),
                .moveBy(x: 0, y: 30, duration: 0.7),
                .sequence([.wait(forDuration: 0.35), .fadeOut(withDuration: 0.35)]),
            ]),
            .removeFromParent(),
        ]))
    }

    func collectPowerCube() {
        powerCubes += 1
        maxHealth += CombatTuning.healthPerPowerCube
        health += CombatTuning.healthPerPowerCube
        refreshStatusBar()
        run(.sequence([.scale(to: 1.2, duration: 0.1), .scale(to: 1.0, duration: 0.1)]))

        // Spell out exactly what the cube just did.
        let bonus = Int(CombatTuning.damageBonusPerPowerCube * 100)
        let label = SKLabelNode(fontNamed: "AvenirNext-Bold")
        label.text = "+\(CombatTuning.healthPerPowerCube) HP  +\(bonus)% DMG"
        label.fontSize = 15
        label.fontColor = SKColor(red: 0.85, green: 0.45, blue: 1.0, alpha: 1)
        label.position = CGPoint(x: 0, y: 62)
        label.zPosition = 6
        addChild(label)
        label.run(.sequence([
            .group([.moveBy(x: 0, y: 26, duration: 1.0),
                    .sequence([.wait(forDuration: 0.6), .fadeOut(withDuration: 0.4)])]),
            .removeFromParent(),
        ]))
    }

    private var lastHealEffectAt: TimeInterval = 0

    /// Per-frame upkeep: ammo recharge, self-heal, knockback decay.
    /// `dt` is seconds since last frame.
    func tick(dt: TimeInterval, currentTime: TimeInterval) {
        var dirty = false
        if ammo < CombatTuning.maxAmmo {
            ammo = min(CombatTuning.maxAmmo, ammo + CGFloat(dt / CombatTuning.ammoRechargeSeconds))
            dirty = true
        }
        if !isDead, health < maxHealth, currentTime - lastDamageTime > CombatTuning.regenDelay {
            let healed = CGFloat(maxHealth) * CombatTuning.regenRatePerSecond * CGFloat(dt)
            health = min(maxHealth, health + Int(healed.rounded(.up)))
            dirty = true
            if currentTime - lastHealEffectAt > 0.45 {
                lastHealEffectAt = currentTime
                emitHealEffect()
            }
        }
        // Flush the batched damage popup once the volley stops landing.
        if pendingDamagePopup > 0, currentTime - lastDamageTime > 0.12 {
            emitDamageNumber(pendingDamagePopup)
            pendingDamagePopup = 0
        }
        if hypot(knockbackVelocity.dx, knockbackVelocity.dy) > 1 {
            let decay = CGFloat(pow(0.0001, dt))   // ~gone in half a second
            knockbackVelocity = CGVector(dx: knockbackVelocity.dx * decay,
                                         dy: knockbackVelocity.dy * decay)
        } else {
            knockbackVelocity = .zero
        }
        if dirty { refreshStatusBar() }
    }

    /// Floating green "+" so healing is readable at a glance.
    private func emitHealEffect() {
        let plus = SKLabelNode(fontNamed: "AvenirNext-Bold")
        plus.text = "+"
        plus.fontSize = 22
        plus.fontColor = SKColor(red: 0.3, green: 0.95, blue: 0.35, alpha: 1)
        plus.position = CGPoint(x: CGFloat.random(in: -14...14), y: 34)
        plus.zPosition = 5
        addChild(plus)
        plus.run(.sequence([
            .group([.moveBy(x: 0, y: 26, duration: 0.7), .fadeOut(withDuration: 0.7)]),
            .removeFromParent(),
        ]))
    }

    func die() {
        physicsBody = nil
        run(.sequence([
            .group([.fadeOut(withDuration: 0.35), .scale(to: 0.3, duration: 0.35)]),
            .removeFromParent(),
        ]))
    }

    private func refreshStatusBar() {
        statusBar.update(health: health, maxHealth: maxHealth, ammo: ammo, cubes: powerCubes)
    }

    private func updateFacingDot() {
        facingDot.position = CGPoint(x: facing.dx * bodyRadius * 0.65,
                                     y: facing.dy * bodyRadius * 0.65)
    }
}
