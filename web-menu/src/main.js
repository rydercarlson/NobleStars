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
  const bar = $('#load-bar'), tip = $('#load-tip'), pct = $('#load-pct');
  const setP = (p, t) => { bar.style.width = Math.round(p * 100) + '%'; pct.textContent = Math.round(p * 100) + '%'; if (t) tip.innerHTML = t; };
  setP(0.05, 'Loading assets…');
  await loadManifest();
  hydrate(document);
  // loading screen art (optional slots — falls back to the auditorium + text logo)
  const art = slot('background.loading_keyart'); const logo = slot('decor.logo');
  await new Promise((res) => { const im = new Image(); im.onload = () => { $('#loader-art').style.backgroundImage = `url(${art})`; res(); }; im.onerror = () => { $('#loader-art').style.backgroundImage = `url(${slot('background.auditorium')})`; res(); }; im.src = art; });
  await new Promise((res) => { const im = new Image(); im.onload = () => { $('#loader-logo').src = logo; $('#loader').classList.add('has-logo'); res(); }; im.onerror = res; im.src = logo; });
  const tips = ['<b>TIP:</b> Tap your brawler on stage to see their attack.', '<b>TIP:</b> Drag the brawler to spin them around.', '<b>TIP:</b> Dawg Treats can unlock new brawlers.', '<b>TIP:</b> The Nobles Pass fills up with tokens from every match.', '<b>TIP:</b> Invite a friend from the + slots to team up.'];
  let tipI = Math.floor(Math.random() * tips.length); tip.innerHTML = tips[tipI];
  const tipTimer = setInterval(() => { tipI = (tipI + 1) % tips.length; tip.innerHTML = tips[tipI]; }, 2600);
  const [brawlerData, gameData] = await Promise.all([fetch(url('data/brawlers.json')).then((r) => r.json()), fetch(url('data/game.json')).then((r) => r.json())]);
  game.brawlers = brawlerData; game.data = gameData;
  // resolve optional 2D card art (falls back to the rendered 3D portrait when a card is missing)
  await Promise.all(game.brawlers.brawlers.map((b) => new Promise((res) => { if (!b.cardArt) return res(); const im = new Image(); im.onload = res; im.onerror = () => { b.cardArt = null; res(); }; im.src = url(b.cardArt); })));
  game.brawlers.brawlers.forEach((b) => { b.art = b.cardArt || b.portrait; });
  // optional full-body art for the season pass hero card + skin offers
  game.passHero = null; game.skinArt = {};
  await Promise.all([['pass_hero', (u) => { game.passHero = u; }], ['skin_tony_fieldday', (u) => { game.skinArt['Field Day Tony'] = u; }], ['skin_leon_homecoming', (u) => { game.skinArt['Homecoming Leon'] = u; }]].map(([k, set]) => new Promise((res) => { const im = new Image(); const u = url(`assets/ui/decor/${k}.webp`); im.onload = () => { set(u); res(); }; im.onerror = res; im.src = u; })));
  setP(0.15);
  await preloadImages(allImageSlots(), (p) => setP(0.15 + p * 0.35));
  setP(0.5);

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
  setP(0.9);
  // warm the rest of the roster in the background
  game.brawlers.brawlers.forEach((br) => preloadModel(br.model).catch(() => {}));

  setP(1);
  clearInterval(tipTimer);
  await new Promise((r) => setTimeout(r, 350));
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

export function inviteFriend(f, slotN = '1') {
  if (!f) return;
  state['team' + slotN] = f.id; save(); sfx('reward');
  toast(`${f.name} joined your team!`, { iconName: 'friends' });
  renderHome();
}
function leaveSlot(n) { state['team' + n] = null; save(); sfx('back'); renderHome(); }
export function renderTeam() {
  const d = game.data;
  $$('.slot-btn').forEach((b) => {
    const id = state['team' + b.dataset.team]; const f = id && d.friends.find((x) => x.id === id);
    b.classList.toggle('filled', !!f);
    if (f) { const br = game.brawlers.brawlers.find((x) => x.id === f.brawler) || game.brawlers.brawlers[0]; b.innerHTML = `<img src="${url(br.art)}" alt=""><em>${f.name}</em>`; }
    else b.innerHTML = '<span>+</span>';
  });
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
  $('#play-btn').addEventListener('click', () => screens.matchmaking());
  $('#cancel-btn').addEventListener('click', () => screens.cancelSearch());
  onState('currency', () => { refreshCurrencies(); countTo($('#cur-pp'), state.powerPoints); countTo($('#cur-bling'), state.bling); });
  onState('profile', () => renderHome());
  onState('brawler', async () => { const b = currentBrawler(); await game.view.load(b); positionBrawler(); });
  onState('mode', () => renderHome());
  $('#friend-bubble').addEventListener('click', () => inviteFriend(game.data.friends.find((f) => f.status === 'online')));
  $$('.slot-btn').forEach((b) => b.addEventListener('click', () => { if (state['team' + b.dataset.team]) { leaveSlot(b.dataset.team); } else screens.teamInvite(b.dataset.team); }));
  game.loadedAt = Date.now();
  tickTimers(); setInterval(tickTimers, 30000);
  document.addEventListener('screen', (e) => { if (game.view) game.view.setVisible(screenDepth() === 0); if (screenDepth()) hideHint(); });
}

