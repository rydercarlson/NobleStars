import CoreGraphics
import Foundation

/// Stats for one attack. Fighters carry a main weapon and a Super.
struct Weapon {
    var pelletCount: Int
    var spreadDegrees: CGFloat
    var pelletDamage: Int
    var range: CGFloat
    var projectileSpeed: CGFloat
    var pelletRadius: CGFloat

    /// The starter fighter's main attack: a short-range shotgun fan.
    static let shotgun = Weapon(
        pelletCount: 5,
        spreadDegrees: 22,
        pelletDamage: 300,
        range: 6.5 * GameConstants.tileSize,
        projectileSpeed: 950,
        pelletRadius: 5
    )

    /// The starter fighter's Super: a wider, longer, harder-hitting blast.
    static let shotgunSuper = Weapon(
        pelletCount: 9,
        spreadDegrees: 36,
        pelletDamage: 400,
        range: 8.5 * GameConstants.tileSize,
        projectileSpeed: 950,
        pelletRadius: 7
    )
}

enum CombatTuning {
    static let maxAmmo: CGFloat = 3
    static let ammoRechargeSeconds: TimeInterval = 1.8
    /// Total damage dealt that fills the Super meter from empty.
    static let superChargeDamage: CGFloat = 4000
    /// Seconds without taking damage before self-healing kicks in.
    static let regenDelay: TimeInterval = 3.0
    /// Fraction of max health recovered per second while regenerating.
    static let regenRatePerSecond: CGFloat = 0.14
    static let baseMaxHealth = 3600
    static let healthPerPowerCube = 400
    static let damageBonusPerPowerCube: CGFloat = 0.10
}
