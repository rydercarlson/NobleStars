// Procedural idle-animation generator for Meshy / Mixamo-style rigs.
// Builds a looping THREE.AnimationClip ("Idle") from the model's rest pose so it can be
// cross-faded with the baked clips (attack, run...) through a normal AnimationMixer.
//
// Bones are addressed by name fragments and rotations are described in WORLD space
// (pitch = about world X, yaw = about world Y, roll = about world Z), so the generator
// works regardless of how the auto-rigger oriented each bone's local axes.

import * as THREE from 'three';

const DEG = Math.PI / 180;

const BONE_ALIASES = {
  hips: ['hips', 'pelvis'],
  spine: ['spine$', 'spine1$', 'spine_01', 'spine01$'],
  spine1: ['spine01', 'spine1', 'spine_01'],
  spine2: ['spine02', 'spine2', 'spine_02', 'chest'],
  neck: ['neck'],
  head: ['^head$', 'head$'],
  lShoulder: ['leftshoulder', 'shoulder_l', 'l_shoulder', 'shoulder.l'],
  rShoulder: ['rightshoulder', 'shoulder_r', 'r_shoulder', 'shoulder.r'],
  lArm: ['leftarm$', 'upperarm_l', 'l_upperarm', 'upper_arm.l'],
  rArm: ['rightarm$', 'upperarm_r', 'r_upperarm', 'upper_arm.r'],
  lForeArm: ['leftforearm', 'lowerarm_l', 'forearm.l'],
  rForeArm: ['rightforearm', 'lowerarm_r', 'forearm.r'],
  lHand: ['lefthand$', 'hand_l', 'hand.l'],
  rHand: ['righthand$', 'hand_r', 'hand.r'],
  lUpLeg: ['leftupleg', 'thigh_l', 'thigh.l'],
  rUpLeg: ['rightupleg', 'thigh_r', 'thigh.r'],
  lLeg: ['leftleg$', 'calf_l', 'shin.l'],
  rLeg: ['rightleg$', 'calf_r', 'shin.r'],
};

export function findBones(root) {
  const bones = [];
  root.traverse((o) => { if (o.isBone) bones.push(o); });
  const map = {};
  for (const key in BONE_ALIASES) {
    for (const pat of BONE_ALIASES[key]) {
      const re = new RegExp(pat, 'i');
      const b = bones.find((bn) => re.test(bn.name));
      if (b) { map[key] = b; break; }
    }
  }
  map._all = bones;
  return map;
}

function smoothNoise(t, seed) {
  // sum of incommensurate sines -> organic, deterministic, loopable-ish motion
  return 0.55 * Math.sin(t * 1.0 + seed) + 0.3 * Math.sin(t * 2.3 + seed * 1.7) + 0.15 * Math.sin(t * 3.7 + seed * 0.3);
}

/**
 * @param {THREE.Object3D} root  loaded gltf scene (rest pose)
 * @param {THREE.AnimationClip[]} animations  baked clips (used to borrow a natural upper-body pose)
 * @param {object} opts
 *   duration   loop length in seconds (default 4.8)
 *   fps        keyframe rate (default 30)
 *   stance     'relaxed' | 'ready'  arm posture (default 'relaxed')
 *   walkTime   if set, sample upper body from the Walking clip at this time instead of building a stance
 */
