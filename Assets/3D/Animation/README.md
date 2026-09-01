# 3D Model Animation

Rigged and animated source models. Unlike the static meshes in the parent folder, these
carry an armature, skin weights, and animation clips — the form the Godot port needs to
actually drive a fighter.

Files here are the **game-ready cleaned versions**: every Meshy export is run through
[`Tools/fix_meshy_glb.py`](../../../Tools/fix_meshy_glb.py) before committing, which
repairs the export defects listed below and synthesizes the idle clip Meshy doesn't
produce. The raw Meshy export of the tennis brawler is preserved in git history
(commit `84dc0da`).

## Inventory

| File | Character | Source | Rig | Clips | Tris | Size |
|---|---|---|---|---|---|---|
| `tennis_brawler_animated.glb` | Tony | Meshy AI (merged animations), 2026-08-31, cleaned | 24-joint humanoid | 5 | ~21,000 | 7.0 MB |
| `paddle_brawler_animated.glb` | Henry | Meshy AI (merged animations), 2026-08-31, cleaned | 24-joint humanoid | 6 | ~8,300 | 17.5 MB |
| `staff_brawler_animated.glb` | Sanjit | Meshy AI (merged animations), 2026-08-31, cleaned + staff split | 24-joint humanoid | 8 | ~7,300 | 9.9 MB |
| `stomp_brawler_animated.glb` | Kovacs | Meshy AI (merged animations), 2026-08-31, cleaned | 24-joint humanoid | 6 | ~8,300 | 17.9 MB |
| `signal_brawler_animated.glb` | Leon | Meshy AI (merged animations), 2026-09-01, cleaned | 24-joint humanoid | 6 | ~8,200 | 20.8 MB |

All five are wired into the game: copied to `godot/assets/<kit>.glb` and declared in
`godot/scripts/kits.gd` (`model` + `clips`).

## `signal_brawler_animated.glb` (Leon)

Gamer kid holding a controller in his left hand. Ships with two mage-cast clips (Meshy's
own `mage_soell_cast_*` naming, typo included — the kit references them verbatim):

- **Attack** (`mage_soell_cast_3` at 4×, `attack_seek: 0.6`): the palm-thrust release
  frame sits at t≈0.90 s, so seeking to 0.6 puts it ~0.075 s after cast. Fires four
  labeled A/B/X/Y button shots (`Style.LANES`) in wide parallel lanes, each with an
  independent side-to-side sine drift. The aim indicator draws a corridor, not a cone.
- **Super — Disconnect** (`mage_soell_cast_2` at 3×, `super_seek: 0.75`): overhead slam
  release at t≈1.28 s. Fires a slow glitch signal (`Style.SIGNAL`) — dark prism core with
  cyan/magenta RGB-split ghosts jittering around it — that detonates on contact or at max
  range: area damage plus a **silence** (`weapon.silence`, 2.4 s) that blocks attacking
  but not moving. Silenced fighters show flickering glitch bars overhead; no ammo or
  Super charge is spent while silenced. `attack_seek` joins `super_seek` in the clip
  contract (seek works for both slots now).

## `stomp_brawler_animated.glb` (Kovacs)

Bulky brawler with no weapon — every attack is a radial ground wave
(`Style.SHOCKWAVE` in `kits.gd`): full damage point blank, fading linearly to the rim,
knockback outward. `weapon.delay` holds the damage burst until the animation's impact
frame, both timed from the clip data:

- **Stomp** (`Angry_Ground_Stomp_2`, 1.8 s): the raised foot slams down at t≈0.68 s —
  at 3× playback the burst fires 0.23 s after cast.
- **Super** (`Backflip_and_Rise`, 2.7 s): airborne flip, crashes flat to the ground at
  t≈1.30 s (hips drop to 0.10) — at 2.5× the big wave erupts 0.52 s after cast, then he
  rises during the recovery tail.

