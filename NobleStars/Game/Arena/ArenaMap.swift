import CoreGraphics

enum TileType: Character {
    case ground = "."
    case wall = "#"
    case bush = "b"
    case water = "~"
    case lootBox = "X"
    case spawn = "S"

    var blocksMovement: Bool {
        self == .wall || self == .water
    }
}

/// A parsed arena layout. Row 0 of the ASCII art is the TOP of the map;
/// tile coordinates use (col, row) with row 0 at the top, but world positions
/// use SpriteKit's y-up convention.
struct ArenaMap {
    let columns: Int
    let rows: Int
    let tiles: [[TileType]]          // tiles[row][col], row 0 = top
    let spawnPoints: [CGPoint]       // world positions (tile centers)
    let lootBoxPoints: [CGPoint]     // world positions (tile centers)

    var pixelWidth: CGFloat { CGFloat(columns) * GameConstants.tileSize }
    var pixelHeight: CGFloat { CGFloat(rows) * GameConstants.tileSize }

    init(ascii: String) {
        let lines = ascii
            .split(separator: "\n", omittingEmptySubsequences: true)
            .map(String.init)
        rows = lines.count
        columns = lines.map(\.count).max() ?? 0

        var parsed: [[TileType]] = []
        var spawns: [CGPoint] = []
        var boxes: [CGPoint] = []

        for (row, line) in lines.enumerated() {
            var tileRow: [TileType] = []
            for col in 0..<columns {
                let chars = Array(line)
                let ch: Character = col < chars.count ? chars[col] : "."
                let tile = TileType(rawValue: ch) ?? .ground
                let center = ArenaMap.worldCenter(col: col, row: row, rows: lines.count)
                switch tile {
                case .spawn:
                    spawns.append(center)
                    tileRow.append(.ground)
                case .lootBox:
                    boxes.append(center)
                    tileRow.append(.ground)
                default:
                    tileRow.append(tile)
                }
            }
            parsed.append(tileRow)
        }

        tiles = parsed
        spawnPoints = spawns
        lootBoxPoints = boxes
    }

    static func worldCenter(col: Int, row: Int, rows: Int) -> CGPoint {
        let ts = GameConstants.tileSize
        return CGPoint(
            x: (CGFloat(col) + 0.5) * ts,
            y: (CGFloat(rows - 1 - row) + 0.5) * ts
        )
    }

    func worldCenter(col: Int, row: Int) -> CGPoint {
        ArenaMap.worldCenter(col: col, row: row, rows: rows)
    }

    /// Tile at a world position; out-of-bounds counts as wall.
    func tile(at point: CGPoint) -> TileType {
        let ts = GameConstants.tileSize
        let col = Int(floor(point.x / ts))
        let row = rows - 1 - Int(floor(point.y / ts))
        guard col >= 0, col < columns, row >= 0, row < rows else { return .wall }
        return tiles[row][col]
    }
}

enum ArenaMaps {
    /// 30x30 Showdown map: outer wall ring, rock clusters, bush patches, a pond.
    static let skullCreek = ArenaMap(ascii: """
    ##############################
    #............................#
    #.S....bbb..........bb.....S.#
    #......bbb....##....bb.......#
    #..##..bbb....##.........##..#
    #..##.........##....X....##..#
    #.......X................##..#
    #.............bb.............#
    #...~~~.......bb....####.....#
    #...~~~~......bb....#........#
    #.S.~~~~............#..X...S.#
    #....~~........X....#........#
    #..........................b.#
    #.....##...........##......b.#
    #.....##....bbbb...##......b.#
    #.S...##....bbbb...##........#
    #...........bbbb.......X...S.#
    #..X.........................#
    #........####................#
    #...bb......#.......~~~~.....#
    #...bb..X...#......~~~~~~....#
    #...bb......#.......~~~~.....#
    #.S..........................#
    #............##......bbb...S.#
    #....bb......##......bbb.....#
    #....bb......##..X...bbb.....#
    #....bb......................#
    #.S......X.........X.....S...#
    #............................#
    #............................#
    ##############################
    """)
}