export function buildIdleClip(root, animations = [], opts = {}) {
  const duration = opts.duration ?? 4.8;
  const fps = opts.fps ?? 30;
  const stance = opts.stance ?? 'relaxed';
  const B = findBones(root);

  root.updateMatrixWorld(true);

  // ---- 1. capture rest pose --------------------------------------------------------
  const rest = new Map();
  for (const b of B._all) rest.set(b, { q: b.quaternion.clone(), p: b.position.clone() });

  // parent world orientation in rest pose (for world->local conversion)
  const parentWorldQ = new Map();
  for (const b of B._all) {
    const q = new THREE.Quaternion();
    if (b.parent) b.parent.getWorldQuaternion(q);
    parentWorldQ.set(b, q);
  }
  const rootInvQ = new THREE.Quaternion(); root.getWorldQuaternion(rootInvQ).invert();

  // apply a rotation expressed in root(world) space to a bone's local quaternion
  const worldRot = (bone, pitch, yaw, roll) => {
    const qp = parentWorldQ.get(bone);
    const e = new THREE.Euler(pitch * DEG, yaw * DEG, roll * DEG, 'XYZ');
    const R = new THREE.Quaternion().setFromEuler(e);
    // R is in world space; root may itself be rotated -> bring into world
    const rw = rootInvQ.clone().invert();
    R.premultiply(rw).multiply(rootInvQ);
    const qpInv = qp.clone().invert();
    return qpInv.multiply(R).multiply(qp); // local-space offset
  };

  // ---- 2. build the base stance --------------------------------------------------
  const base = new Map(); // bone -> quaternion
  for (const b of B._all) base.set(b, rest.get(b).q.clone());

  const walk = animations.find((a) => /walk/i.test(a.name)) || animations.find((a) => /run/i.test(a.name));
  if (opts.walkTime != null && walk) {
    const mixer = new THREE.AnimationMixer(root);
    const act = mixer.clipAction(walk); act.play(); mixer.setTime(opts.walkTime);
    const upper = ['spine', 'spine1', 'spine2', 'neck', 'head', 'lShoulder', 'rShoulder', 'lArm', 'rArm', 'lForeArm', 'rForeArm', 'lHand', 'rHand'];
    for (const k of upper) if (B[k]) base.set(B[k], B[k].quaternion.clone());
    mixer.stopAllAction();
    for (const b of B._all) { b.quaternion.copy(rest.get(b).q); b.position.copy(rest.get(b).p); }
    root.updateMatrixWorld(true);
  } else {
    // Determine which side each arm hangs on (world X sign of the arm's child joint)
    const sideOf = (bone) => {
      const p = new THREE.Vector3(); bone.getWorldPosition(p);
      const c = new THREE.Vector3(); (bone.children[0] || bone).getWorldPosition(c);
      return Math.sign(c.x - p.x) || 1; // +1 => arm points to +X
    };
    const setArm = (arm, fore, hand, shoulder) => {
      if (!arm) return;
      const s = sideOf(arm); // +1 for arm extending toward +X
      const down = stance === 'ready' ? 52 : 68;      // degrees to drop from T-pose
      const fwd = stance === 'ready' ? 22 : 8;        // bring hands forward
      // drop: rotate about world Z (arm pointing +X rotates clockwise => negative)
      let q = worldRot(arm, 0, 0, -down * s);
      // forward: rotate about world X... arm pointing down rotates forward with negative pitch? use yaw around Y before drop instead
      q.premultiply(worldRot(arm, 0, fwd * s * -1, 0));
      q.premultiply(worldRot(arm, 0, 0, 0));
      base.set(arm, q.clone().multiply(rest.get(arm).q));
      if (fore) {
        const bend = stance === 'ready' ? 55 : 22;
        // elbow bend: rotate forearm forward around world X-ish axis (after arm drop the forearm points down,
        // bending it forward = pitch around world X toward +Z). Use roll around world Y too for natural inward turn.
        const qf = worldRot(fore, 0, 0, -bend * s * 0.15).premultiply(worldRot(fore, -bend * 0.85, 0, 0));
        base.set(fore, qf.multiply(rest.get(fore).q));
      }
      if (hand) {
        const qh = worldRot(hand, -10, 0, 0);
        base.set(hand, qh.multiply(rest.get(hand).q));
      }
      if (shoulder) {
        const qs = worldRot(shoulder, 0, 0, -6 * s);
        base.set(shoulder, qs.multiply(rest.get(shoulder).q));
      }
    };
    setArm(B.lArm, B.lForeArm, B.lHand, B.lShoulder);
    setArm(B.rArm, B.rForeArm, B.rHand, B.rShoulder);
    // slight relaxed stance: feet a bit apart, tiny knee bend, torso a touch forward
    if (B.lUpLeg) base.set(B.lUpLeg, worldRot(B.lUpLeg, -3, 0, -4 * (sideOf(B.lUpLeg) < 0 ? -1 : 1) * 0.5).multiply(rest.get(B.lUpLeg).q));
    if (B.rUpLeg) base.set(B.rUpLeg, worldRot(B.rUpLeg, -3, 0, 4 * (sideOf(B.rUpLeg) < 0 ? -1 : 1) * 0.5).multiply(rest.get(B.rUpLeg).q));
    if (B.lLeg) base.set(B.lLeg, worldRot(B.lLeg, 4, 0, 0).multiply(rest.get(B.lLeg).q));
    if (B.rLeg) base.set(B.rLeg, worldRot(B.rLeg, 4, 0, 0).multiply(rest.get(B.rLeg).q));
    if (B.spine) base.set(B.spine, worldRot(B.spine, 2, 0, 0).multiply(rest.get(B.spine).q));
  }

  // ---- 3. animated layers ----------------------------------------------------------
  // scale of hip bob relative to skeleton size
  const hipsLen = B.hips ? B.hips.position.length() : 1;
  const hipBob = hipsLen * 0.022;
  const seed = opts.seed ?? 1.3;

  const layers = []; // {bone, fn(t) -> {pitch,yaw,roll,dy}}
  const add = (bone, fn) => { if (bone) layers.push({ bone, fn }); };
  const w = (2 * Math.PI) / duration;

  add(B.hips, (t) => ({
    dy: -hipBob * (0.5 - 0.5 * Math.cos(w * 2 * t)),
    roll: 1.4 * Math.sin(w * t),
    yaw: 2.0 * Math.sin(w * t + 0.4),
    pitch: 0.8 * Math.sin(w * 2 * t),
  }));
  add(B.spine, (t) => ({ roll: -1.6 * Math.sin(w * t), pitch: 1.4 * Math.sin(w * 2 * t + 0.5) }));
  add(B.spine1, (t) => ({ pitch: 2.0 * Math.sin(w * 2 * t + 0.9), roll: -0.9 * Math.sin(w * t) }));
  add(B.spine2, (t) => ({ pitch: 2.6 * Math.sin(w * 2 * t + 1.2), yaw: 1.2 * Math.sin(w * t + 1) }));
  add(B.neck, (t) => ({ pitch: -1.2 * Math.sin(w * 2 * t + 1.2), yaw: 2.5 * smoothNoise(t * 0.9, seed) }));
  add(B.head, (t) => ({ yaw: 9 * smoothNoise(t * 0.7, seed + 2), pitch: 3.5 * smoothNoise(t * 0.8, seed + 5), roll: 2.0 * smoothNoise(t * 0.5, seed + 9) }));
  const armSide = (bone) => { if (!bone) return 1; const p = new THREE.Vector3(); bone.getWorldPosition(p); return p.x >= 0 ? 1 : -1; };
  const ls = armSide(B.lArm), rs = armSide(B.rArm);
  add(B.lShoulder, (t) => ({ roll: -0.9 * ls * (0.5 - 0.5 * Math.cos(w * 2 * t + 1.2)) }));
  add(B.rShoulder, (t) => ({ roll: -0.9 * rs * (0.5 - 0.5 * Math.cos(w * 2 * t + 1.2)) }));
  add(B.lArm, (t) => ({ roll: -4.5 * ls * (0.5 - 0.5 * Math.cos(w * 2 * t + 1.2)), pitch: 3.0 * Math.sin(w * t + 0.3) }));
  add(B.rArm, (t) => ({ roll: -4.5 * rs * (0.5 - 0.5 * Math.cos(w * 2 * t + 1.2)), pitch: -3.0 * Math.sin(w * t + 0.3) }));
  add(B.lForeArm, (t) => ({ pitch: -5 * (0.5 - 0.5 * Math.cos(w * 2 * t + 1.6)) }));
  add(B.rForeArm, (t) => ({ pitch: -5 * (0.5 - 0.5 * Math.cos(w * 2 * t + 1.6)) }));
  add(B.lHand, (t) => ({ pitch: -6 * smoothNoise(t * 0.6, seed + 3) }));
  add(B.rHand, (t) => ({ pitch: -6 * smoothNoise(t * 0.6, seed + 7) }));
  // weight shift through the legs (counter the hips roll so feet stay planted)
  add(B.lUpLeg, (t) => ({ roll: -1.4 * Math.sin(w * t) }));
  add(B.rUpLeg, (t) => ({ roll: -1.4 * Math.sin(w * t) }));

  // ---- 4. bake keyframes -----------------------------------------------------------
  const n = Math.round(duration * fps);
  const times = new Float32Array(n + 1);
  for (let i = 0; i <= n; i++) times[i] = i / fps;
  const tracks = [];
  const animatedBones = new Set(layers.map((l) => l.bone));

  // static tracks for posed-but-not-animated bones (keeps them from snapping when blending)
  for (const [bone, q] of base) {
    if (animatedBones.has(bone)) continue;
    if (q.equals(rest.get(bone).q)) continue;
    const vals = new Float32Array((n + 1) * 4);
    for (let i = 0; i <= n; i++) { vals[i * 4] = q.x; vals[i * 4 + 1] = q.y; vals[i * 4 + 2] = q.z; vals[i * 4 + 3] = q.w; }
    tracks.push(new THREE.QuaternionKeyframeTrack(`${bone.name}.quaternion`, times, vals));
  }

  for (const { bone, fn } of layers) {
    const qv = new Float32Array((n + 1) * 4);
    const pv = new Float32Array((n + 1) * 3);
    let hasPos = false;
    const b0 = base.get(bone);
    const p0 = rest.get(bone).p;
    for (let i = 0; i <= n; i++) {
      // ensure loop closure by blending tail into head
      const t = times[i];
      const o = fn(t);
      const o2 = fn(t - duration); // identical for pure w-multiples; noise terms differ -> blend
      const k = i / n; // 0..1
      const mix = (a, b) => (a ?? 0) * (1 - k * k * k) + (b ?? 0) * (k * k * k);
      const pitch = mix(o.pitch, o2.pitch), yaw = mix(o.yaw, o2.yaw), roll = mix(o.roll, o2.roll), dy = mix(o.dy, o2.dy);
      const q = worldRot(bone, pitch, yaw, roll).multiply(b0);
      qv[i * 4] = q.x; qv[i * 4 + 1] = q.y; qv[i * 4 + 2] = q.z; qv[i * 4 + 3] = q.w;
      if (dy) hasPos = true;
      // hips bob along the bone's parent-space up axis (world Y mapped into parent space)
      const up = new THREE.Vector3(0, 1, 0).applyQuaternion(parentWorldQ.get(bone).clone().invert());
      pv[i * 3] = p0.x + up.x * dy; pv[i * 3 + 1] = p0.y + up.y * dy; pv[i * 3 + 2] = p0.z + up.z * dy;
    }
    tracks.push(new THREE.QuaternionKeyframeTrack(`${bone.name}.quaternion`, times, qv));
    if (hasPos) tracks.push(new THREE.VectorKeyframeTrack(`${bone.name}.position`, times, pv));
  }

  const clip = new THREE.AnimationClip('Idle', duration, tracks);
  return clip;
}