The aim indicator needed no changes: `spread_deg: 360` makes the existing cone renderer
draw a full circle at wave radius. The `Idle` is synthesized as usual (export shipped
run/walk cycles only).

## `staff_brawler_animated.glb` (Sanjit)

Chibi martial artist with a headband who carries his bo staff at his hip — the staff is
skinned to `RightHand` and held perpendicular to the grip, so it rides horizontally beside
him at idle and follows the hand through the attack clips. ~7,300 tris, one 2048×2048
atlas. The richest clip set of the three:

| Clip | Length | Note |
|---|---|---|
| `Idle` | 4.00 s | Synthesized by the tool (export shipped none) |
| `Running` / `RunFast` / `Walking` | 0.63 / 0.47 / 1.03 s | |
| `Double_Combo_Attack` | 2.83 s | The plans.md "double punch" primary — sped up like Tony's 3× Thrust_Slash when wired |
| `Attack` | 2.80 s | Generic strike, spare |
| `Axe_Spin_Attack` | 2.50 s | Spin attack, spare |
| `Crouch_Charge_and_Throw` | 7.70 s | Charge-up and throw — raw material for the boomeranging-staff Super |

Wired as: idle `Idle`, run `Running`, attack `Double_Combo_Attack` at 4.5×. The Super
plays the real throw — `clips.super` seeks `Crouch_Charge_and_Throw` to 5.2 s at 4×, so
the release (t≈5.6 s, found from the hand-speed peak in the clip data) lands ~0.1 s after
the boomerang spawns, then follow-through. Kits without a `super` clip keep their attack
clip for Supers, exactly as before.

**The staff is a separate `held_item` node** (`--split-held-item right` in the tool): 381
triangles split off `RightHand` into their own skinned mesh, so `fighter.gd` hides the
in-hand staff while the boomerang Super flies and `boomerang.gd` restores it on any end
of flight (catch, owner death, cleanup). Boundary triangles stay with the body, keeping
the fist sealed while empty.

## `tennis_brawler_animated.glb`

The rigged tennis character — same ~21k-tri mesh and baked atlas as the static
`../tennis_brawler.glb`, plus a skeleton and clips. Build fighters on this one.

