import SpriteKit

/// Title screen + character select.
final class MenuScene: SKScene {
    private var selectedIndex = 0
    private var cardNodes: [SKShapeNode] = []
    private let root = SKNode()

    override func didMove(to view: SKView) {
        backgroundColor = SKColor(red: 0.13, green: 0.16, blue: 0.24, alpha: 1)
        rebuild()
    }

    override func didChangeSize(_ oldSize: CGSize) {
        guard scene?.view != nil else { return }
        rebuild()
    }

    private func rebuild() {
        root.removeFromParent()
        root.removeAllChildren()
        cardNodes.removeAll()
        addChild(root)
        root.position = CGPoint(x: size.width / 2, y: size.height / 2)

        let title = SKLabelNode(fontNamed: "AvenirNext-Heavy")
        title.text = "NOBLE STARS"
        title.fontSize = 52
        title.fontColor = SKColor(red: 1.0, green: 0.85, blue: 0.25, alpha: 1)
        title.position = CGPoint(x: 0, y: size.height * 0.28)
        root.addChild(title)

        let subtitle = SKLabelNode(fontNamed: "AvenirNext-Medium")
        subtitle.text = "SHOWDOWN — last star standing"
        subtitle.fontSize = 17
        subtitle.fontColor = SKColor(white: 1, alpha: 0.65)
        subtitle.position = CGPoint(x: 0, y: size.height * 0.28 - 32)
        root.addChild(subtitle)

        // Character cards.
        let cardSize = CGSize(width: 190, height: 186)
        let gap: CGFloat = 22
        let totalWidth = cardSize.width * CGFloat(FighterKit.all.count) + gap * CGFloat(FighterKit.all.count - 1)

        for (index, kit) in FighterKit.all.enumerated() {
            let card = SKShapeNode(rectOf: cardSize, cornerRadius: 14)
            card.fillColor = SKColor(white: 1, alpha: 0.08)
            card.name = "card_\(index)"
            card.position = CGPoint(
                x: -totalWidth / 2 + cardSize.width / 2 + CGFloat(index) * (cardSize.width + gap),
                y: -26
            )
            root.addChild(card)
            cardNodes.append(card)

            let portrait = SKSpriteNode(imageNamed: kit.portraitImage)
            portrait.size = CGSize(width: 84, height: 98)
            portrait.position = CGPoint(x: 0, y: 38)
            portrait.name = card.name
            card.addChild(portrait)

            let name = SKLabelNode(fontNamed: "AvenirNext-Bold")
            name.text = kit.name
            name.fontSize = 22
            name.fontColor = .white
            name.position = CGPoint(x: 0, y: -32)
            name.name = card.name
            card.addChild(name)

            // Blurb wraps onto two lines around the "·" separator.
            let parts = kit.blurb.split(separator: "·").map {
                $0.trimmingCharacters(in: .whitespaces)
            }
            for (line, text) in parts.enumerated() {
                let blurb = SKLabelNode(fontNamed: "AvenirNext-Medium")
                blurb.text = text
                blurb.fontSize = 11.5
                blurb.fontColor = SKColor(white: 1, alpha: 0.7)
                blurb.position = CGPoint(x: 0, y: -56 - CGFloat(line) * 15)
                blurb.name = card.name
                card.addChild(blurb)
            }
        }

        let play = SKShapeNode(rectOf: CGSize(width: 220, height: 56), cornerRadius: 28)
        play.fillColor = SKColor(red: 1.0, green: 0.75, blue: 0.1, alpha: 1)
        play.strokeColor = .clear
        play.name = "play"
        play.position = CGPoint(x: 0, y: -size.height * 0.30)
        root.addChild(play)

        let playLabel = SKLabelNode(fontNamed: "AvenirNext-Heavy")
        playLabel.text = "PLAY"
        playLabel.fontSize = 26
        playLabel.fontColor = SKColor(red: 0.2, green: 0.12, blue: 0, alpha: 1)
        playLabel.verticalAlignmentMode = .center
        playLabel.name = "play"
        play.addChild(playLabel)

        updateSelection()
    }

    private func updateSelection() {
        for (index, card) in cardNodes.enumerated() {
            let selected = index == selectedIndex
            card.strokeColor = selected
                ? SKColor(red: 1.0, green: 0.85, blue: 0.25, alpha: 1)
                : SKColor(white: 1, alpha: 0.2)
            card.lineWidth = selected ? 4 : 1.5
            card.fillColor = SKColor(white: 1, alpha: selected ? 0.16 : 0.08)
        }
    }

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let touch = touches.first else { return }
        let tapped = nodes(at: touch.location(in: self))

        for node in tapped {
            guard let name = node.name else { continue }
            if name == "play" {
                startGame()
                return
            }
            if name.hasPrefix("card_"), let index = Int(name.dropFirst(5)) {
                selectedIndex = index
                updateSelection()
                return
            }
        }
    }

    private func startGame() {
        let game = GameScene(size: size)
        game.scaleMode = scaleMode
        game.playerKit = FighterKit.all[selectedIndex]
        view?.presentScene(game, transition: .fade(withDuration: 0.4))
    }
}
