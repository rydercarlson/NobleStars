# 3D Model Animation

Rigged and animated source models. Unlike the static meshes in the parent folder, these
carry an armature, skin weights, and animation clips — the form the Godot port needs to
actually drive a fighter.

## Inventory

| File | Source | Rig | Clips | Tris | Size |
|---|---|---|---|---|---|
| `tennis_brawler_animated.glb` | Meshy AI (merged animations), 2026-08-31 | 24-joint humanoid | 4 | ~21,000 | 12.0 MB |

## `tennis_brawler_animated.glb`

The rigged counterpart to `../tennis_brawler.glb` — same tennis character, same ~21k-tri
mesh and baked texture atlas, re-exported with a skeleton and clips. This is the version
to build a fighter on; the static one is kept as the original generator output.

- glTF 2.0 binary, exported through Blender glTF I/O v4.2.57
- Single skinned mesh (`char1`) under one `Armature` root node
- Vertex attributes: `POSITION`, `NORMAL`, `TEXCOORD_0`, `JOINTS_0`, `WEIGHTS_0`
- **Feet sit at the origin** — bounds run y = -0.003 to 1.690, so the model is 1.69 units
  tall and stands on y = 0 with no offset. (The static model differs: it is centred on the
  origin, so it needs lifting. Don't reuse those numbers here.)

### Animation clips

| Clip | Length | Notes |
|---|---|---|
| `Walking` | 1.03 s | Loops |
| `Running` | 0.63 s | Loops |
| `Run_03` | 0.80 s | A second run cycle — near-duplicate of `Running`, pick one |
| `Thrust_Slash` | 3.00 s | Attack. Long for a game action; likely needs trimming or a faster playback rate to match attack cadence |

**There is no idle clip.** A fighter standing still has nothing to play, so an idle needs to
be generated or authored before this fully replaces the capsule.

### Material problems to fix on import

Meshy's export wires the material in a way that will look wrong in Godot. All four are
fixable in the import dock or with a material override — no re-export needed:

1. **`alphaMode` is `BLEND`** on a fully opaque character. Transparency sorting will make it
   flicker against the gas volume and other transparent geometry. Set it to opaque.
2. **The base colour texture is also plugged into `emissiveTexture` at `emissiveFactor`
   [1, 1, 1].** The character self-illuminates at full albedo, so it ignores scene lighting
   entirely and reads flat and blown out. Clear the emissive.
3. **`KHR_materials_specular` sets `specularColorFactor` to [2, 2, 2]** — double the valid
   0–1 range, adding to the washed-out look.
4. **The two embedded 2048×2048 textures are visually identical.** The same atlas is stored
   twice, once for base colour and once for emissive — about 5.6 MB of the 12 MB file. Once
   the emissive is cleared, that copy can be dropped.

### Swapping it in for a fighter capsule

`godot/scripts/fighter.gd` builds each fighter from a `CapsuleMesh` (radius 0.45, height
1.6) at `position.y = 0.8`, plus a sphere "nose" marking facing. To use this model instead:

- Add the imported scene as a child at **`position.y = 0`** — feet are already at the
  model's origin, so it needs no lift. Scale **0.947** matches the capsule's 1.6 height
  exactly, or leave it at 1.0 for a slightly taller fighter.
- **Leave the `CollisionShape3D` alone.** The capsule collider and its 0.8 offset are the
  physics body; only the visual mesh is being replaced.
- **Drop the nose sphere** — a rigged character reads its own facing.
- **Kit colour needs rethinking.** `_material.albedo_color = kit.color` tints a plain
  capsule. This model carries a baked atlas, so per-kit identity needs an overlay/modulate
  pass or one retextured model per kit.