- glTF 2.0 binary; single skinned mesh (`char1`) under one `Armature` root
- Vertex attributes: `POSITION`, `NORMAL`, `TEXCOORD_0`, `JOINTS_0`, `WEIGHTS_0`
- **Feet at the origin** — bounds y 0 to 1.69, so it stands on y = 0 with no offset.
  (The static model differs: it is centred on the origin. Don't reuse numbers across them.)
- **Faces −Z**, Godot's forward, after cleanup (Meshy exports face +Z)
- The tennis racket is skinned to `RightHand` (~10k of the verts — the string lattice is
  dense), so it follows the swing in every clip
- One 2048×2048 base-colour atlas; material is opaque, lit, `roughnessFactor` 0.41

### Animation clips

| Clip | Length | Loops | Notes |
|---|---|---|---|
| `Idle` | 4.00 s | Yes | Synthesized standing idle — see below |
| `Walking` | 1.03 s | Yes | |
| `Running` | 0.63 s | Yes | |
| `Run_03` | 0.80 s | Yes | Second run cycle, near-duplicate of `Running` — pick one |
| `Thrust_Slash` | 3.00 s | No | Attack. Long for a game action; trim or speed up playback to match attack cadence |

The `Idle` clip is generated by the fix tool, not Meshy: it starts from the rest pose (the
only genuinely standing pose in the export — feet level, legs straight), relaxes the stiff
A-pose arms so each hand hangs ~4 cm outside its thigh (solved per arm — the rig is
asymmetric, one shoulder sits 6 cm further out than the other), and layers a subtle
breath cycle (~10 mm head bob, slight shoulder sway, hips settle). It drives all 24 bones
like the other clips, loops seamlessly (zero first/last-frame delta), and was verified
free of mesh interpenetration — the racket hangs beside the leg with 13 cm of ground
clearance.

## `paddle_brawler_animated.glb` (Henry)

Chibi kid with an afro who carries his paddle **slung on his back** — hands are empty
(hand vertex counts are symmetric; unlike Tony there is no held weapon). ~8.3k tris,
one 4096×4096 atlas. Shipped as a strict T-pose with only run/walk cycles
(`Running`, `Walking`, `run_fast_3` — the latter two are unused by the game wiring),
**no idle and no attack**, so the tool synthesized both:

- `Idle` (4 s loop) — same recipe as Tony's, solved from this rig's own geometry
- `Attack_Sweep` (0.55 s) — a right-handed horizontal melee sweep: windup pulling the
  arm back with a torso counter-twist, an accelerating strike across the front,
  follow-through, and a settle onto the exact pose Idle starts from. Sweeps bare-handed,
  matching the model's back-mounted-paddle design. Wired as Henry's attack at 1× speed.

This model also exposed a new Meshy auto-rig defect the tool now fixes: the back-slung
paddle had picked up `LeftArm` skin weights, so it swung out horizontally the moment the
arm left the T-pose. The tool re-anchors arm-dominated vertices that sit further from the
arm bone than a sleeve can reach (9.2% of model height) onto the nearest spine bone —
121 weight slots here. Hand bones are exempt, so Tony's racket keeps following his hand.

### What the cleanup fixed (all Meshy export defects)

Recorded so the next model's diff makes sense — `Tools/fix_meshy_glb.py` does all of this:

1. `alphaMode` BLEND on an opaque character → opaque (kills transparency-sorting flicker
   against the gas volume)
2. Base-colour atlas duplicated into `emissiveTexture` at factor [1,1,1] — the character
   self-illuminated and ignored scene lighting → emissive cleared
3. `KHR_materials_specular` at 2.0, past the valid 0–1 range → extension removed
4. `metallicFactor` left at the glTF default of 1.0 — full metal renders black in a scene
   without reflection probes → forced to 0 (the runtime clamp in `fighter.gd` remains as
   belt-and-braces)
5. The same atlas embedded twice (base colour + emissive copy) → duplicate dropped,
   buffer repacked: **12.6 → 7.0 MB** (Tony), **34.0 → 17.5 MB** (Henry)
6. Torso-mounted gear weighted to arm bones → re-anchored to the spine (see above)
7. Faced +Z → armature yawed 180° to face −Z
8. No idle clip → synthesized; no attack clip → synthesized

### Adding the next character

`godot/scripts/fighter.gd` already instantiates a kit's GLB when `kits.gd` declares
`model` + `clips` (Tony and Henry are wired; Nova still uses the capsule). For a new
Meshy export:

1. `python3 Tools/fix_meshy_glb.py <export.glb> -o Assets/3D/Animation/<name>_animated.glb`
2. Read the tool's log — it says what it repaired and which clips it synthesized.
3. Copy to `godot/assets/<kit>.glb`, run the import scan (`--headless --import`).
4. Declare in `kits.gd`: `"model": "res://assets/<kit>.glb"` and
   `"clips": {"idle": ..., "run": ..., "attack": ..., "attack_speed": ...}` — plus
   optional `super`/`super_speed`/`super_seek` for a Super-specific clip, and
   `--split-held-item left|right` at tool time if the character's weapon should leave
   their hand while a thrown Super is in the air.

Cleaned models stand on y = 0 facing −Z at ~1.65–1.69 units tall, so they drop into the
fighter scene with no offset, rotation, or rescale. The capsule `CollisionShape3D` stays —
only the visual is replaced.

**Kit colour still needs rethinking.** `_material.albedo_color = kit.color` tints the
placeholder capsule. Models carry baked atlases, so per-kit identity needs an
overlay/modulate pass or one retextured model per kit.
