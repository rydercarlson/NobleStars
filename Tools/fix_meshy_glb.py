#!/usr/bin/env python3
"""Clean up a Meshy AI character export for the Godot port.

Meshy's GLB exports share a set of defects that make them render and behave
wrong in Godot. This fixes them in place and synthesizes the idle clip Meshy
does not produce:

  1. alphaMode BLEND on an opaque character -> transparency sorting artifacts
  2. base colour atlas wired into emissiveTexture at full strength -> the
     character self-illuminates and ignores scene lighting
  3. KHR_materials_specular specularColorFactor pushed past the valid 0-1 range
  4. metallicFactor left at the glTF default of 1.0 -- full metal renders
     black in a scene without reflection probes
  5. the same atlas embedded twice (base colour + emissive)
  6. a metallic-roughness texture that is uniform -- megabytes encoding two
     numbers, replaced with metallicFactor/roughnessFactor scalars
  7. auto-rig weight bleed: gear slung on the torso (a back-mounted paddle,
     a strap) picks up upper-arm weights and swings out when the arm moves --
     re-anchored to the nearest spine bone. Hand weights are never touched,
     so held weapons keep following the hand.
  8. model faces +Z, but Godot forward -- and fighter.gd's facing nose -- is -Z
  9. no idle animation, so a standing fighter has nothing to play; and no
     attack clip, so kits.gd has nothing to wire. Both are synthesized from
     the rest pose for rigged models that lack them.

Usage:  python3 Tools/fix_meshy_glb.py <in.glb> [-o <out.glb>] [--no-idle]
        [--no-attack]

No third-party dependencies beyond numpy.
"""
import argparse, json, os, struct, sys
import numpy as np

# ---------- container ----------

def load(path):
    with open(path, 'rb') as f:
        magic, ver, _ = struct.unpack('<4sII', f.read(12))
        if magic != b'glTF':
            sys.exit(f"{path}: not a GLB")
        chunks, total = {}, os.path.getsize(path)
        while f.tell() < total:
            clen, ctype = struct.unpack('<I4s', f.read(8))
            chunks[ctype.strip(b'\x00').decode()] = f.read(clen)
    return json.loads(chunks['JSON']), bytearray(chunks['BIN'])


def save(path, j, blob):
    js = json.dumps(j, separators=(',', ':')).encode()
    js += b' ' * ((4 - len(js) % 4) % 4)
    bn = bytes(blob) + b'\x00' * ((4 - len(blob) % 4) % 4)
    with open(path, 'wb') as f:
        f.write(struct.pack('<4sII', b'glTF', 2, 12 + 8 + len(js) + 8 + len(bn)))
        f.write(struct.pack('<I4s', len(js), b'JSON')); f.write(js)
        f.write(struct.pack('<I4s', len(bn), b'BIN\x00')); f.write(bn)


CT = {5120: 'b', 5121: 'B', 5122: 'h', 5123: 'H', 5125: 'I', 5126: 'f'}
NC = {'SCALAR': 1, 'VEC2': 2, 'VEC3': 3, 'VEC4': 4, 'MAT4': 16}

# ---------- math ----------

def qmul(a, b):
    x1, y1, z1, w1 = a; x2, y2, z2, w2 = b
    return np.array([w1*x2 + x1*w2 + y1*z2 - z1*y2,
                     w1*y2 - x1*z2 + y1*w2 + z1*x2,
                     w1*z2 + x1*y2 - y1*x2 + z1*w2,
                     w1*w2 - x1*x2 - y1*y2 - z1*z2])


def qmat(q):
    x, y, z, w = q
    return np.array([[1-2*(y*y+z*z), 2*(x*y-z*w),   2*(x*z+y*w)],
                     [2*(x*y+z*w),   1-2*(x*x+z*z), 2*(y*z-x*w)],
                     [2*(x*z-y*w),   2*(y*z+x*w),   1-2*(x*x+y*y)]])


def axis_angle(axis, ang):
    axis = np.asarray(axis, float)
    axis = axis / np.linalg.norm(axis)
    return np.concatenate([axis * np.sin(ang / 2), [np.cos(ang / 2)]])


def between(v0, v1):
    """Minimal quaternion rotating unit vector v0 onto v1."""
    v0 = v0 / np.linalg.norm(v0); v1 = v1 / np.linalg.norm(v1)
    d = float(np.clip(np.dot(v0, v1), -1, 1))
    if d > 1 - 1e-9:
        return np.array([0., 0., 0., 1.])
    if d < -1 + 1e-9:
        axis = np.cross(v0, [1., 0, 0])
        if np.linalg.norm(axis) < 1e-6:
            axis = np.cross(v0, [0, 1., 0])
        return axis_angle(axis, np.pi)
    return axis_angle(np.cross(v0, v1), np.arccos(d))


