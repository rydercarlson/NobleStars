import SpriteKit

/// A playable character: identity plus main attack and Super.
struct FighterKit {
    let name: String
    let color: SKColor
    let blurb: String
    let weapon: Weapon
    let superWeapon: Weapon

    var portraitImage: String { "portrait_\(name.lowercased())" }
    var bodyImage: String { "body_\(name.lowercased())" }
    var weaponImage: String {
        switch weapon.style {
        case .lob: return "weapon_racket"
        case .melee: return "weapon_paddle"
        default: return "weapon_shotgun"
        }
    }

    /// Shotgun bruiser (the original starter fighter).
    static let nova = FighterKit(
        name: "Nova",
        color: SKColor(red: 0.25, green: 0.75, blue: 0.95, alpha: 1),
        blurb: "Shotgun burst · Super: wall-smashing blast",
        weapon: Weapon(
            style: .pellets,
            pelletCount: 5,
            spreadDegrees: 22,
            pelletDamage: 300,
            range: 5.0 * GameConstants.tileSize,
            projectileSpeed: 800,
            pelletRadius: 5
        ),
        superWeapon: Weapon(
            style: .pellets,
            pelletCount: 9,
            spreadDegrees: 34,
            pelletDamage: 450,
            range: 7.0 * GameConstants.tileSize,
            projectileSpeed: 880,
            pelletRadius: 10,
            destroysWalls: true,
            knockback: 520
        )
    )

    /// Tennis player: lobs balls over cover; Super is a cannon serve.
    static let tony = FighterKit(
        name: "Tony",
        color: SKColor(red: 0.98, green: 0.85, blue: 0.25, alpha: 1),
        blurb: "Lobs over walls · Super: wall-breaking serve",
        weapon: Weapon(
            style: .lob,
            pelletDamage: 900,
            range: 6.5 * GameConstants.tileSize,
            projectileSpeed: 620,
            pelletRadius: 9,
            aoeRadius: 0.9 * GameConstants.tileSize
        ),
        superWeapon: Weapon(
            style: .pellets,
            pelletDamage: 1300,
            range: 9.0 * GameConstants.tileSize,
            projectileSpeed: 1350,
            pelletRadius: 13,
            destroysWalls: true,
            knockback: 420,
            piercesFighters: true
        )
    )

    /// Rower: paddle swipes up close; Super is a damaging dash that
    /// crosses water and hits twice as hard when it does.
    static let henry = FighterKit(
        name: "Henry",
        color: SKColor(red: 0.45, green: 0.55, blue: 0.95, alpha: 1),
        blurb: "Paddle swipe · Super: rowing dash, 2× over water",
        weapon: Weapon(
            style: .melee,
            spreadDegrees: 110,
            pelletDamage: 750,
            range: 1.9 * GameConstants.tileSize
        ),
        superWeapon: Weapon(
            style: .dash,
            pelletDamage: 1000,
            range: 4.5 * GameConstants.tileSize,
            projectileSpeed: 1100,
            knockback: 380,
            waterDamageMultiplier: 2
        )
    )

    static let all: [FighterKit] = [.nova, .tony, .henry]

    static func named(_ name: String) -> FighterKit? {
        all.first { $0.name.lowercased() == name.lowercased() }
    }
}
