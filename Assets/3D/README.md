# 3D Assets

Source 3D models for the Godot 4 3D port in `godot/`. These are **authoring-side source
assets**, not shipped app resources.

> **Why this lives outside `NobleStars/`:** `project.yml` declares `sources: - NobleStars`,
> so anything under that directory is picked up by XcodeGen and compiled into the app
> bundle. Keeping raw models here means multi-megabyte works-in-progress don't inflate the
> build until a model is actually wired into the game.

## Layout

- `./` — static source meshes, as the generator produced them
- `Animation/` — rigged models with skeletons and animation clips ([README](Animation/README.md))

## Inventory

| File | Source | Tris | Verts | Rigged | Size |
|---|---|---|---|---|---|
| `tennis_brawler.glb` | Meshy AI (image-to-3D + texture), 2026-08-31 | 21,003 | 19,419 | No | 13.8 MB |
| `Animation/tennis_brawler_animated.glb` | Meshy AI (merged animations), 2026-08-31 | ~21,000 | 19,628 | Yes, 24 joints | 12.0 MB |

## `tennis_brawler.glb`

Stylized tennis-player character — navy tee, blue racket, sneakers. Fits the existing
tennis kit in `NobleStars/Resources/Sprites/` (`weapon_racket.png`, `ball_tennis.png`).

- glTF 2.0 binary, exported through Blender glTF I/O v4.3.47
- Single mesh (`Mesh0`), single double-sided PBR material
- Vertex attributes: `POSITION`, `NORMAL`, `TEXCOORD_0` — no tangents, no vertex colors
- Y-up, roughly unit-scaled: bounds ~1.18 × 1.90 × 0.83, so ~1.9 units tall. Treat 1 unit
  as 1 metre when importing and it lands at human scale with no extra scaling.
- Two embedded 2048×2048 PNG textures: `Baked_BaseColor`, `Baked_MetallicRoughness`

### Known issues before this is game-ready

- **Not rigged.** There is no armature, no skin, and no animations — this is a static mesh
  in a T/A-pose. **A rigged version of this same character now exists** at
  `Animation/tennis_brawler_animated.glb` — use that one to drive a fighter. This file is
  kept as the unmodified original generator output.
- **The metallic-roughness map is ~8 MB of nearly nothing.** It is essentially uniform —
  metallic 0, roughness high across the whole atlas. Dropping the texture and setting
  `metallicFactor` / `roughnessFactor` scalars on the material instead cuts the file by
  more than half with no visible change.
- **Baked-texture artifacts.** Meshy's image-to-3D bakes lighting into the base colour and
  leaves seam bleed along UV island edges. Expect to touch up or re-bake for a clean look.

### Swapping it in for a fighter capsule

> Prefer `Animation/tennis_brawler_animated.glb` for this — it is rigged, and its origin
> sits at the feet rather than the centre, so the numbers below do **not** carry over.

`godot/scripts/fighter.gd` currently builds each fighter from a `CapsuleMesh` (radius 0.45,
height 1.6) parented at `position.y = 0.8`, with a sphere "nose" showing facing. To try this
model in its place:

1. Copy the file into `godot/assets/` and let Godot generate the `.import` sidecar on scan
   (`--headless --import`), same as `Fox.glb`. Import as **Scene**.
2. Scale it to **0.84** — the mesh is 1.90 units tall, and 1.6 / 1.90 ≈ 0.84 matches the
   capsule it replaces.
3. Offset it to **y = 0.8**. The GLB origin sits at the model's centre (bounds run
   -0.95 to +0.95 on Y), not at its feet, so at 0.84 scale a 0.8 lift puts the soles on the
   floor — which is the capsule's existing offset, so `_body_mesh.position.y` stays as is.
4. Kit colour is applied to the capsule's material. This model carries its own baked base
   colour, so per-kit tinting needs a different approach — a modulate/overlay pass, or one
   retextured model per kit.

## Conventions

- Lowercase `snake_case` filenames, matching `NobleStars/Resources/Sprites/`
- Keep the original generator output committed unmodified; derived or optimized versions
  get a suffix (e.g. `tennis_brawler_animated.glb`, `tennis_brawler_lod0.glb`)
- Record provenance and generation date in the inventory table above

## A note on repository size

These files are committed directly, not through Git LFS. The largest is 13.8 MB,
comfortably under GitHub's 100 MB per-file limit, but binaries are stored whole per
revision — re-committing a changed model keeps every previous copy in history forever. If
this folder grows to many models or models start getting revised in place, move it to Git
LFS before that history gets expensive rather than after.
