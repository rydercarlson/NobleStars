import SpriteKit

/// Builds the visual + physical arena from an ArenaMap.
final class ArenaNode: SKNode {
    let map: ArenaMap
    private var bushNodes: [SKSpriteNode] = []

    private static let grassLight = SKTexture(imageNamed: "tile_grass_light")
    private static let grassDark = SKTexture(imageNamed: "tile_grass_dark")
    private static let wallTopTexture = SKTexture(imageNamed: "wall_top")
    private static let wallFrontTexture = SKTexture(imageNamed: "wall_front")
    private static let waterTexture = SKTexture(imageNamed: "tile_water")
    private static let bushTexture = SKTexture(imageNamed: "bush")

    init(map: ArenaMap) {
        self.map = map
        super.init()
        buildGround()
        buildTiles()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    private func buildGround() {
        let ts = GameConstants.tileSize
        for row in 0..<map.rows {
            for col in 0..<map.columns {
                let texture = (row + col).isMultiple(of: 2) ? Self.grassLight : Self.grassDark
                let tile = SKSpriteNode(texture: texture, size: CGSize(width: ts, height: ts))
                tile.position = map.worldCenter(col: col, row: row)
                tile.zPosition = ZLayer.ground
                addChild(tile)
            }
        }
    }

    private func buildTiles() {
        for row in 0..<map.rows {
            for col in 0..<map.columns {
                let center = map.worldCenter(col: col, row: row)
                let isBorder = row == 0 || col == 0 || row == map.rows - 1 || col == map.columns - 1
                switch map.tiles[row][col] {
                case .wall: addWall(at: center, isBorder: isBorder)
                case .bush: addBush(at: center)
                case .water: addWater(at: center)
                default: break
                }
            }
        }
    }

    private func addWall(at center: CGPoint, isBorder: Bool) {
        let ts = GameConstants.tileSize
        let face = GameConstants.wallFaceHeight
        let baselineY = center.y - ts / 2

        let container = SKNode()
        // Interior walls can be smashed by Supers; the border ring cannot.
        container.name = isBorder ? "wallBorder" : "wallBreakable"
        container.position = CGPoint(x: center.x, y: baselineY)
        container.zPosition = ZLayer.ySorted(baselineY: baselineY, mapPixelHeight: map.pixelHeight)

        // Front face (fake height) then top face above it.
        let front = SKSpriteNode(texture: Self.wallFrontTexture, size: CGSize(width: ts, height: face))
        front.anchorPoint = CGPoint(x: 0.5, y: 0)
        front.position = .zero
        container.addChild(front)

        let top = SKSpriteNode(texture: Self.wallTopTexture, size: CGSize(width: ts, height: ts))
        top.anchorPoint = CGPoint(x: 0.5, y: 0)
        top.position = CGPoint(x: 0, y: face)
        container.addChild(top)

        let body = SKPhysicsBody(
            rectangleOf: CGSize(width: ts, height: ts),
            center: CGPoint(x: 0, y: ts / 2)
        )
        body.isDynamic = false
        body.categoryBitMask = PhysicsCategory.wall
        container.physicsBody = body

        addChild(container)
    }

    private func addBush(at center: CGPoint) {
        let ts = GameConstants.tileSize
        let bush = SKSpriteNode(texture: Self.bushTexture,
                                size: CGSize(width: ts * 1.24, height: ts * 1.08))
        bush.position = center
        bush.zPosition = ZLayer.bushCanopy
        bush.alpha = 0.92
        addChild(bush)
        bushNodes.append(bush)
    }

    /// Bushes near a fighter standing inside them go translucent so the
    /// player can still see their own character.
    func updateBushReveal(around point: CGPoint, isInBush: Bool) {
        let revealRadius = GameConstants.tileSize * 1.6
        for bush in bushNodes {
            let distance = hypot(bush.position.x - point.x, bush.position.y - point.y)
            let target: CGFloat = (isInBush && distance < revealRadius) ? 0.4 : 0.92
            if abs(bush.alpha - target) > 0.01 {
                bush.alpha = target
            }
        }
    }

    private func addWater(at center: CGPoint) {
        let ts = GameConstants.tileSize
        let water = SKSpriteNode(texture: Self.waterTexture, size: CGSize(width: ts, height: ts))
        water.position = center
        water.zPosition = ZLayer.groundDecal

        // Blocks fighters, but projectiles will fly over (they don't collide with water).
        let body = SKPhysicsBody(rectangleOf: water.size)
        body.isDynamic = false
        body.categoryBitMask = PhysicsCategory.water
        water.physicsBody = body

        addChild(water)
    }
}
