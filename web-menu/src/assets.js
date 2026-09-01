// Asset manifest: every image/model/font the menu uses is addressed by a slot
// ("buttons.play", "icons.trophy"...) and resolved through assets/manifest.json.
// Swap a file in the manifest and every <img data-slot> and CSS lookup follows.

let manifest = null;
// project root: src/../ when served as modules; the document folder when bundled into one file
const base = (() => { try { if (import.meta.url) return new URL('..', import.meta.url); } catch (e) { /* bundled */ } return new URL('./', location.href); })();
// single-file builds (tools/build-single.mjs) pre-embed every asset as a data: URL here
const embedded = (typeof window !== 'undefined' && window.__NB_ASSETS) || null;

export async function loadManifest() {
  const res = await fetch(url('assets/manifest.json'));
  manifest = await res.json();
  return manifest;
}

export function slot(path) {
  if (!manifest) throw new Error('manifest not loaded');
  const [group, key] = path.split('.');
  const v = manifest[group]?.[key];
  if (v == null) { console.warn('[assets] missing slot', path); return ''; }
  return v ? url(v) : '';
}

export function url(relative) {
  if (embedded && embedded[relative]) return embedded[relative];
  return new URL(relative, base).href;
}

/** Fill every <img data-slot="..."> inside root. */
export function hydrate(root = document) {
  root.querySelectorAll('img[data-slot]').forEach((img) => {
    const src = slot(img.dataset.slot);
    if (src) img.src = src;
  });
}

/** Preload a list of image URLs, calling onProgress(0..1). */
export function preloadImages(urls, onProgress = () => {}) {
  let done = 0;
  return Promise.all(urls.map((u) => new Promise((resolve) => {
    const img = new Image();
    img.onload = img.onerror = () => { done++; onProgress(done / urls.length); resolve(); };
    img.src = u;
  })));
}

export function allImageSlots() {
  const out = [];
  for (const g of ['buttons', 'icons']) for (const k in manifest[g] || {}) { const v = manifest[g][k]; if (v) out.push(url(v)); }
  return out;
}

export function getManifest() { return manifest; }
