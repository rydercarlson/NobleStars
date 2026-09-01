// 3D brawler viewer: loads a Meshy GLB, builds a procedural idle, blends baked attack
// clips on tap, spins on drag, and casts a real contact shadow onto an invisible floor.

import * as THREE from 'three';
import { GLTFLoader } from 'three/addons/loaders/GLTFLoader.js';
import { clone as cloneSkeleton } from 'three/addons/utils/SkeletonUtils.js';
import { buildIdleClip, buildAccentClip } from './idle.js';
import { url as assetUrl } from './assets.js';

const loader = new GLTFLoader();
const cache = new Map(); // url -> Promise<gltf>

export function preloadModel(u) {
  const full = assetUrl(u);
  if (!cache.has(full)) cache.set(full, loader.loadAsync(full));
  return cache.get(full);
}

/** Brawl-style ink outline: an inverted hull pushed out along the normals, drawn behind the mesh. */
function addOutline(model, width) {
  const meshes = []; model.traverse((o) => { if (o.isMesh && !o.userData.isOutline) meshes.push(o); });
  for (const m of meshes) {
    const mat = new THREE.MeshBasicMaterial({ color: 0x0b0d16, side: THREE.BackSide });
    mat.onBeforeCompile = (sh) => {
      sh.uniforms.uWidth = { value: width };
      sh.vertexShader = sh.vertexShader.replace('#include <common>', '#include <common>\nuniform float uWidth;')
        .replace('#include <skinning_vertex>', '#include <skinning_vertex>\ntransformed += normalize(objectNormal) * uWidth * (1.0 / max(0.0001, length(vec3(modelMatrix[0][0], modelMatrix[1][1], modelMatrix[2][2])) / 1.7320508));');
    };
    let hull;
    if (m.isSkinnedMesh) { hull = new THREE.SkinnedMesh(m.geometry, mat); hull.bind(m.skeleton, m.bindMatrix); hull.bindMode = m.bindMode; }
    else hull = new THREE.Mesh(m.geometry, mat);
    hull.userData.isOutline = true; hull.frustumCulled = false; hull.renderOrder = -1; hull.castShadow = false;
    hull.position.copy(m.position); hull.quaternion.copy(m.quaternion); hull.scale.copy(m.scale);
    m.parent.add(hull);
  }
}

export class BrawlerView {
  /**
   * @param {HTMLCanvasElement} canvas
   * @param {object} opts  { fov, fill (0..1 model height / canvas height), lookY, shadow, spin, onTap }
   */
  constructor(canvas, opts = {}) {
    this.canvas = canvas;
    this.opts = Object.assign({ fov: 22, fill: 0.78, lookY: 0.5, shadow: true, spin: true, autoReturn: true, onTap: null }, opts);
    this.renderer = new THREE.WebGLRenderer({ canvas, antialias: true, alpha: true, powerPreference: 'high-performance' });
    this.renderer.setClearColor(0x000000, 0);
    this.renderer.outputColorSpace = THREE.SRGBColorSpace;
    this.renderer.toneMapping = THREE.NoToneMapping;
    this.renderer.shadowMap.enabled = !!this.opts.shadow;
    this.renderer.shadowMap.type = THREE.PCFSoftShadowMap;
    this.scene = new THREE.Scene();
    this.camera = new THREE.PerspectiveCamera(this.opts.fov, 1, 0.05, 50);
    this.group = new THREE.Group(); // rotates with drag
    this.scene.add(this.group);
    this.clock = new THREE.Clock();
    this.mixer = null; this.model = null; this.actions = {}; this.idleAction = null; this.current = null;
    this.rotY = 0; this.rotVel = 0; this.dragging = false; this.lastDragT = 0; this.baseYaw = 0;
    this.visible = true; this.disposed = false;
    this._lights();
    this._floor();
    this._events();
    this.resize();
    if (window.ResizeObserver) { this._ro = new ResizeObserver(() => this.resize()); this._ro.observe(canvas); }
    this._loop = this._loop.bind(this);
    requestAnimationFrame(this._loop);
  }

  _lights() {
    const s = this.scene;
    s.add(new THREE.HemisphereLight(0xfff4e0, 0x2b3aa0, 1.35));
    const key = new THREE.DirectionalLight(0xfff1d6, 2.6); key.position.set(0.9, 4.0, 1.8);
    key.castShadow = true; key.shadow.mapSize.set(1024, 1024); key.shadow.camera.near = 0.5; key.shadow.camera.far = 10;
    key.shadow.camera.left = key.shadow.camera.bottom = -1.2; key.shadow.camera.right = key.shadow.camera.top = 1.2; key.shadow.bias = -0.0008; key.shadow.radius = 4;
    s.add(key); this.key = key;
    const fill = new THREE.DirectionalLight(0x9ec1ff, 0.9); fill.position.set(-2.2, 1.4, 1.6); s.add(fill);
    const rim = new THREE.DirectionalLight(0xffc35c, 1.6); rim.position.set(-0.8, 2.2, -2.6); s.add(rim);
  }

