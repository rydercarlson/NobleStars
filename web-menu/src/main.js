// Nobles Brawl — menu bootstrap

import { loadManifest, hydrate, slot, url, allImageSlots, preloadImages } from './assets.js';
import { state, save, on as onState } from './state.js';
import { $, $$, installPressFeedback, countTo, fmt, refreshCurrencies, toast, closeAllScreens, screenDepth } from './ui.js';
import { sfx, music } from './audio.js';
import { BrawlerView, preloadModel } from './brawler3d.js';
import * as screens from './screens/index.js';

export const game = { data: null, brawlers: null, view: null };

// ------------------------------------------------------------ stage scaling
const STAGE_H = 1080, MIN_W = 1920;
function fitStage() {
  const vw = window.innerWidth, vh = window.innerHeight;
  const scale = Math.min(vw / MIN_W, vh / STAGE_H);
  const stageW = Math.max(MIN_W, vw / scale);
  const st = $('#stage');
  st.style.setProperty('--stage-scale', scale);
  st.style.setProperty('--stage-w', stageW + 'px');
  st.style.width = stageW + 'px';
  positionBrawler();
  game.view && game.view.resize();
  game.detailView && game.detailView.resize();
}
window.addEventListener('resize', fitStage);

/** Place the 3D view so the brawler's feet sit on the stage floor of the background image. */
function positionBrawler() {
  const st = $('#stage'); const W = st.offsetWidth, H = STAGE_H;
  // background is cover-fitted 16:9
  const bgAspect = 1920 / 1080; let bw, bh, bx, by;
  if (W / H > bgAspect) { bw = W; bh = W / bgAspect; bx = 0; by = (H - bh) / 2; } else { bh = H; bw = H * bgAspect; bx = (W - bw) / 2; by = 0; }
  const floorY = by + bh * 0.715;          // stage floor line in the auditorium art
  const centerX = bx + bw * 0.5;
  const el = $('#brawler-view'); const vh = 760, vw = 900;
  el.style.width = vw + 'px'; el.style.height = vh + 'px';
  const footFrac = game.view ? game.view.footScreenY() : 0.885;
  el.style.left = centerX - vw / 2 + 'px';
  el.style.top = floorY - footFrac * vh + 'px';
  el.style.bottom = 'auto'; el.style.transform = 'none';
  const sh = el.querySelector('.shadow'); sh.style.bottom = (vh - footFrac * vh - 22) + 'px';
  const hint = el.querySelector('.tap-hint'); hint.style.bottom = (vh - footFrac * vh - 70) + 'px';
}

// ------------------------------------------------------------ boot
async function boot() {
  const bar = $('#load-bar'), tip = $('#load-tip');
  const setP = (p, t) => { bar.style.width = Math.round(p * 100) + '%'; if (t) tip.textContent = t; };
  setP(0.05, 'Loading assets…');
  await loadManifest();
  hydrate(document);
  const [brawlerData, gameData] = await Promise.all([fetch(url('data/brawlers.json')).then((r) => r.json()), fetch(url('data/game.json')).then((r) => r.json())]);
  game.brawlers = brawlerData; game.data = gameData;
  setP(0.15, 'Hanging the banners…');
  await preloadImages(allImageSlots(), (p) => setP(0.15 + p * 0.35));
  setP(0.5, 'Waking up the brawlers…');

  fitStage();
  installPressFeedback(document);
  wireHome();
  renderHome();

  // 3D
  const canvas = $('#brawler-view canvas');
  game.view = new BrawlerView(canvas, { fov: 22, fill: 0.72, lookY: 0.5, onTap: () => { sfx('hit'); hideHint(); } });
  positionBrawler(); game.view.resize();
  const b = currentBrawler();
  try { await game.view.load(b); } catch (e) { console.error('model load failed', e); }
  setP(0.9, 'Tuning the piano…');
  // warm the rest of the roster in the background
  game.brawlers.brawlers.forEach((br) => preloadModel(br.model).catch(() => {}));

  setP(1, 'Ready!');
  await new Promise((r) => setTimeout(r, 250));
  $('#loader').classList.add('done');
  $('#home').classList.add('intro');
  setTimeout(() => { $('#loader').remove(); $('#home').classList.remove('intro'); }, 1200);

  if (state.settings.hints && state.firstRun) { showHint(); }
  if (state.settings.music) { const start = () => { music(true); window.removeEventListener('pointerdown', start); }; window.addEventListener('pointerdown', start); }

  // keyboard: Esc closes
  window.addEventListener('keydown', (e) => { if (e.key === 'Escape' && screenDepth()) { sfx('back'); closeAllScreens(); } });
}

