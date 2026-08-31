# Noble Stars

Brawl Stars–inspired top-down 2.5D arena battler for iOS. SpriteKit + SwiftUI shell, Swift, no external dependencies. Landscape-only, iPhone-only (iPadOS 26 has orientation-lock regressions). Plan and milestones: `~/.claude/plans/hello-i-would-like-stateless-kurzweil.md`.

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
- **Automated play-testing without touch input**: launch with `SIMCTL_CHILD_NS_AUTOWALK="dx,dy"` to drive the player at a constant joystick vector (see `autoWalkInput` in GameScene.swift).
- zsh does not glob-expand unquoted variables — resolve the DerivedData app path with `find`, not a wildcard in a variable.

## Architecture notes

- Arena maps are ASCII grids in `ArenaMap.swift` (`#` wall, `b` bush, `~` water, `S` spawn, `X` loot box). Row 0 is the top of the map; world coords are SpriteKit y-up.
- 2.5D depth: y-sorted `zPosition` via `ZLayer.ySorted(baselineY:mapPixelHeight:)`; a node's position is its feet/baseline.
- Physics category bitmasks live in `Constants.swift` (`PhysicsCategory`).