def trs_mat(t, r, s):
    M = np.eye(4); M[:3, :3] = qmat(r) * np.asarray(s); M[:3, 3] = t
    return M


def node_trs(n):
    return (np.array(n.get('translation', [0, 0, 0]), float),
            np.array(n.get('rotation', [0, 0, 0, 1]), float),
            np.array(n.get('scale', [1, 1, 1]), float))

# ---------- fixes ----------

def drop_junk_clips(j, log):
    """Remove Meshy's export debris: the near-zero-length `clip0|baselayer`
    stub, and clips still named after a raw asset UUID. Godot addresses clips
    by name, so a duplicate name silently shadows its twin in the
    AnimationPlayer — these arrive in pairs, so they cannot all be kept.
    """
    import re as _re
    anims = j.get('animations', [])
    if not anims:
        return
    def duration(a):
        return max((j['accessors'][s['input']].get('max', [0])[0]
                    for s in a['samplers']), default=0)
    uuid_like = _re.compile(r'^[0-9a-f]{8}-[0-9a-f]{4}-', _re.I)
    kept, dropped = [], []
    for a in anims:
        nm = a.get('name', '')
        if duration(a) < 0.1 or 'baselayer' in nm or uuid_like.match(nm):
            dropped.append(f"{nm or '<unnamed>'} ({duration(a):.2f}s)")
        else:
            kept.append(a)
    # a name surviving twice would still shadow itself — keep the longer one
    seen = {}
    for a in list(kept):
        nm = a['name']
        if nm in seen:
            loser = a if duration(a) <= duration(seen[nm]) else seen[nm]
            kept.remove(loser)
            dropped.append(f"{nm} (duplicate name)")
            if loser is seen[nm]:
                seen[nm] = a
        else:
            seen[nm] = a
    if dropped:
        j['animations'] = kept
        log(f"dropped {len(dropped)} junk clip(s): " + ", ".join(dropped))


def fix_material(j, log):
    for m in j.get('materials', []):
        if m.pop('emissiveTexture', None) is not None:
            m['emissiveFactor'] = [0, 0, 0]
            log("cleared emissiveTexture (was self-illuminating at full albedo)")
        elif m.get('emissiveFactor') and any(m['emissiveFactor']):
            m['emissiveFactor'] = [0, 0, 0]; log("zeroed emissiveFactor")
        if m.get('alphaMode') == 'BLEND':
            del m['alphaMode']; log("alphaMode BLEND -> OPAQUE")
        ext = m.get('extensions', {})
        if ext.pop('KHR_materials_specular', None) is not None:
            log("removed KHR_materials_specular (specular pushed past 0-1)")
        pbr = m.setdefault('pbrMetallicRoughness', {})
        if 'metallicRoughnessTexture' not in pbr and pbr.get('metallicFactor', 1) > 0:
            pbr['metallicFactor'] = 0
            log("metallicFactor -> 0 (glTF defaults to 1.0 = full metal, "
                "which renders black without reflection probes)")
        if not ext:
            m.pop('extensions', None)
    still = {e for m in j.get('materials', []) for e in m.get('extensions', {})}
    for key in ('extensionsUsed', 'extensionsRequired'):
        if key in j:
            j[key] = [e for e in j[key] if not e.startswith('KHR_materials_') or e in still]
            if not j[key]:
                del j[key]


def png_mean_std(data):
    """Per-channel mean/std of a PNG, via PIL or macOS sips. None if neither works."""
    try:
        from PIL import Image
        import io
        px = np.asarray(Image.open(io.BytesIO(data)).convert('RGB'), float) / 255
        return px.reshape(-1, 3).mean(0), px.reshape(-1, 3).std(0)
    except ImportError:
        pass
    import subprocess, tempfile
    with tempfile.TemporaryDirectory() as td:
        src, bmp = os.path.join(td, 'i.png'), os.path.join(td, 'i.bmp')
        open(src, 'wb').write(data)
        r = subprocess.run(['sips', '-s', 'format', 'bmp', src, '--out', bmp],
                           capture_output=True)
        if r.returncode:
            return None, None
        raw = open(bmp, 'rb').read()
        off, w, h = struct.unpack_from('<I', raw, 10)[0], *struct.unpack_from('<ii', raw, 18)
        bpp = struct.unpack_from('<H', raw, 28)[0] // 8
        row = (w * bpp + 3) & ~3
        a = np.frombuffer(raw, np.uint8, abs(h) * row, off).reshape(abs(h), row)
        px = a[:, :w * bpp].reshape(abs(h), w, bpp)[..., :3][..., ::-1] / 255  # BGR->RGB
        return px.reshape(-1, 3).mean(0), px.reshape(-1, 3).std(0)


