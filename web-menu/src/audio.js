// Tiny WebAudio SFX engine. Every sound is synthesized so the menu ships with zero
// audio files; drop a path into manifest.json -> audio.<name> to override a sound.

import { getManifest, url } from './assets.js';
import { state } from './state.js';

let ctx = null;
const buffers = {};

function ac() {
  if (!ctx) ctx = new (window.AudioContext || window.webkitAudioContext)();
  if (ctx.state === 'suspended') ctx.resume();
  return ctx;
}

// unlock on first gesture
['pointerdown', 'keydown', 'touchstart'].forEach((ev) => window.addEventListener(ev, () => ac(), { once: true, passive: true }));

function env(g, t, a, d, s = 0.0001) {
  g.gain.setValueAtTime(0.0001, t);
  g.gain.exponentialRampToValueAtTime(1, t + a);
  g.gain.exponentialRampToValueAtTime(s, t + a + d);
}

const synth = {
  click(c, t, out) { // short bright pop
    const o = c.createOscillator(); const g = c.createGain();
    o.type = 'triangle'; o.frequency.setValueAtTime(720, t); o.frequency.exponentialRampToValueAtTime(380, t + 0.08);
    env(g, t, 0.004, 0.09); o.connect(g).connect(out); o.start(t); o.stop(t + 0.12);
    const n = c.createBufferSource(); n.buffer = noise(c, 0.04); const ng = c.createGain(); ng.gain.value = 0.25; env(ng, t, 0.002, 0.03);
    n.connect(ng).connect(out); n.start(t);
  },
  back(c, t, out) {
    const o = c.createOscillator(); const g = c.createGain();
    o.type = 'triangle'; o.frequency.setValueAtTime(420, t); o.frequency.exponentialRampToValueAtTime(220, t + 0.12);
    env(g, t, 0.004, 0.12); o.connect(g).connect(out); o.start(t); o.stop(t + 0.16);
  },
  open(c, t, out) { // whoosh + ding
    const n = c.createBufferSource(); n.buffer = noise(c, 0.25); const f = c.createBiquadFilter(); f.type = 'bandpass'; f.frequency.setValueAtTime(600, t); f.frequency.exponentialRampToValueAtTime(2400, t + 0.2); f.Q.value = 1.2;
    const ng = c.createGain(); env(ng, t, 0.02, 0.2, 0.001); ng.gain.value = 0.5; n.connect(f).connect(ng).connect(out); n.start(t);
    const o = c.createOscillator(); const g = c.createGain(); o.type = 'sine'; o.frequency.value = 1046; env(g, t + 0.08, 0.005, 0.25); g.gain.value = 0.35; o.connect(g).connect(out); o.start(t + 0.08); o.stop(t + 0.45);
  },
  purchase(c, t, out) { // coin jingle
    [880, 1174, 1568].forEach((fq, i) => {
      const o = c.createOscillator(); const g = c.createGain(); o.type = 'square'; o.frequency.value = fq;
      env(g, t + i * 0.07, 0.004, 0.18); g.gain.value = 0.18; o.connect(g).connect(out); o.start(t + i * 0.07); o.stop(t + i * 0.07 + 0.25);
    });
  },
  error(c, t, out) {
    const o = c.createOscillator(); const g = c.createGain(); o.type = 'sawtooth'; o.frequency.setValueAtTime(220, t); o.frequency.linearRampToValueAtTime(160, t + 0.18);
    env(g, t, 0.005, 0.2); g.gain.value = 0.25; o.connect(g).connect(out); o.start(t); o.stop(t + 0.24);
  },
  play(c, t, out) { // big confident hit
    const o = c.createOscillator(); const g = c.createGain(); o.type = 'sawtooth'; o.frequency.setValueAtTime(140, t); o.frequency.exponentialRampToValueAtTime(70, t + 0.25);
    const f = c.createBiquadFilter(); f.type = 'lowpass'; f.frequency.setValueAtTime(1800, t); f.frequency.exponentialRampToValueAtTime(300, t + 0.3);
    env(g, t, 0.006, 0.3); g.gain.value = 0.6; o.connect(f).connect(g).connect(out); o.start(t); o.stop(t + 0.35);
    [523, 659, 784, 1046].forEach((fq, i) => { const s = c.createOscillator(); const sg = c.createGain(); s.type = 'triangle'; s.frequency.value = fq; env(sg, t + 0.05 + i * 0.05, 0.005, 0.3); sg.gain.value = 0.2; s.connect(sg).connect(out); s.start(t + 0.05 + i * 0.05); s.stop(t + 0.6); });
  },
  hit(c, t, out) { // brawler tap: thump
    const o = c.createOscillator(); const g = c.createGain(); o.type = 'sine'; o.frequency.setValueAtTime(180, t); o.frequency.exponentialRampToValueAtTime(50, t + 0.18);
    env(g, t, 0.004, 0.2); g.gain.value = 0.8; o.connect(g).connect(out); o.start(t); o.stop(t + 0.25);
    const n = c.createBufferSource(); n.buffer = noise(c, 0.08); const ng = c.createGain(); env(ng, t, 0.002, 0.07); ng.gain.value = 0.3; n.connect(ng).connect(out); n.start(t);
  },
  reward(c, t, out) { // sparkle arpeggio
    [659, 784, 988, 1318, 1568].forEach((fq, i) => { const o = c.createOscillator(); const g = c.createGain(); o.type = 'sine'; o.frequency.value = fq; env(g, t + i * 0.06, 0.004, 0.35); g.gain.value = 0.22; o.connect(g).connect(out); o.start(t + i * 0.06); o.stop(t + i * 0.06 + 0.4); });
  },
  tick(c, t, out) {
    const o = c.createOscillator(); const g = c.createGain(); o.type = 'square'; o.frequency.value = 1500; env(g, t, 0.002, 0.03); g.gain.value = 0.08; o.connect(g).connect(out); o.start(t); o.stop(t + 0.05);
  },
  found(c, t, out) { // match found fanfare
    [[392, 0], [523, 0.12], [659, 0.24], [784, 0.36], [1046, 0.5]].forEach(([fq, d]) => { const o = c.createOscillator(); const g = c.createGain(); o.type = 'square'; o.frequency.value = fq; env(g, t + d, 0.005, 0.28); g.gain.value = 0.16; o.connect(g).connect(out); o.start(t + d); o.stop(t + d + 0.35); });
  },
};