  _floor() {
    const geo = new THREE.PlaneGeometry(6, 6);
    const mat = new THREE.ShadowMaterial({ opacity: 0.42, color: 0x081030 });
    const floor = new THREE.Mesh(geo, mat); floor.rotation.x = -Math.PI / 2; floor.position.y = 0; floor.receiveShadow = true;
    this.scene.add(floor); this.floor = floor;
  }

  _events() {
    const c = this.canvas; let sx = 0, sy = 0, moved = false, lastX = 0, lastT = 0;
    c.addEventListener('pointerdown', (e) => {
      if (!this.model) return;
      sx = lastX = e.clientX; sy = e.clientY; moved = false; lastT = performance.now();
      this.dragging = true; this.rotVel = 0; c.setPointerCapture(e.pointerId); c.parentElement?.classList.add('dragging');
    });
    c.addEventListener('pointermove', (e) => {
      if (!this.dragging) return;
      const dx = e.clientX - lastX; lastX = e.clientX;
      if (Math.abs(e.clientX - sx) > 6 || Math.abs(e.clientY - sy) > 6) moved = true;
      if (this.opts.spin) { const now = performance.now(); const dt = Math.max(1, now - lastT) / 1000; lastT = now; this.rotY += dx * 0.012; this.rotVel = (dx * 0.012) / dt; }
    });
    const up = (e) => {
      if (!this.dragging) return;
      this.dragging = false; this.lastDragT = performance.now(); c.parentElement?.classList.remove('dragging');
      if (!moved) this.tap();
    };
    c.addEventListener('pointerup', up); c.addEventListener('pointercancel', up);
  }

  resize() {
    const w = this.canvas.clientWidth || 1, hgt = this.canvas.clientHeight || 1;
    const dpr = Math.min(window.devicePixelRatio || 1, 2);
    this.renderer.setPixelRatio(dpr); this.renderer.setSize(w, hgt, false);
    this.camera.aspect = w / hgt; this.camera.updateProjectionMatrix();
    this._frame();
  }

  _frame() {
    // model is normalized to height 1 with feet at y=0. Fit `fill` of the canvas height.
    const vis = 1 / this.opts.fill; // world units visible vertically at the look distance
    const d = vis / (2 * Math.tan(THREE.MathUtils.degToRad(this.opts.fov) / 2));
    this.camera.position.set(0, this.opts.lookY + 0.10, d);
    this.camera.lookAt(0, this.opts.lookY, 0);
    this.camera.updateMatrixWorld();
  }

  /** Normalized screen-y (0 top .. 1 bottom) where the feet land, for positioning the canvas on a floor line. */
  footScreenY() {
    const v = new THREE.Vector3(0, 0, 0).project(this.camera);
    return (1 - v.y) / 2;
  }

  async load(brawler) {
    this.brawler = brawler; const gltf = await preloadModel(brawler.model);
    if (this.disposed || this.brawler !== brawler) return;
    this.clear();
    const model = cloneSkeleton(gltf.scene);
    // normalize: height 1, feet at 0, centered on x/z
    model.updateMatrixWorld(true);
    const box = new THREE.Box3().setFromObject(model); const size = box.getSize(new THREE.Vector3());
    const s = 1 / size.y; model.scale.setScalar(s);
    model.updateMatrixWorld(true);
    const box2 = new THREE.Box3().setFromObject(model); const c = box2.getCenter(new THREE.Vector3());
    model.position.set(-c.x, -box2.min.y, -c.z);
    model.traverse((o) => {
      if (!o.isMesh) return;
      o.castShadow = true; o.receiveShadow = false; o.frustumCulled = false;
      const mat = o.material;
      if (!mat) return;
      mat.side = THREE.FrontSide;
      // Meshy leaves metallicFactor at the glTF default of 1.0; full metal
      // renders near-black without a reflection probe.
      if (mat.metalness !== undefined) mat.metalness = 0;
      // Menu-brightness lift so brawlers pop against the stage. Models that
      // still carry Meshy's emissive-duplicate are already self-lit, so only
      // the cleaned ones get the boost — this can never double-expose.
      if (mat.map && !mat.emissiveMap) {
        mat.emissive = new THREE.Color(0xffffff);
        mat.emissiveMap = mat.map;
        mat.emissiveIntensity = 0.34;
      }
      mat.needsUpdate = true;
    });
    if (this.opts.outline !== false) addOutline(model, this.opts.outlineWidth ?? 0.0055);
    this.group.add(model); this.model = model;
    // Meshy exports face +Z; the cleaned models face -Z and carry a 'headfront'
    // marker. Measure in the model's own space — world space would inherit the
    // yaw the stage group kept from the previously shown brawler.
    this.baseYaw = 0;
    const headB = model.getObjectByName('Head'), frontB = model.getObjectByName('headfront');
    if (headB && frontB) {
      const hp = new THREE.Vector3(), fp = new THREE.Vector3();
      headB.getWorldPosition(hp); model.worldToLocal(hp);
      frontB.getWorldPosition(fp); model.worldToLocal(fp);
      if (fp.z < hp.z) this.baseYaw = Math.PI;
    }
    this.group.rotation.y = this.baseYaw;
    this.mixer = new THREE.AnimationMixer(model);
    this.clips = gltf.animations;
    // Prefer the model's own baked, seam-free Idle; the procedural builder
    // stays as the fallback for models that ship without one.
    const baked = gltf.animations.find((a) => a.name === 'Idle');
    const idle = baked || buildIdleClip(model, gltf.animations, { stance: brawler.stance || 'relaxed', ...(brawler.idle || {}) });
    this.idleAction = this.mixer.clipAction(idle);
    this.idleAction.setLoop(THREE.LoopRepeat, Infinity);
    this.idleAction.play();
    this.current = this.idleAction;
    if (baked) {
      const accent = buildAccentClip(model, { ...(brawler.idle || {}) });
      if (accent) {
        THREE.AnimationUtils.makeClipAdditive(accent);
        this.accentAction = this.mixer.clipAction(accent);
        this.accentAction.blendMode = THREE.AdditiveAnimationBlendMode;
        this.accentAction.setEffectiveWeight(1).play();
      }
    }
    // baked clips
    this.actions = {};
    for (const clip of gltf.animations) {
      if (clip === idle) continue; // a baked Idle is this same action — leave it looping
      const a = this.mixer.clipAction(clip); a.setLoop(THREE.LoopOnce, 1); a.clampWhenFinished = false; this.actions[clip.name] = a;
    }
    this.mixer.addEventListener('finished', (e) => { if (e.action !== this.idleAction) this._toIdle(0.35); });
    // entrance pop
    this.group.scale.setScalar(0.001); this.popT = 0;
    this.rotY = 0; this.rotVel = 0;
    this.mixer.update(0.001);
  }