def flatten_uniform_mr(j, blob, log):
    """A near-uniform metallicRoughness texture is megabytes spent encoding two
    scalars; replace it with metallicFactor/roughnessFactor (G=rough, B=metal)."""
    for m in j.get('materials', []):
        pbr = m.get('pbrMetallicRoughness', {})
        mrt = pbr.get('metallicRoughnessTexture')
        if not mrt:
            continue
        img = j['images'][j['textures'][mrt['index']].get('source', 0)]
        if 'bufferView' not in img or img.get('mimeType') != 'image/png':
            continue
        bv = j['bufferViews'][img['bufferView']]
        off = bv.get('byteOffset', 0)
        mean, std = png_mean_std(bytes(blob[off:off + bv['byteLength']]))
        if mean is None:
            log("could not decode MR texture (no PIL, sips failed), leaving it")
            continue
        if max(std[1], std[2]) > 0.04:
            continue                                   # genuinely varying map
        del pbr['metallicRoughnessTexture']
        pbr['roughnessFactor'] = round(float(mean[1]) * pbr.get('roughnessFactor', 1), 4)
        pbr['metallicFactor'] = round(float(mean[2]) * pbr.get('metallicFactor', 1), 4)
        log(f"uniform MR texture -> roughnessFactor {pbr['roughnessFactor']}, "
            f"metallicFactor {pbr['metallicFactor']}")


def drop_unused_textures(j, log):
    used_tex = set()
    def scan(o):
        if isinstance(o, dict):
            if 'index' in o and set(o) <= {'index', 'texCoord', 'scale', 'strength'}:
                used_tex.add(o['index'])
            for v in o.values(): scan(v)
        elif isinstance(o, list):
            for v in o: scan(v)
    scan(j.get('materials', []))

    keep_tex = sorted(used_tex)
    if len(keep_tex) == len(j.get('textures', [])):
        return
    tex_map = {old: new for new, old in enumerate(keep_tex)}
    j['textures'] = [j['textures'][i] for i in keep_tex]

    keep_img = sorted({t['source'] for t in j['textures'] if 'source' in t})
    img_map = {old: new for new, old in enumerate(keep_img)}
    dropped = len(j.get('images', [])) - len(keep_img)
    j['images'] = [j['images'][i] for i in keep_img]
    for t in j['textures']:
        if 'source' in t: t['source'] = img_map[t['source']]

    def remap(o):
        if isinstance(o, dict):
            if 'index' in o and set(o) <= {'index', 'texCoord', 'scale', 'strength'}:
                o['index'] = tex_map[o['index']]
            for v in o.values(): remap(v)
        elif isinstance(o, list):
            for v in o: remap(v)
    remap(j.get('materials', []))
    if dropped:
        log(f"dropped {dropped} orphaned image(s) — the duplicated atlas")


def fix_stray_limb_weights(j, blob, log):
    """Re-anchor auto-rig weight bleed on the upper-arm bones.

    Meshy's auto-rig gives torso-mounted gear (a paddle slung on the back, a
    strap over the shoulder) weights on Arm/ForeArm bones, so it swings out
    sideways the moment the arm leaves the T-pose. Any vertex weighted to an
    upper-arm bone but further from that bone than a sleeve can reach (9.2%
    of model height -- calibrated so a clean mirrored sleeve stays untouched)
    has its arm-bone weight slots re-pointed at the nearest spine bone. Only
    vertices DOMINATED by the arm bone are touched: held weapons are
    hand-dominant (with intentional forearm blending) and hang far from the
    wrist on purpose, so they are left alone.
    """
    if not j.get('skins'):
        return
    names = [n.get('name') for n in j['nodes']]
    skin = j['skins'][0]
    jn = {names[x]: k for k, x in enumerate(skin['joints'])}
    need = ('LeftArm', 'LeftForeArm', 'LeftHand', 'RightArm', 'RightForeArm',
            'RightHand', 'Spine', 'Spine01', 'Spine02')
    if not all(b in jn for b in need):
        return

    def acc_array(ai):
        a = j['accessors'][ai]; bv = j['bufferViews'][a['bufferView']]
        off = bv.get('byteOffset', 0) + a.get('byteOffset', 0)
        dt = np.dtype('<' + CT[a['componentType']])
        n = NC[a['type']]
        arr = np.frombuffer(blob, dt, a['count'] * n, off).reshape(a['count'], n)
        return arr, off, dt

    ibm, _, _ = acc_array(skin['inverseBindMatrices'])
    ibm = np.asarray(ibm, np.float64).reshape(-1, 4, 4).transpose(0, 2, 1)
    bind = {k: np.linalg.inv(ibm[k])[:3, 3] for k in range(len(skin['joints']))}

    prim = j['meshes'][0]['primitives'][0]
    v, _, _ = acc_array(prim['attributes']['POSITION'])
    v = np.asarray(v, np.float64)
    jj, joff, jdt = acc_array(prim['attributes']['JOINTS_0'])
    jj = np.array(jj)                                   # writable copy
    ww, _, _ = acc_array(prim['attributes']['WEIGHTS_0'])
    height = v[:, 1].max() - v[:, 1].min()
    cut = 0.092 * height

    def seg_dist(p, a, b):
        ab = b - a
        t = np.clip(((p - a) @ ab) / (ab @ ab), 0, 1)
        return np.linalg.norm(p - (a + t[:, None] * ab), axis=1)

    spines = [jn[b] for b in ('Spine', 'Spine01', 'Spine02')]
    wwa = np.asarray(ww)
    dominant = jj[np.arange(len(jj)), wwa.argmax(1)]
    arm_bones = {jn[side + b] for side in ('Left', 'Right')
                 for b in ('Arm', 'ForeArm')}
    moved = 0
    for side in ('Left', 'Right'):
        for bone, nxt in ((side + 'Arm', side + 'ForeArm'),
                          (side + 'ForeArm', side + 'Hand')):
            k = jn[bone]
            d = seg_dist(v, bind[k], bind[jn[nxt]])
            stray = (dominant == k) & (d > cut)
            if not stray.any():
                continue
            for slot in range(jj.shape[1]):
                hit = stray & np.isin(jj[:, slot], list(arm_bones)) & (wwa[:, slot] > 0)
                if not hit.any():
                    continue
                sp = np.stack([np.linalg.norm(v[hit] - bind[si], axis=1)
                               for si in spines])
                jj[hit, slot] = np.array(spines, dtype=jj.dtype)[sp.argmin(0)]
                moved += int(hit.sum())
    if moved:
        blob[joff:joff + jj.nbytes] = np.ascontiguousarray(jj, jdt).tobytes()
        log(f"re-anchored {moved} stray limb weight slots to the spine "
            "(torso-mounted gear was riding the arm bones)")


