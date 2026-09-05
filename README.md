# Noble Stars ⭐

A Brawl Stars–inspired top-down arena battler for iOS, built in Godot 4 — nine
fighters based on real people, played against bots or against your friends over
wifi in the same room.

Two modes are playable:

- **Showdown** — solo battle royale, ten fighters, a tile arena with destructible
  cover, hiding bushes and a closing gas ring.
- **Nobles Cup** — 3v3 on the Lower Field, first to two goals. Carry the ball and
  you can only kick; a tie at full time goes to overtime with every wall levelled.

## Requirements

- [Godot 4.7](https://godotengine.org) (developed against 4.7.2)
- Xcode 16+ for the iOS build (developed against Xcode 26)

## Running it

```sh
/Applications/Godot.app/Contents/MacOS/Godot --path godot
```

A fresh clone must import once (~5s) before the project will open — `godot/.godot/`
is gitignored. Run **one** Godot at a time on this project; two contend on the
import lock badly enough to look like a hang.

Desktop controls are WASD to move, Space to auto-aim and fire, E for Super. On a
phone it's twin floating touch sticks — move on the left half, aim on the right,
release to fire or tap to auto-aim.

## Project layout

- `godot/scripts/` — the game. `main.gd` is the match hub; `fighter.gd`,
  `arena.gd`, `bot_brain.gd`, `kits.gd` (all character stats), `cup_mode.gd` +
  `ball.gd` for Nobles Cup.
- `godot/scripts/menu/` — the menu (see below).
- `godot/data/{brawlers,game}.json` — copy and config only. **Stats come from
  `kits.gd`, never from the JSON.**
- `Assets/3D` — source Meshy character models, cleaned by `Tools/fix_meshy_glb.py`
  before they're wired into a kit.
- `Tools/` — `export_ios.sh` (iOS export), `fix_meshy_glb.py` (model pipeline),
  `gen_showdown_map.py` (regenerates the Showdown arena).

Almost nothing here ships as an art file. The floor, walls and water are fragment
shaders over flat colour; the hit sparks and shockwaves are rebuilt per frame from
vertex colours; all 28 combat sounds are synthesized at runtime. A fixed steep
camera only ever shows one angle, so the look is cheaper to compute than to author.

## The menu

A game programme's roster page rather than a mobile-game lobby: the selected
fighter stands on the arena's own ground fading to ink, with their stat column and
ability write-ups filling the flanks, and ROSTER / SEASON / SHOP / WIFI along the
bottom. Five screens, flat blocks and hairline rules, two fonts and no chrome art.

## iOS

```sh
Tools/export_ios.sh          # writes build/ios/noblestars3d.xcodeproj
```

Then open that project in Xcode, set your team under Signing & Capabilities, and
run it on a connected device. **Simulator builds are blocked upstream**
([godotengine/godot#118161](https://github.com/godotengine/godot/issues/118161)) —
the shipped simulator library is x86_64-only and Xcode 26 has no Rosetta
simulators, so test on real hardware.

## Development

This game is being built with [Claude Code](https://claude.com/claude-code). See
`CLAUDE.md` for the agent-facing build notes — it carries the gotchas, the debug
env hooks that are the testing strategy, and the reasoning behind the decisions
above.