  clear() {
    if (this.model) { this.group.remove(this.model); this.model = null; }
    if (this.mixer) { this.mixer.stopAllAction(); this.mixer = null; }
    this.actions = {}; this.idleAction = null; this.accentAction = null; this.current = null;
  }

  _toIdle(fade = 0.3) {
    if (!this.idleAction) return;
    this.idleAction.reset().setEffectiveWeight(1).play();
    if (this.current && this.current !== this.idleAction) this.current.crossFadeTo(this.idleAction, fade, true);
    this.current = this.idleAction;
  }

  play(name, fade = 0.15) {
    const a = this.actions[name]; if (!a) return false;
    a.reset().setEffectiveWeight(1).play();
    if (this.current && this.current !== a) this.current.crossFadeTo(a, fade, true);
    this.current = a; return true;
  }

  tap() {
    if (!this.model) return;
    const list = (this.brawler.attackClips || []).filter((n) => this.actions[n]);
    if (this.current !== this.idleAction && this.current) return; // wait for current move
    if (list.length) { const n = list[Math.floor(Math.random() * list.length)]; this.play(n); }
    // squash & stretch punch
    this.squash = 1;
    this.opts.onTap && this.opts.onTap();
  }

  setVisible(v) { this.visible = v; }

  _loop() {
    if (this.disposed) return;
    requestAnimationFrame(this._loop);
    if (!this.visible || !this.model) return;
    const dt = Math.min(0.05, this.clock.getDelta());
    this.mixer && this.mixer.update(dt);
    // entrance pop
    if (this.popT < 1) { this.popT = Math.min(1, this.popT + dt * 3.2); const k = this.popT; const s = 1 + Math.sin(k * Math.PI) * 0.12 * (1 - k) + (k < 1 ? 0 : 0); this.group.scale.setScalar(0.001 + (1 - 0.001) * (1 - Math.pow(1 - k, 3)) * (1 + 0.15 * Math.sin(k * Math.PI))); }
    // squash on tap
    if (this.squash > 0) { this.squash = Math.max(0, this.squash - dt * 4); const q = Math.sin(this.squash * Math.PI) * 0.08; this.group.scale.set(1 + q, 1 - q, 1 + q); }
    // drag inertia + spring back
    if (!this.dragging) {
      this.rotY += this.rotVel * dt; this.rotVel *= Math.pow(0.02, dt);
      if (this.opts.autoReturn && performance.now() - this.lastDragT > 1200) {
        // wrap to nearest turn then spring home
        const target = Math.round(this.rotY / (Math.PI * 2)) * Math.PI * 2;
        this.rotY += (target - this.rotY) * Math.min(1, dt * 4);
      }
    }
    this.group.rotation.y = this.baseYaw + this.rotY;
    this.renderer.render(this.scene, this.camera);
  }

  dispose() {
    this.disposed = true; this.clear(); this._ro && this._ro.disconnect(); this.renderer.dispose();
  }
}