def face_forward(j, log):
    """Meshy models face +Z; Godot forward is -Z. Yaw the armature 180."""
    names = [n.get('name') for n in j['nodes']]
    if 'headfront' not in names or 'Head' not in names:
        return
    parent = {c: i for i, n in enumerate(j['nodes']) for c in n.get('children', [])}
    roots = [i for i in range(len(j['nodes'])) if i not in parent]
    if not roots:
        return
    root = roots[0]

    W = {}
    def walk(i, M):
        t, r, s = node_trs(j['nodes'][i]); W[i] = M @ trs_mat(t, r, s)
        for c in j['nodes'][i].get('children', []): walk(c, W[i])
    walk(root, np.eye(4))
    fwd = W[names.index('headfront')][:3, 3] - W[names.index('Head')][:3, 3]
    if fwd[2] <= 0:                       # already faces -Z
        return
    t, r, s = node_trs(j['nodes'][root])
    j['nodes'][root]['rotation'] = [float(v) for v in qmul(axis_angle([0, 1, 0], np.pi), r)]
    j['nodes'][root]['translation'] = [float(v) for v in t]
    j['nodes'][root]['scale'] = [float(v) for v in s]
    j['nodes'][root].pop('matrix', None)
    log("yawed armature 180 so the model faces -Z (Godot forward)")


