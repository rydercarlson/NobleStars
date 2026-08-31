import CoreGraphics
import Foundation

/// How an attack is delivered.
enum AttackStyle {
    case pellets   // linear projectiles
    case lob       // arcing ball that flies over walls, splash on landing
    case melee     // instant swipe in an arc in front of the fighter
    case dash      // charge forward, damaging everyone touched
}

/// Stats for one attack. Fighters carry a main weapon and a Super.
struct Weapon {
    var style: AttackStyle = .pellets
    var pelletCount = 1
    var spreadDegrees: CGFloat = 0
    var pelletDamage: Int
    var range: CGFloat
    var projectileSpeed: CGFloat = 800
    var pelletRadius: CGFloat = 5
    /// Shells plow through breakable walls instead of stopping.
    var destroysWalls = false
    /// Impulse applied to fighters hit (points/sec, decays fast).
    var knockback: CGFloat = 0
    /// Projectile keeps flying after hitting a fighter.
    var piercesFighters = false
    /// Splash radius on landing (lob style).
    var aoeRadius: CGFloat = 0
    /// Damage multiplier when a dash has crossed water (dash style).
    var waterDamageMultiplier: CGFloat = 1
}

enum CombatTuning {
    static let maxAmmo: CGFloat = 3
    static let ammoRechargeSeconds: TimeInterval = 1.8
    /// Total damage dealt that fills the Super meter from empty.
    static let superChargeDamage: CGFloat = 2500
    /// Seconds without taking damage before self-healing kicks in.
    static let regenDelay: TimeInterval = 3.0
    /// Fraction of max health recovered per second while regenerating.
    static let regenRatePerSecond: CGFloat = 0.14
    static let baseMaxHealth = 3600
    static let healthPerPowerCube = 400
    static let damageBonusPerPowerCube: CGFloat = 0.10
}
