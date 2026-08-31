import SpriteKit

/// Builds the visual + physical arena from an ArenaMap.
final class ArenaNode: SKNode {
    let map: ArenaMap

    private static let groundLight = SKColor(red: 0.55, green: 0.75, blue: 0.35, alpha: 1)
    private static let groundDark = SKColor(red: 0.51, green: 0.71, blue: 0.32, alpha: 1)
    private static let wallTop = SKColor(red: 0.62, green: 0.46, blue: 0.32, alpha: 1)
    private static let wallFace = SKColor(red: 0.45, green: 0.32, blue: 0.22, alpha: 1)
    private static let bushColor = SKColor(red: 0.22, green: 0.5, blue: 0.2, alpha: 1)
    private static let waterColor = SKColor(red: 0.3, green: 0.55, blue: 0.85, alpha: 1)

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
                let color = (row + col).isMultiple(of: 2) ? Self.groundLight : Self.groundDark
                let tile = SKSpriteNode(color: color, size: CGSize(width: ts, height: ts))
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
                switch map.tiles[row][col] {
                case .wall: addWall(at: center)
                case .bush: addBush(at: center)
                case .water: addWater(at: center)
                default: break
                }
            }
        }
    }

    private func addWall(at center: CGPoint) {
        let ts = GameConstants.tileSize
        let face = GameConstants.wallFaceHeight
        let baselineY = center.y - ts / 2

        let container = SKNode()
        container.position = CGPoint(x: center.x, y: baselineY)
        container.zPosition = ZLayer.ySorted(baselineY: baselineY, mapPixelHeight: map.pixelHeight)

        // Front face (fake height) then top face above it.
        let front = SKSpriteNode(color: Self.wallFace, size: CGSize(width: ts, height: face))
        front.anchorPoint = CGPoint(x: 0.5, y: 0)
        front.position = .zero
        container.addChild(front)

        let top = SKSpriteNode(color: Self.wallTop, size: CGSize(width: ts, height: ts))
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
        let bush = SKShapeNode(circleOfRadius: ts * 0.58)
        bush.fillColor = Self.bushColor
        bush.strokeColor = SKColor(red: 0.16, green: 0.38, blue: 0.15, alpha: 1)
        bush.lineWidth = 3
        bush.position = center
        bush.zPosition = ZLayer.bushCanopy
        bush.alpha = 0.92
        addChild(bush)
    }

    private func addWater(at center: CGPoint) {
        let ts = GameConstants.tileSize
        let water = SKSpriteNode(color: Self.waterColor, size: CGSize(width: ts, height: ts))
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