class Rig:
    """Skeleton helpers shared by the clip synthesizers."""

    def __init__(self, j, blob):
        self.j = j
        self.names = [n.get('name') for n in j['nodes']]
        self.idx = {n: i for i, n in enumerate(self.names)}
        self.parent = {c: i for i, n in enumerate(j['nodes'])
                       for c in n.get('children', [])}
        self.root = [i for i in range(len(self.names)) if i not in self.parent][0]
        self.driven = sorted({ch['target']['node']
                              for a in j.get('animations', [])
                              for ch in a['channels']})
        self.rest = {i: [np.array(v) for v in node_trs(j['nodes'][i])]
                     for i in self.driven}
        self._relaxed = None

    def world(self, pose):
        W = {}
        def walk(i, M):
            t, r, s = node_trs(self.j['nodes'][i])
            if i in pose: t, r, s = pose[i]
            W[i] = M @ trs_mat(t, r, s)
            for c in self.j['nodes'][i].get('children', []): walk(c, W[i])
        walk(self.root, np.eye(4))
        return W

    def aim(self, pose, bone, direction):
        """Rotate `bone` so its +Y axis (the bone direction) points along
        world `direction`, preserving roll."""
        i = self.idx[bone]
        Rp = self.world(pose)[self.parent[i]][:3, :3]
        Rp = Rp / np.linalg.norm(Rp[:, 0])              # strip uniform scale
        cur = qmat(pose[i][1]) @ np.array([0., 1., 0.])
        tgt = np.linalg.inv(Rp) @ (np.asarray(direction, float)
                                   / np.linalg.norm(direction))
        pose[i][1] = qmul(between(cur, tgt), pose[i][1])

    def spin(self, pose, bone, axis, deg):
        """Post-multiply a bone-local rotation (e.g. a spine yaw)."""
        i = self.idx[bone]
        pose[i][1] = qmul(pose[i][1], axis_angle(axis, np.radians(deg)))

    def copy(self, pose):
        return {k: [np.array(x) for x in v] for k, v in pose.items()}

    def relaxed(self):
        """Rest pose with the T/A-pose arms relaxed so each hand hangs just
        outside its thigh. Solved per arm: Meshy rigs are noticeably
        asymmetric (shoulders can sit several cm different distances from the
        centreline), so one shared arm angle buries a hand in the leg."""
        if self._relaxed is not None:
            return self.copy(self._relaxed)
        CLEARANCE = 0.04
        base = self.copy(self.rest)
        if all(b in self.idx for b in ('LeftUpLeg', 'RightUpLeg')):
            W = self.world(base)
            centre = (W[self.idx['LeftUpLeg']][0, 3]
                      + W[self.idx['RightUpLeg']][0, 3]) / 2
            for side in ('Left', 'Right'):
                arm, fore = side + 'Arm', side + 'ForeArm'
                hand, leg = side + 'Hand', side + 'UpLeg'
                if not all(b in self.idx for b in (arm, fore, hand, leg)):
                    continue
                sign = np.sign(self.world(base)[self.idx[arm]][0, 3] - centre) or 1.0
                goal = self.world(base)[self.idx[leg]][0, 3] + sign * CLEARANCE

                def place(c):
                    pose = self.copy(base)
                    self.aim(pose, arm,  [sign * c,        -1.0, 0.05])
                    self.aim(pose, fore, [sign * c * 0.65, -1.0, 0.24])
                    return pose, self.world(pose)[self.idx[hand]][0, 3]

                lo, hi = 0.0, 1.5
                for _ in range(40):                     # bisect on lateral lean
                    mid = (lo + hi) / 2
                    if (place(mid)[1] - goal) * sign < 0: lo = mid
                    else: hi = mid
                solved = place((lo + hi) / 2)[0]
                for b in (arm, fore):
                    base[self.idx[b]] = solved[self.idx[b]]
        self._relaxed = base
        return self.copy(base)


def write_clip(j, blob, name, times, poses, driven):
    """Serialise a list of poses (one per time) as a new animation."""
    keys = len(times)
    def add_acc(arr, typ):
        arr = np.ascontiguousarray(arr, dtype='<f4')
        while len(blob) % 4: blob.append(0)
        off = len(blob); blob.extend(arr.tobytes())
        j['bufferViews'].append({'buffer': 0, 'byteOffset': off,
                                 'byteLength': arr.nbytes})
        acc = {'bufferView': len(j['bufferViews']) - 1, 'componentType': 5126,
               'count': keys, 'type': typ}
        if typ == 'SCALAR':
            acc['min'] = [float(arr.min())]; acc['max'] = [float(arr.max())]
        j['accessors'].append(acc)
        return len(j['accessors']) - 1

    tin = add_acc(np.asarray(times).reshape(-1, 1), 'SCALAR')
    samplers, channels = [], []
    for i in driven:
        T = np.stack([p[i][0] for p in poses])
        R = np.stack([p[i][1] for p in poses])
        S = np.stack([p[i][2] for p in poses])
        for k in range(1, keys):                # keep quaternions on one cover
            if np.dot(R[k - 1], R[k]) < 0: R[k] = -R[k]
        for path, data, typ in (('translation', T, 'VEC3'),
                                ('rotation', R, 'VEC4'),
                                ('scale', S, 'VEC3')):
            samplers.append({'input': tin, 'interpolation': 'LINEAR',
                             'output': add_acc(data, typ)})
            channels.append({'sampler': len(samplers) - 1,
                             'target': {'node': i, 'path': path}})
    j.setdefault('animations', []).append(
        {'name': name, 'samplers': samplers, 'channels': channels})