export function renderHome() {
  const d = game.data;
  $('#player-name').textContent = state.name;
  countTo($('#player-trophies'), state.trophies);
  refreshCurrencies();
  countTo($('#cur-pp'), state.powerPoints); countTo($('#cur-bling'), state.bling);
  $('#player-level').textContent = 'LVL ' + state.level;
  requestAnimationFrame(() => { $('#player-xp').style.width = Math.round(((state.trophies % 250) / 250) * 100) + '%'; });
  // trophy road progress
  const next = d.trophyRoad.find((r) => r.trophies > state.trophies); const prev = [...d.trophyRoad].reverse().find((r) => r.trophies <= state.trophies);
  const lo = prev ? prev.trophies : 0, hi = next ? next.trophies : state.trophies;
  requestAnimationFrame(() => { $('#trophy-progress').style.width = Math.round(((state.trophies - lo) / Math.max(1, hi - lo)) * 100) + '%'; });
  $('#trophy-next').textContent = next ? `next reward: ${fmt(next.trophies)}` : 'Trophy Road complete!';
  // mode plate
  const m = currentMode();
  $('#mode-name').textContent = m.name; $('#mode-sub').textContent = m.sub; $('#mode-sub').style.color = m.color;
  $('#mode-icon').src = slot('icons.' + m.icon);
  $('#mode-btn .tab').style.background = `linear-gradient(180deg, ${lighten(m.color)}, ${m.color} 30%, ${m.color} 70%, ${darken(m.color)})`;
  // badges
  const unread = d.inbox.filter((x) => x.unread && !state.readMail[x.id]).length;
  $('#inbox-dot').classList.toggle('hidden', !unread); $('#inbox-dot').textContent = unread;
  const online = d.friends.filter((f) => f.status === 'online').length;
  $('#friends-dot').classList.toggle('hidden', !online); $('#friends-dot').textContent = online; $('#friends-dot').style.background = 'var(--green)';
  const claimableQ = Object.values(d.quests).flat().filter((q) => q.progress >= q.goal && !state.claimed['quest:' + q.id]).length;
  $('#quests-dot').classList.toggle('hidden', !claimableQ); $('#quests-dot').textContent = claimableQ;
  const passClaimable = d.passRewards.some((t) => t.tier <= state.passTier && (!state.claimed[`pass:${t.tier}:free`] || (state.passPremium && !state.claimed[`pass:${t.tier}:premium`])));
  $('#pass-dot').classList.toggle('hidden', !passClaimable); $$('.side-btn.pass').forEach((b) => b.classList.toggle('glow', passClaimable));
  // friend bubble + team
  const onlineFriend = d.friends.find((f) => f.status === 'online' && f.id !== state.team1 && f.id !== state.team2);
  $('#friend-bubble').classList.toggle('hidden', !onlineFriend || !!state.team1);
  if (onlineFriend) $('#friend-bubble-name').textContent = onlineFriend.name;
  renderTeam();
}

/** Countdown helpers: event rotation + shop reset, ticking every 30s. */
function fmtCountdown(sec) { sec = Math.max(0, sec); const h = Math.floor(sec / 3600), mi = Math.floor((sec % 3600) / 60); return h > 48 ? `${Math.floor(h / 24)}d ${h % 24}h` : `${h}h ${mi}m`; }
export function eventEndsIn(mode) { const t0 = game.loadedAt || Date.now(); return (mode.endsInMin || 60) * 60 - Math.floor((Date.now() - t0) / 1000); }
export function eventStartsIn(ev) { const t0 = game.loadedAt || Date.now(); return (ev.startsInMin || 60) * 60 - Math.floor((Date.now() - t0) / 1000); }
export { fmtCountdown };
function tickTimers() {
  const m = currentMode(); $('#event-timer').textContent = 'Ends in ' + fmtCountdown(eventEndsIn(m));
  const now = new Date(); const end = new Date(now); end.setHours(24, 0, 0, 0); $('#shop-timer').textContent = fmtCountdown((end - now) / 1000);
}

export function lighten(hex, k = 0.35) { const [r, g, b] = rgb(hex); return `rgb(${m(r, k)},${m(g, k)},${m(b, k)})`; }
export function darken(hex, k = 0.45) { const [r, g, b] = rgb(hex); return `rgb(${Math.round(r * (1 - k))},${Math.round(g * (1 - k))},${Math.round(b * (1 - k))})`; }
const m = (v, k) => Math.round(v + (255 - v) * k);
function rgb(hex) { const n = parseInt(hex.slice(1), 16); return [(n >> 16) & 255, (n >> 8) & 255, n & 255]; }

boot().catch((e) => { console.error(e); $('#load-tip').textContent = 'Something broke while loading: ' + e.message; });