/**
 * Small looping head/neck "personality" layer, meant to be converted with
 * AnimationUtils.makeClipAdditive and played on top of a baked Idle clip.
 * First keyframe is the rest pose, so the additive reference is clean.
 */
export function buildAccentClip(root, opts = {}) {
  const duration = opts.duration ?? 6.4;
  const fps = 30;
  const seed = opts.seed ?? 1.3;
  const B = findBones(root);
  if (!B.head && !B.neck) return null;
  root.updateMatrixWorld(true);
  const parentWorldQ = new Map();
  for (const b of B._all) {
    const q = new THREE.Quaternion();
    if (b.parent) b.parent.getWorldQuaternion(q);
    parentWorldQ.set(b, q);
  }
  const worldRot = (bone, pitch, yaw, roll) => {
    const qp = parentWorldQ.get(bone);
    const e = new THREE.Euler(pitch * DEG, yaw * DEG, roll * DEG, 'XYZ');
    const R = new THREE.Quaternion().setFromEuler(e);
    const qpInv = qp.clone().invert();
    return qpInv.multiply(R).multiply(qp);
  };
  // ease in from exactly zero so frame 0 (the additive reference) is rest
  const env = (t) => Math.min(1, t * 2) * Math.min(1, (duration - t) * 2);
  const n = Math.round(duration * fps);
  const times = new Float32Array(n + 1);
  for (let i = 0; i <= n; i++) times[i] = i / fps;
  const tracks = [];
  const addTrack = (bone, fn) => {
    if (!bone) return;
    const rest = bone.quaternion.clone();
    const qv = new Float32Array((n + 1) * 4);
    for (let i = 0; i <= n; i++) {
      const t = times[i];
      const o = fn(t);
      const k = env(t);
      const q = worldRot(bone, (o.pitch ?? 0) * k, (o.yaw ?? 0) * k, (o.roll ?? 0) * k).multiply(rest);
      qv[i * 4] = q.x; qv[i * 4 + 1] = q.y; qv[i * 4 + 2] = q.z; qv[i * 4 + 3] = q.w;
    }
    tracks.push(new THREE.QuaternionKeyframeTrack(`${bone.name}.quaternion`, times, qv));
  };
  addTrack(B.head, (t) => ({
    yaw: 7 * smoothNoise(t * 0.55, seed + 2),
    pitch: 2.5 * smoothNoise(t * 0.7, seed + 5),
    roll: 1.5 * smoothNoise(t * 0.45, seed + 9),
  }));
  addTrack(B.neck, (t) => ({ yaw: 3 * smoothNoise(t * 0.5, seed) }));
  return new THREE.AnimationClip('IdleAccent', duration, tracks);
}