def add_idle(j, blob, log, duration=4.0, keys=17):
    """Looping standing idle: the relaxed rest pose plus a slow breath cycle.

    Every bone the other clips drive gets a track here too -- a clip with
    missing tracks leaves those bones frozen wherever the previous animation
    stopped.
    """
    if any(a.get('name') == 'Idle' for a in j.get('animations', [])):
        log("Idle already present, skipping"); return
    rig = Rig(j, blob)
    if not rig.driven:
        log("no existing animation tracks to mirror, skipping idle"); return
    base = rig.relaxed()
    log("relaxed A/T-pose arms, hands solved to 4 cm outside each thigh")

    # +X on the spine chain pitches forward/back; amplitudes in degrees.
    breath = {'Spine02': -0.5, 'Spine01': -1.3, 'Spine': -0.9,
              'neck': 0.5, 'Head': 0.4}
    sway = {'LeftArm': 0.8, 'RightArm': -0.8,
            'LeftShoulder': 0.5, 'RightShoulder': -0.5}
    times = np.linspace(0.0, duration, keys)
    poses = []
    for ph in np.sin(2 * np.pi * times / duration):     # 0 at both ends: loops
        p = rig.copy(base)
        for nm, amp in breath.items():
            if nm in rig.idx and rig.idx[nm] in p:
                rig.spin(p, nm, [1, 0, 0], amp * ph)
        for nm, amp in sway.items():
            if nm in rig.idx and rig.idx[nm] in p:
                rig.spin(p, nm, [0, 0, 1], amp * ph)
        if 'Hips' in rig.idx and rig.idx['Hips'] in p:
            p[rig.idx['Hips']][0] = p[rig.idx['Hips']][0] + [0, 0.45 * ph, 0]
        poses.append(p)
    write_clip(j, blob, 'Idle', times, poses, rig.driven)
    log(f"added looping 'Idle' clip — {duration:g}s over {len(rig.driven)} bones")


ATTACKISH = ('attack', 'slash', 'thrust', 'punch', 'swing', 'smash', 'sweep',
             'hit', 'kick', 'shoot', 'cast', 'stomp', 'slam', 'throw', 'pitch',
             'shot', 'dunk', 'serve')


def dirlerp(d0, d1, u):
    """Spherical interpolation between two directions."""
    d0 = d0 / np.linalg.norm(d0); d1 = d1 / np.linalg.norm(d1)
    dot = float(np.clip(np.dot(d0, d1), -1, 1))
    ang = np.arccos(dot)
    if ang < 1e-6:
        return d0
    return (np.sin((1 - u) * ang) * d0 + np.sin(u * ang) * d1) / np.sin(ang)


def add_attack(j, blob, log, fps=30):
    """Synthesize a right-handed horizontal melee sweep ('Attack_Sweep') for
    rigged exports that ship with no attack clip at all: windup pulling the
    weapon arm back, an accelerating sweep across the front, follow-through,
    and a settle back onto the exact relaxed pose Idle starts from.

    Assumes the model already faces -Z (run after face_forward), where the
    character's right hand is on +X.
    """
    have = [a.get('name', '').lower() for a in j.get('animations', [])]
    if any(k in nm for nm in have for k in ATTACKISH):
        return                                          # a real attack exists
    rig = Rig(j, blob)
    if not rig.driven or 'RightArm' not in rig.idx:
        return
    base = rig.relaxed()
    Wb = rig.world(base)
    ybone = lambda b: (qmat(base[rig.idx[b]][1]) @ [0, 1, 0])
    arm0 = Wb[rig.idx['RightArm']][:3, :3] @ [0, 1, 0]  # relaxed arm dir
    arm0 = arm0 / np.linalg.norm(arm0)

    #        time   torso yaw   upper-arm dir            forearm dir      ease
    KEYS = [(0.00,   0.0,  arm0,                    arm0,                None),
            (0.14, -26.0,  [0.85, -0.30, +0.45],    [0.75, -0.05, +0.60], 'io'),
            (0.26, +14.0,  [0.05, -0.15, -0.95],    [0.00, +0.05, -1.00], 'in'),
            (0.40, +26.0,  [-0.65, -0.35, -0.55],   [-0.60, -0.20, -0.65], 'out'),
            (0.55,   0.0,  arm0,                    arm0,                'io')]
    EASE = {'in': lambda u: u * u * u,
            'out': lambda u: 1 - (1 - u) ** 3,
            'io': lambda u: u * u * (3 - 2 * u)}

    def at(t):
        for k in range(1, len(KEYS)):
            t0, t1 = KEYS[k - 1][0], KEYS[k][0]
            if t <= t1 or k == len(KEYS) - 1:
                u = EASE[KEYS[k][4]](np.clip((t - t0) / (t1 - t0), 0, 1))
                yaw = KEYS[k - 1][1] + u * (KEYS[k][1] - KEYS[k - 1][1])
                da = dirlerp(np.asarray(KEYS[k - 1][2], float),
                             np.asarray(KEYS[k][2], float), u)
                df = dirlerp(np.asarray(KEYS[k - 1][3], float),
                             np.asarray(KEYS[k][3], float), u)
                return yaw, da, df

    dur = KEYS[-1][0]
    times = np.linspace(0.0, dur, int(round(dur * fps)) + 1)
    poses = []
    for t in times:
        yaw, da, df = at(t)
        p = rig.copy(base)
        for bone, share in (('Hips', 0.35), ('Spine01', 0.40), ('Spine02', 0.25)):
            if bone in rig.idx and rig.idx[bone] in p:
                rig.spin(p, bone, [0, 1, 0], yaw * share)
        rig.aim(p, 'RightArm', da)
        if 'RightForeArm' in rig.idx:
            rig.aim(p, 'RightForeArm', df)
        if 'Hips' in rig.idx and rig.idx['Hips'] in p:      # settle into the hit
            dip = 1.5 * np.sin(np.pi * np.clip((t - 0.14) / (dur - 0.14), 0, 1))
            p[rig.idx['Hips']][0] = p[rig.idx['Hips']][0] - [0, dip, 0]
        poses.append(p)
    write_clip(j, blob, 'Attack_Sweep', times, poses, rig.driven)
    log(f"added 'Attack_Sweep' clip — {dur:g}s melee sweep (no attack clip "
        "shipped in the export)")


