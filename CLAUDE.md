# Noble Stars

Brawl Stars–inspired top-down 2.5D arena battler for iOS. SpriteKit + SwiftUI shell, Swift, no external dependencies. Landscape-only, iPhone-only (iPadOS 26 has orientation-lock regressions). Plan and milestones: `~/.claude/plans/hello-i-would-like-stateless-kurzweil.md`.

## Godot 3D port (`godot/`)

The long-term direction is a 3D rebuild in Godot 4 using Meshy-generated GLB characters; the SpriteKit game above is v1 and stays working. Run the 3D game: `/Applications/Godot.app/Contents/MacOS/Godot --path godot` (add `--headless --import` after adding files). Debug env hooks mirror the 2D ones: `NS3_KIT=nova|tony|henry`, `NS3_AUTOFIRE=<sec>`, `NS3_AUTOWALK="x,z"`, `NS3_GODMODE=1`, and `NS3_SHOTS="prefix:t1,t2,..."` (saves screenshots at those match times, then quits — the verification loop). Desktop controls: WASD move, left-click aimed fire, Space auto-aim, E Super, R restart. All scenes are built in code; `.tscn` files stay minimal. GDScript gotcha: `:=` cannot infer types from ternary expressions — annotate (`var t: float = ...`). Character models come from Meshy as GLB — always run `python3 Tools/fix_meshy_glb.py <file.glb>` on a fresh export before committing (fixes broken material export, +Z facing, and adds the missing Idle clip); cleaned models live in `Assets/3D/` (see its README).

## Build & run

Full Xcode lives at /Applications/Xcode.app but `xcode-select` points at CommandLineTools — always prefix builds with `DEVELOPER_DIR`:

```sh
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
xcodegen generate          # only needed after adding/removing files or editing project.yml
xcodebuild -project NobleStars.xcodeproj -scheme NobleStars \
  -destination 'platform=iOS Simulator,name=iPhone 17' build
APP=$(find ~/Library/Developer/Xcode/DerivedData -maxdepth 5 -name "NobleStars.app" -path "*Debug-iphonesimulator*" | head -1)
xcrun simctl install <UDID> "$APP" && xcrun simctl launch <UDID> com.ryder.noblestars
```

The Xcode project is generated — never edit `NobleStars.xcodeproj` by hand; edit `project.yml` and re-run `xcodegen generate`. New source files under `NobleStars/` are picked up automatically on regen.

## Gotchas

- **Simulator screenshots are captured in portrait framebuffer orientation.** The app runs landscape, so `xcrun simctl io <UDID> screenshot x.png` needs `sips --rotate 270 x.png --out x_r.png` before viewing. Don't mistake the raw portrait capture for a broken orientation lock (top-down game art looks plausible at any rotation — check that wall front-faces are BELOW their top faces).
- **Automated play-testing without touch input** (env vars via `SIMCTL_CHILD_` prefix on `simctl launch`): `NS_AUTOWALK="dx,dy"` drives the player at a constant joystick vector; `NS_AUTOFIRE="seconds"` auto-aim fires on that interval (fires the Super when charged); `NS_GODMODE=1` makes the player invulnerable; `NS_DEBUG_HUD=1` shows a live stats readout; `NS_KIT=nova|tony|henry` picks the player's character. Any of NS_KIT/NS_AUTOFIRE/NS_AUTOWALK skips the main menu and jumps straight into a match. All in GameScene.swift / GameView.swift.
- The simulator can shut down between Bash invocations when Simulator.app isn't open — `open -a Simulator` keeps it alive, or re-boot with `xcrun simctl boot <UDID>`.
- zsh does not glob-expand unquoted variables — resolve the DerivedData app path with `find`, not a wildcard in a variable.

## Architecture notes

- Arena maps are ASCII grids in `ArenaMap.swift` (`#` wall, `b` bush, `~` water, `S` spawn, `X` loot box). Row 0 is the top of the map; world coords are SpriteKit y-up.
- 2.5D depth: y-sorted `zPosition` via `ZLayer.ySorted(baselineY:mapPixelHeight:)`; a node's position is its feet/baseline.
- Physics category bitmasks live in `Constants.swift` (`PhysicsCategory`).