function noise(c, dur) {
  const b = c.createBuffer(1, Math.floor(c.sampleRate * dur), c.sampleRate);
  const d = b.getChannelData(0); for (let i = 0; i < d.length; i++) d[i] = Math.random() * 2 - 1;
  return b;
}

let master = null;
function out() {
  const c = ac();
  if (!master) { master = c.createGain(); master.connect(c.destination); }
  master.gain.value = state.settings.sfx ? 0.55 : 0;
  return master;
}

async function fileBuffer(name) {
  const path = getManifest()?.audio?.[name];
  if (!path) return null;
  if (buffers[name] !== undefined) return buffers[name];
  try {
    const res = await fetch(url(path)); const arr = await res.arrayBuffer();
    buffers[name] = await ac().decodeAudioData(arr);
  } catch (e) { buffers[name] = null; }
  return buffers[name];
}

export function sfx(name = 'click') {
  if (!state.settings.sfx) return;
  try {
    const c = ac(); const o = out(); const t = c.currentTime;
    fileBuffer(name).then((buf) => {
      if (buf) { const s = c.createBufferSource(); s.buffer = buf; s.connect(o); s.start(); }
      else (synth[name] || synth.click)(c, c.currentTime, o);
    });
  } catch (e) { /* audio unavailable */ }
}

// ---- background music: gentle synthesized loop (replace via manifest audio.music) ----
let musicNodes = null;
export function music(on) {
  try {
    const c = ac();
    if (!on) { if (musicNodes) { musicNodes.gain.gain.linearRampToValueAtTime(0.0001, c.currentTime + 0.4); const n = musicNodes; setTimeout(() => n.stop(), 500); musicNodes = null; } return; }
    if (musicNodes) return;
    const path = getManifest()?.audio?.music;
    const gain = c.createGain(); gain.gain.value = 0.0001; gain.connect(c.destination);
    gain.gain.linearRampToValueAtTime(0.18, c.currentTime + 1.2);
    if (path) {
      fileBuffer('music').then((buf) => { if (!buf || !musicNodes) return; const s = c.createBufferSource(); s.buffer = buf; s.loop = true; s.connect(gain); s.start(); musicNodes.src = s; });
      musicNodes = { gain, stop() { try { this.src?.stop(); } catch (e) {} gain.disconnect(); } };
      return;
    }
    // procedural: slow major-key pad with a pulsing bass, Brawl-lobby-ish energy without being loud
    const chords = [[261.6, 329.6, 392.0], [293.7, 349.2, 440.0], [329.6, 392.0, 493.9], [349.2, 440.0, 523.3]];
    const oscs = []; let bar = 0; let timer = null;
    const lp = c.createBiquadFilter(); lp.type = 'lowpass'; lp.frequency.value = 900; lp.connect(gain);
    const step = () => {
      const t = c.currentTime; const ch = chords[bar % chords.length]; bar++;
      ch.forEach((f) => { const o = c.createOscillator(); const g = c.createGain(); o.type = 'sawtooth'; o.frequency.value = f; g.gain.setValueAtTime(0.0001, t); g.gain.exponentialRampToValueAtTime(0.09, t + 0.4); g.gain.exponentialRampToValueAtTime(0.0001, t + 2.4); o.connect(g).connect(lp); o.start(t); o.stop(t + 2.5); });
      for (let i = 0; i < 4; i++) { const b = c.createOscillator(); const bg = c.createGain(); b.type = 'square'; b.frequency.value = ch[0] / 2; bg.gain.setValueAtTime(0.0001, t + i * 0.6); bg.gain.exponentialRampToValueAtTime(0.12, t + i * 0.6 + 0.02); bg.gain.exponentialRampToValueAtTime(0.0001, t + i * 0.6 + 0.3); b.connect(bg).connect(lp); b.start(t + i * 0.6); b.stop(t + i * 0.6 + 0.35); }
    };
    step(); timer = setInterval(step, 2400);
    musicNodes = { gain, stop() { clearInterval(timer); gain.disconnect(); } };
  } catch (e) { /* no audio */ }
}