def split_held_item(j, blob, log, hand_side):
    """Split a hand-held item (a staff, a racket) into its own skinned node
    named "held_item" so the game can hide it while a thrown version flies.

    The item is found geometrically: vertices dominated by the <side>Hand
    joint further from the fist than the mitt reaches, clustered around the
    item's own PCA axis. Triangles fully inside that set move to a second
    mesh that shares the skin and vertex data; boundary triangles stay with
    the body so the fist remains sealed.
    """
    names = [n.get('name') for n in j['nodes']]
    skin = j['skins'][0]
    jn = {names[x]: k for k, x in enumerate(skin['joints'])}
    hand = hand_side.capitalize() + 'Hand'
    if hand not in jn:
        log(f"no {hand} joint, cannot split held item"); return

    prim = j['meshes'][0]['primitives'][0]
    def acc_read(ai):
        a = j['accessors'][ai]; bv = j['bufferViews'][a['bufferView']]
        off = bv.get('byteOffset', 0) + a.get('byteOffset', 0)
        dt = np.dtype('<' + CT[a['componentType']])
        return np.frombuffer(blob, dt, a['count'] * NC[a['type']],
                             off).reshape(a['count'], NC[a['type']])
    v = np.asarray(acc_read(prim['attributes']['POSITION']), np.float64)
    jj = acc_read(prim['attributes']['JOINTS_0']).astype(int)
    ww = np.asarray(acc_read(prim['attributes']['WEIGHTS_0']), np.float64)
    tris = acc_read(prim['indices']).reshape(-1, 3).astype(np.int64)

    ibm = np.asarray(acc_read(skin['inverseBindMatrices']),
                     np.float64).reshape(-1, 4, 4).transpose(0, 2, 1)
    hand_pos = np.linalg.inv(ibm[jn[hand]])[:3, 3]

    dom = jj[np.arange(len(jj)), ww.argmax(1)]
    dist = np.linalg.norm(v - hand_pos, axis=1)
    cand = (dom == jn[hand]) & (dist > 0.14)
    if cand.sum() < 40:
        log(f"no held item found on {hand} ({int(cand.sum())} candidate verts)")
        return
    c = v[cand].mean(0)
    axis = np.linalg.svd(v[cand] - c)[2][0]
    radial = np.linalg.norm((v - c) - np.outer((v - c) @ axis, axis), axis=1)
    item = (dom == jn[hand]) & (dist > 0.14) & (radial < 0.10)

    inside = item[tris].sum(1)
    item_tris = tris[inside == 3]
    body_tris = tris[inside < 3]
    if not len(item_tris):
        log("held-item split found no whole triangles, skipping"); return

    def add_index_acc(arr):
        arr = np.ascontiguousarray(arr.reshape(-1), dtype='<u4')
        while len(blob) % 4: blob.append(0)
        off = len(blob); blob.extend(arr.tobytes())
        j['bufferViews'].append({'buffer': 0, 'byteOffset': off,
                                 'byteLength': arr.nbytes})
        j['accessors'].append({'bufferView': len(j['bufferViews']) - 1,
                               'componentType': 5125, 'count': int(arr.size),
                               'type': 'SCALAR'})
        return len(j['accessors']) - 1

    prim['indices'] = add_index_acc(body_tris)          # body keeps mesh 0
    item_prim = dict(prim)
    item_prim['indices'] = add_index_acc(item_tris)
    j['meshes'].append({'name': 'held_item', 'primitives': [item_prim]})

    mesh_node = next(i for i, n in enumerate(j['nodes']) if 'mesh' in n)
    node = {'name': 'held_item', 'mesh': len(j['meshes']) - 1}
    if 'skin' in j['nodes'][mesh_node]:
        node['skin'] = j['nodes'][mesh_node]['skin']
    j['nodes'].append(node)
    parent = next(i for i, n in enumerate(j['nodes'])
                  if mesh_node in n.get('children', []))
    j['nodes'][parent]['children'].append(len(j['nodes']) - 1)
    log(f"split {len(item_tris)} triangles off {hand} into a 'held_item' "
        f"node ({len(body_tris)} stay with the body)")


