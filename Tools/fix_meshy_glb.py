#!/usr/bin/env python3
"""Clean up a Meshy AI character export for the Godot port.

Meshy's GLB exports share a set of defects that make them render and behave
wrong in Godot. This fixes them in place and synthesizes the idle clip Meshy
does not produce:

  1. alphaMode BLEND on an opaque character -> transparency sorting artifacts
  2. base colour atlas wired into emissiveTexture at full strength -> the
     character self-illuminates and ignores scene lighting
  3. KHR_materials_specular specularColorFactor pushed past the valid 0-1 range
  4. the same 2048x2048 atlas embedded twice (base colour + emissive)
  5. a metallic-roughness texture that is uniform -- megabytes encoding two
     numbers, replaced with metallicFactor/roughnessFactor scalars
  6. model faces +Z, but Godot forward -- and fighter.gd's facing nose -- is -Z
  7. no idle animation, so a standing fighter has nothing to play (skipped
     automatically for unrigged models)

Usage:  python3 Tools/fix_meshy_glb.py <in.glb> [-o <out.glb>] [--no-idle]

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


def add_idle(j, blob, log, duration=4.0, keys=17):
    """Build a looping standing idle from the rest pose.

    The rest pose is the only genuinely standing pose in a Meshy export -- feet
    level, legs straight, most upright -- but it is a stiff A-pose, so the arms
    are relaxed toward the body first. Then a slow breath cycle is layered on.
    Every bone the other clips drive gets a track here too: a clip with missing
    tracks leaves those bones frozen wherever the previous animation stopped.
    """
    if any(a.get('name') == 'Idle' for a in j.get('animations', [])):
        log("Idle already present, skipping"); return
    names = [n.get('name') for n in j['nodes']]
    idx = {n: i for i, n in enumerate(names)}
    parent = {c: i for i, n in enumerate(j['nodes']) for c in n.get('children', [])}
    roots = [i for i in range(len(j['nodes'])) if i not in parent]
    root = roots[0]

    driven = sorted({ch['target']['node'] for a in j.get('animations', [])
                     for ch in a['channels']})
    if not driven:
        log("no existing animation tracks to mirror, skipping idle"); return

    base = {i: list(node_trs(j['nodes'][i])) for i in driven}

    def world(over):
        W = {}
        def walk(i, M):
            t, r, s = node_trs(j['nodes'][i])
            if i in over: t, r, s = over[i]
            W[i] = M @ trs_mat(t, r, s)
            for c in j['nodes'][i].get('children', []): walk(c, W[i])
        walk(root, np.eye(4)); return W

    # --- relax the A-pose arms so the hands hang just outside the thighs ---
    # Bones run along local +Y, so a bone's world direction is its Y column.
    # Meshy rigs are noticeably asymmetric (here the two shoulders sit 6 cm
    # different distances from the centreline), so aiming both arms along one
    # fixed world direction buries the shorter side in the thigh. Solve each
    # arm separately for a real clearance instead.
    CLEARANCE = 0.04
    if all(b in idx for b in ('LeftUpLeg', 'RightUpLeg')):
        W = world(base)
        centre = (W[idx['LeftUpLeg']][0, 3] + W[idx['RightUpLeg']][0, 3]) / 2

        def aim(bone, direction, pose):
            """Point `bone` along world `direction`, preserving roll."""
            i = idx[bone]
            Rp = world(pose)[parent[i]][:3, :3]
            Rp = Rp / np.linalg.norm(Rp[:, 0])          # strip uniform scale
            cur = qmat(pose[i][1]) @ np.array([0., 1., 0.])
            tgt = np.linalg.inv(Rp) @ (direction / np.linalg.norm(direction))
            pose[i][1] = qmul(between(cur, tgt), pose[i][1])

        for side in ('Left', 'Right'):
            arm, fore = side + 'Arm', side + 'ForeArm'
            hand, leg = side + 'Hand', side + 'UpLeg'
            if not all(b in idx for b in (arm, fore, hand, leg)):
                continue
            sign = np.sign(world(base)[idx[arm]][0, 3] - centre) or 1.0
            goal = world(base)[idx[leg]][0, 3] + sign * CLEARANCE

            def place(c):
                pose = {k: list(v) for k, v in base.items()}
                aim(arm,  np.array([sign * c,        -1.0, 0.05]), pose)
                aim(fore, np.array([sign * c * 0.65, -1.0, 0.24]), pose)
                return pose, world(pose)[idx[hand]][0, 3]

            lo, hi = 0.0, 1.5
            for _ in range(40):                          # bisect on lateral lean
                mid = (lo + hi) / 2
                if (place(mid)[1] - goal) * sign < 0: lo = mid
                else: hi = mid
            solved = place((lo + hi) / 2)[0]
            for b in (arm, fore):
                base[idx[b]] = solved[idx[b]]
        log(f"relaxed A-pose arms, hands solved to {CLEARANCE*100:.0f} cm "
            "outside each thigh")

    # --- breath cycle layered on the relaxed pose ---
    # +X on the spine chain pitches forward/back; amplitudes in degrees.
    breath = {'Spine02': -0.5, 'Spine01': -1.3, 'Spine': -0.9, 'neck': 0.5, 'Head': 0.4}
    sway = {'LeftArm': 0.8, 'RightArm': -0.8, 'LeftShoulder': 0.5, 'RightShoulder': -0.5}
    times = np.linspace(0.0, duration, keys)
    phase = np.sin(2 * np.pi * times / duration)          # 0 at both ends -> loops

    tracks = {}
    for i in driven:
        t0, r0, s0 = base[i]
        T = np.tile(t0, (keys, 1)); R = np.tile(r0, (keys, 1)); S = np.tile(s0, (keys, 1))
        nm = names[i]
        if nm in breath:
            for k in range(keys):
                R[k] = qmul(r0, axis_angle([1, 0, 0], np.radians(breath[nm]) * phase[k]))
        if nm in sway:
            for k in range(keys):
                R[k] = qmul(R[k], axis_angle([0, 0, 1], np.radians(sway[nm]) * phase[k]))
        if nm == 'Hips':
            # subtle vertical settle, in the rig's centimetre units
            T[:, 1] = t0[1] + 0.45 * phase
        tracks[i] = (T, R, S)

    # --- serialise ---
    def add_view(arr):
        arr = np.ascontiguousarray(arr, dtype='<f4')
        while len(blob) % 4: blob.append(0)
        off = len(blob); blob.extend(arr.tobytes())
        j['bufferViews'].append({'buffer': 0, 'byteOffset': off, 'byteLength': arr.nbytes})
        return len(j['bufferViews']) - 1

    def add_acc(arr, typ):
        arr = np.asarray(arr, dtype='<f4')
        acc = {'bufferView': add_view(arr), 'componentType': 5126,
               'count': int(arr.shape[0]), 'type': typ}
        if typ == 'SCALAR':
            acc['min'] = [float(arr.min())]; acc['max'] = [float(arr.max())]
        j['accessors'].append(acc)
        return len(j['accessors']) - 1

    tin = add_acc(times.reshape(-1, 1), 'SCALAR')
    samplers, channels = [], []
    for i, (T, R, S) in tracks.items():
        for path, data, typ in (('translation', T, 'VEC3'),
                                ('rotation', R, 'VEC4'),
                                ('scale', S, 'VEC3')):
            samplers.append({'input': tin, 'interpolation': 'LINEAR',
                             'output': add_acc(data, typ)})
            channels.append({'sampler': len(samplers) - 1,
                             'target': {'node': i, 'path': path}})
    j.setdefault('animations', []).append(
        {'name': 'Idle', 'samplers': samplers, 'channels': channels})
    log(f"added looping 'Idle' clip — {duration:g}s, {len(channels)} channels "
        f"over {len(tracks)} bones")


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
    args = ap.parse_args()
    out = args.output or args.input

    j, blob = load(args.input)
    before = os.path.getsize(args.input)
    steps = []
    log = lambda m: (steps.append(m), print(f"  - {m}"))

    print(f"{os.path.basename(args.input)}  ({before/1e6:.1f} MB)")
    fix_material(j, log)
    flatten_uniform_mr(j, blob, log)
    drop_unused_textures(j, log)
    face_forward(j, log)
    if not args.no_idle and j.get('skins'):
        add_idle(j, blob, log)
    blob = repack(j, blob, log)
    save(out, j, blob)
    after = os.path.getsize(out)
    print(f"-> {os.path.basename(out)}  ({after/1e6:.1f} MB, "
          f"{100*(before-after)/before:.0f}% smaller)")
    if not steps:
        print("  (nothing to change)")


if __name__ == '__main__':
    main()