export function currentBrawler() {
  return game.brawlers.brawlers.find((b) => b.id === state.selectedBrawler) || game.brawlers.brawlers[0];
}
export function currentMode() {
  return game.data.modes.find((m) => m.id === state.selectedMode) || game.data.modes[0];
}

function showHint() { $('#brawler-view').classList.add('show-hint'); }
function hideHint() { $('#brawler-view').classList.remove('show-hint'); if (state.firstRun) { state.firstRun = false; save(); } }

// ------------------------------------------------------------ home
function wireHome() {
  document.addEventListener('click', (e) => {
    const b = e.target.closest('[data-open]'); if (!b) return;
    const name = b.dataset.open;
    if (screens[name]) screens[name]();
  });
  $('#profile-btn').addEventListener('click', () => screens.profile());
  $('#season-btn').addEventListener('click', () => screens.pass());
  $('#play-btn').addEventListener('click', () => screens.matchmaking());
  onState('currency', () => refreshCurrencies());
  onState('profile', () => renderHome());
  onState('brawler', async () => { const b = currentBrawler(); await game.view.load(b); positionBrawler(); });
  onState('mode', () => renderHome());
  document.addEventListener('screen', (e) => { if (game.view) game.view.setVisible(screenDepth() === 0); if (screenDepth()) hideHint(); });
}

export function renderHome() {
  const d = game.data;
  $('#player-name').textContent = state.name;
  countTo($('#player-trophies'), state.trophies);
  refreshCurrencies();
  $('#season-l1').textContent = 'SEASON ' + d.season.number;
  $('#season-l2').textContent = d.season.name;
  requestAnimationFrame(() => { $('#season-progress').style.width = Math.round((state.passTokens / d.season.tokensPerTier) * 100) + '%'; });
  const m = currentMode();
  $('#mode-name').textContent = m.name; $('#mode-sub').textContent = m.sub; $('#mode-sub').style.color = m.color;
  $('#mode-icon').src = slot('icons.' + m.icon);
  $('#mode-btn .tab').style.background = `linear-gradient(180deg, ${lighten(m.color)}, ${m.color} 30%, ${m.color} 70%, ${darken(m.color)})`;
  const unread = d.inbox.filter((x) => x.unread && !state.readMail[x.id]).length;
  $('#inbox-dot').classList.toggle('hidden', !unread); $('#inbox-dot').textContent = unread;
  const online = d.friends.filter((f) => f.status === 'online').length;
  $('#friends-dot').classList.toggle('hidden', !online); $('#friends-dot').textContent = online; $('#friends-dot').style.background = 'var(--green)';
}

export function lighten(hex, k = 0.35) { const [r, g, b] = rgb(hex); return `rgb(${m(r, k)},${m(g, k)},${m(b, k)})`; }
export function darken(hex, k = 0.45) { const [r, g, b] = rgb(hex); return `rgb(${Math.round(r * (1 - k))},${Math.round(g * (1 - k))},${Math.round(b * (1 - k))})`; }
const m = (v, k) => Math.round(v + (255 - v) * k);
function rgb(hex) { const n = parseInt(hex.slice(1), 16); return [(n >> 16) & 255, (n >> 8) & 255, n & 255]; }

boot().catch((e) => { console.error(e); $('#load-tip').textContent = 'Something broke while loading: ' + e.message; });