def resize_textures(j, blob, log, max_side):
    """Downsample embedded textures to `max_side`. Meshy ships 4k and 8k bakes
    for characters that draw a few hundred pixels tall; the oversized ones cost
    file size, iOS bundle size, and minutes of Godot import time each. Uses
    `sips`, which is always present on macOS, so the tool keeps its no-extra-
    dependencies promise.
    """
    import subprocess, tempfile, struct as _struct
    changed = 0
    for im in j.get('images', []):
        bv_index = im.get('bufferView')
        if bv_index is None:
            continue
        bv = j['bufferViews'][bv_index]
        off = bv.get('byteOffset', 0)
        raw = bytes(blob[off:off + bv['byteLength']])
        if raw[:8] != b'\x89PNG\r\n\x1a\n':
            continue                      # only PNG bakes are handled
        w, h = _struct.unpack('>II', raw[16:24])
        if max(w, h) <= max_side:
            continue
        with tempfile.TemporaryDirectory() as tmp:
            src, dst = f"{tmp}/in.png", f"{tmp}/out.png"
            open(src, 'wb').write(raw)
            subprocess.run(["sips", "-Z", str(max_side), src, "--out", dst],
                           capture_output=True)
            try:
                new = open(dst, 'rb').read()
            except OSError:
                continue
        if not new or len(new) >= len(raw):
            continue
        delta = len(new) - bv['byteLength']
        blob[off:off + bv['byteLength']] = new
        bv['byteLength'] = len(new)
        for other in j['bufferViews']:
            if other is not bv and other.get('byteOffset', 0) > off:
                other['byteOffset'] += delta
        log(f"resized {im.get('name', 'texture')} {w}x{h} -> {max_side} "
            f"({len(raw)/1e6:.1f} MB -> {len(new)/1e6:.1f} MB)")
        changed += 1
    if changed:
        j['buffers'][0]['byteLength'] = len(blob)


def repack(j, blob, log):
    """Rebuild the binary chunk, dropping bufferViews nothing references."""
    used = set()
    for a in j.get('accessors', []):
        if 'bufferView' in a: used.add(a['bufferView'])
        used.update(v['bufferView'] for v in a.get('sparse', {}).get('indices', {}).values()
                    if isinstance(v, int))
    for im in j.get('images', []):
        if 'bufferView' in im: used.add(im['bufferView'])

    keep = sorted(used)
    new_blob, remap, views = bytearray(), {}, []
    for new_i, old_i in enumerate(keep):
        bv = dict(j['bufferViews'][old_i])
        off = bv.get('byteOffset', 0)
        data = blob[off:off + bv['byteLength']]
        while len(new_blob) % 4: new_blob.append(0)
        bv['byteOffset'] = len(new_blob); new_blob.extend(data)
        remap[old_i] = new_i; views.append(bv)

    freed = len(blob) - len(new_blob)
    j['bufferViews'] = views
    for a in j.get('accessors', []):
        if 'bufferView' in a: a['bufferView'] = remap[a['bufferView']]
    for im in j.get('images', []):
        if 'bufferView' in im: im['bufferView'] = remap[im['bufferView']]
    j['buffers'] = [{'byteLength': len(new_blob)}]
    if freed:
        log(f"repacked buffer, reclaimed {freed/1e6:.1f} MB")
    return new_blob


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('input')
    ap.add_argument('-o', '--output')
    ap.add_argument('--no-idle', action='store_true')
    ap.add_argument('--no-attack', action='store_true')
    ap.add_argument('--texture-size', type=int, default=0,
                    help="downsample embedded textures to at most N pixels")
    ap.add_argument('--split-held-item', choices=['left', 'right'],
                    help="split the item in this hand into a hideable "
                         "'held_item' node")
    args = ap.parse_args()
    out = args.output or args.input

    j, blob = load(args.input)
    before = os.path.getsize(args.input)
    steps = []
    log = lambda m: (steps.append(m), print(f"  - {m}"))

    print(f"{os.path.basename(args.input)}  ({before/1e6:.1f} MB)")
    drop_junk_clips(j, log)
    fix_material(j, log)
    flatten_uniform_mr(j, blob, log)
    drop_unused_textures(j, log)
    fix_stray_limb_weights(j, blob, log)
    face_forward(j, log)
    if not args.no_idle and j.get('skins'):
        add_idle(j, blob, log)
    if not args.no_attack and j.get('skins'):
        add_attack(j, blob, log)
    if args.split_held_item and j.get('skins'):
        split_held_item(j, blob, log, args.split_held_item)
    if args.texture_size:
        resize_textures(j, blob, log, args.texture_size)
    blob = repack(j, blob, log)
    save(out, j, blob)
    after = os.path.getsize(out)
    print(f"-> {os.path.basename(out)}  ({after/1e6:.1f} MB, "
          f"{100*(before-after)/before:.0f}% smaller)")
    if not steps:
        print("  (nothing to change)")


if __name__ == '__main__':
    main()
