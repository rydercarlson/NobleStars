import SpriteKit

/// Decision-making for one bot: a small priority-based state machine.
/// The scene executes the returned decision (movement + optional shot).
final class BotBrain {
    let fighter: Fighter

    struct Decision {
        var move = CGVector.zero
        var fireDirection: CGVector?
        var fireDistance: CGFloat = 0
        var useSuper = false
    }

    private enum Mode { case wander, loot, engage, flee, escapeGas }

    private var wanderTarget: CGPoint?
    private var repickWanderAt: TimeInterval = 0
    private var nextFireAt: TimeInterval = 0

    // Unstick detection: if we want to move but barely do, take a detour.
    private var lastCheckedPosition: CGPoint = .zero
    private var nextStuckCheckAt: TimeInterval = 0
    private var detour: CGVector?
    private var detourEndsAt: TimeInterval = 0

    /// Personality jitter so bots don't feel identical.
    private let aimErrorDegrees: CGFloat = .random(in: 3...9)
    private let fireInterval: TimeInterval = .random(in: 1.0...1.6)
    private let engageRange: CGFloat = GameConstants.tileSize * .random(in: 5.5...7.0)

    init(fighter: Fighter) {
        self.fighter = fighter
    }

    func decide(now: TimeInterval, scene: GameScene) -> Decision {
        var decision = Decision()

        let visibleEnemy = scene.nearestVisibleEnemy(of: fighter, within: engageRange)
        let mode = pickMode(now: now, scene: scene, enemy: visibleEnemy)

        switch mode {
        case .escapeGas:
            decision.move = direction(to: scene.gasSafeCenter)
        case .flee:
            if let enemy = visibleEnemy {
                let away = direction(from: enemy.position)
                let toCenter = direction(to: scene.gasSafeCenter)
                decision.move = normalized(CGVector(dx: away.dx + toCenter.dx * 0.5,
                                                    dy: away.dy + toCenter.dy * 0.5))
            }
        case .engage:
            if let enemy = visibleEnemy {
                let distance = hypot(enemy.position.x - fighter.position.x,
                                     enemy.position.y - fighter.position.y)
                // Fight at a range suited to the kit: melee closes all the
                // way in, ranged kits keep their distance.
                let ideal = max(GameConstants.tileSize * 0.9, fighter.weapon.range * 0.7)
                let toward = direction(to: enemy.position)
                // Approach if far, back off if too close, strafe a bit in between.
                if distance > ideal * 1.2 {
                    decision.move = toward
                } else if distance < ideal * 0.7 {
                    decision.move = CGVector(dx: -toward.dx, dy: -toward.dy)
                } else {
                    decision.move = CGVector(dx: -toward.dy * 0.6, dy: toward.dx * 0.6)
                }
            }
        case .loot:
            if let loot = scene.nearestLoot(to: fighter.position) {
                decision.move = direction(to: loot)
            }
        case .wander:
            if wanderTarget == nil || now >= repickWanderAt ||
                distanceTo(wanderTarget!) < GameConstants.tileSize {
                wanderTarget = scene.randomWanderPoint(near: fighter.position)
                repickWanderAt = now + .random(in: 2.5...4.5)
            }
            if let target = wanderTarget {
                decision.move = direction(to: target)
            }
        }

        // Shooting: independent of movement mode, on a personal cooldown.
        // Only swing/fire when the enemy is actually within the weapon's
        // reach (matters most for melee kits).
        if let enemy = visibleEnemy, now >= nextFireAt {
            let enemyDistance = distanceTo(enemy.position)
            let useSuper = fighter.isSuperReady
            let reach = (useSuper ? fighter.superWeapon : fighter.weapon).range
            if enemyDistance < reach + GameConstants.tileSize * 0.5 {
                nextFireAt = now + fireInterval
                let error = CGFloat.random(in: -aimErrorDegrees...aimErrorDegrees) * .pi / 180
                let base = direction(to: enemy.position)
                let angle = atan2(base.dy, base.dx) + error
                decision.fireDirection = CGVector(dx: cos(angle), dy: sin(angle))
                decision.fireDistance = enemyDistance
                decision.useSuper = useSuper
            }
        }

        applyUnstick(now: now, to: &decision)
        return decision
    }

    private func pickMode(now: TimeInterval, scene: GameScene, enemy: Fighter?) -> Mode {
        if !scene.gasContains(fighter.position) { return .escapeGas }
        if let _ = enemy, CGFloat(fighter.health) < CGFloat(fighter.maxHealth) * 0.3 { return .flee }
        if enemy != nil { return .engage }
        if scene.nearestLoot(to: fighter.position) != nil { return .loot }
        return .wander
    }

    private func applyUnstick(now: TimeInterval, to decision: inout Decision) {
        if let active = detour, now < detourEndsAt {
            decision.move = active
            return
        }
        detour = nil

        guard hypot(decision.move.dx, decision.move.dy) > 0.1 else {
            nextStuckCheckAt = now + 0.6
            lastCheckedPosition = fighter.position
            return
        }
        if now >= nextStuckCheckAt {
            let moved = hypot(fighter.position.x - lastCheckedPosition.x,
                              fighter.position.y - lastCheckedPosition.y)
            if nextStuckCheckAt > 0, moved < 6 {
                // Barely moved while trying to: sidestep perpendicular to the goal.
                let side: CGFloat = Bool.random() ? 1 : -1
                detour = CGVector(dx: -decision.move.dy * side, dy: decision.move.dx * side)
                detourEndsAt = now + 0.5
            }
            lastCheckedPosition = fighter.position
            nextStuckCheckAt = now + 0.6
        }
    }

    // MARK: - Vector helpers

    private func distanceTo(_ point: CGPoint) -> CGFloat {
        hypot(point.x - fighter.position.x, point.y - fighter.position.y)
    }

    private func direction(to point: CGPoint) -> CGVector {
        normalized(CGVector(dx: point.x - fighter.position.x, dy: point.y - fighter.position.y))
    }

    private func direction(from point: CGPoint) -> CGVector {
        normalized(CGVector(dx: fighter.position.x - point.x, dy: fighter.position.y - point.y))
    }

    private func normalized(_ v: CGVector) -> CGVector {
        let m = hypot(v.dx, v.dy)
        guard m > 0.001 else { return .zero }
        return CGVector(dx: v.dx / m, dy: v.dy / m)
    }
}
