# Noble Stars ⭐

A Brawl Stars–inspired top-down 2.5D arena battler for iOS, built with SpriteKit and Swift — no external dependencies, no game engine, all code.

Current mode: **Showdown** — a solo battle royale against AI bots on a tile-based arena with destructible cover, hiding bushes, and a closing poison gas ring. (Work in progress.)

## Requirements

- Xcode 16+ (developed against Xcode 26)
- [XcodeGen](https://github.com/yonaskolb/XcodeGen) (`brew install xcodegen`)

## Building

The Xcode project is generated — don't edit `NobleStars.xcodeproj` directly:

```sh
xcodegen generate
open NobleStars.xcodeproj   # build & run the NobleStars scheme on an iOS Simulator
```

Or from the command line:

```sh
xcodebuild -project NobleStars.xcodeproj -scheme NobleStars \
  -destination 'platform=iOS Simulator,name=iPhone 17' build
```

## Project layout

- `project.yml` — XcodeGen spec (source of truth for the Xcode project)
- `NobleStars/App` — SwiftUI shell hosting the SpriteKit scene
- `NobleStars/Game` — all gameplay: arena, entities, input, systems
- Arena maps are ASCII grids in `Game/Arena/ArenaMap.swift` (`#` wall, `b` bush, `~` water, `S` spawn, `X` loot box)
- `Assets/3D` — source 3D models for the in-progress 3D direction (not bundled into the app)

## The menu

The menu is native Godot, in `godot/scripts/menu/` — a Brawl Stars-style home
(auditorium stage with the selected brawler idling live in 3D, brawlers grid and
detail, shop with Star Drops, Nobles Pass, modes, matchmaking, news, friends,
club chat, inbox). It is the only menu: the HTML build it was rebuilt from has
been removed, because a browser page cannot ship inside the iOS app.

Art lives in `godot/assets/menu/` (background, buttons, icons, svg, portraits,
cards, treats, decor, fonts) and copy/config in `godot/data/{brawlers,game}.json`.
Stats come from `kits.gd`, never from the JSON.

```sh
/Applications/Godot.app/Contents/MacOS/Godot --path godot
```

Solo Showdown is wired through today. The other events remain previews until
their game modes are implemented.

## Development

This game is being built with [Claude Code](https://claude.com/claude-code). See `CLAUDE.md` for the agent-facing build notes.
