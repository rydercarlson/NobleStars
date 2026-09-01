// TROPHY ROAD + QUESTS + MENU DRAWER (account, controls, game log, leaderboard)

import { h, icon, fmt, openScreen, topbar, toast, stagger, burst, centerOf, drawer, popup, confirm } from '../ui.js';
import { state, save, emit, addCurrency, resetSave } from '../state.js';
import { url } from '../assets.js';
import { game, renderHome } from '../main.js';
import { sfx, music } from '../audio.js';
import { openStarDrop } from './shop.js';
import { settings, profile } from './settings.js';

const kindIcon = { coins: 'coin', gems: 'gem', power_points: 'power_point', dawg_treat: 'dawg_treat', bling: 'bling', tokens: 'token', pin: 'token' };
const kindLabel = { coins: 'Coins', gems: 'Gems', power_points: 'Power Points', dawg_treat: 'Dawg Treat', bling: 'Bling', tokens: 'Tokens' };

function giveReward(r, at) {
  if (r.kind === 'brawler') { state.unlocked[r.id] = true; save(); emit('profile'); const b = game.brawlers.brawlers.find((x) => x.id === r.id); toast(`Unlocked ${b.name}!`, { iconName: 'brawlers' }); }
  else if (r.kind === 'dawg_treat') { for (let i = 0; i < r.amount; i++) setTimeout(() => openStarDrop(), 300 + i * 120); }
  else { addCurrency(r.kind, r.amount); toast(`+${fmt(r.amount)} ${kindLabel[r.kind] || r.kind}`, { iconName: kindIcon[r.kind] || 'token' }); }
  if (at) burst(at.x, at.y, kindIcon[r.kind] || 'star_points', 14);
  sfx('reward');
}

// ---------------------------------------------------------------- trophy road
export function trophyRoad() {
  openScreen((el, api) => {
    const road = game.data.trophyRoad;
    el.append(topbar(api, 'Trophy Road', { sub: `${fmt(state.trophies)} trophies` }));
    const content = h('div.content');
    content.append(h('div.section-h', {}, 'Milestones', h('span.n', {}, 'Every milestone you pass unlocks a reward — tap to claim')));
    const strip = h('div.road'); const track = h('div.track', h('i')); strip.append(track);
    road.forEach((ms, i) => {
      const reached = state.trophies >= ms.trophies; const id = 'road:' + ms.trophies; const claimed = !!state.claimed[id];
      const r = ms.reward; const b = r.kind === 'brawler' ? game.brawlers.brawlers.find((x) => x.id === r.id) : null;
      const cell = h('div.reward.card' + (claimed ? '.claimed' : reached ? '.claimable' : '.locked') + (b ? '.portrait' : ''),
        b ? h('img', { src: url(b.art) }) : icon(kindIcon[r.kind] || 'token'),
        r.amount ? h('div.amt.t.outline.hair', {}, 'x' + r.amount) : null,
        h('div.nm', {}, b ? 'NEW BRAWLER: ' + b.name : kindLabel[r.kind] || r.kind));
      if (reached && !claimed) cell.addEventListener('click', () => { state.claimed[id] = true; save(); giveReward(r, centerOf(cell)); cell.classList.replace('claimable', 'claimed'); renderHome(); });
      const col = h('div.ms' + (reached ? '.reached' : ''), h('div.pin'), h('div.tro', icon('trophy'), fmt(ms.trophies)), cell);
      if (!reached && (i === 0 || state.trophies >= road[i - 1].trophies)) col.append(h('div.you', {}, `YOU · ${fmt(state.trophies)}`));
      strip.append(col);
    });
    content.append(strip);
    requestAnimationFrame(() => {
      const idx = road.findIndex((r) => r.trophies > state.trophies); const n = road.length;
      const frac = idx < 0 ? 1 : (idx + (state.trophies - (idx ? road[idx - 1].trophies : 0)) / (road[idx].trophies - (idx ? road[idx - 1].trophies : 0))) / n;
      track.querySelector('i').style.width = Math.round(frac * 100) + '%';
      const cur = strip.querySelector('.ms:not(.reached)'); if (cur) strip.scrollLeft = Math.max(0, cur.offsetLeft - 500);
    });
    strip.addEventListener('wheel', (e) => { strip.scrollLeft += e.deltaY; e.preventDefault(); }, { passive: false });
    el.append(content);
  }, { name: 'trophy-road' });
}

// ---------------------------------------------------------------- quests
export function quests() {
  openScreen((el, api) => {
    el.append(topbar(api, 'Quests', { sub: 'Season 1' }));
    const content = h('div.content.scroll'); questList(content, api); el.append(content);
  }, { name: 'quests' });
}

/** Renders the tabbed quest list into `container` (used by the Quests screen and the Pass QUESTS tab). */
export function questList(container, api) {
  const q = game.data.quests;
  const tabs = [['daily', 'DAILY'], ['seasonal', 'SEASONAL'], ['special', 'SPECIAL EVENT']];
  let cur = 'daily';
  const bar = h('div.quest-tabs'); const list = h('div.list');
  const render = () => {
    bar.querySelectorAll('.tab-btn').forEach((b) => b.classList.toggle('on', b.dataset.id === cur));
    list.replaceChildren();
    for (const qu of q[cur]) {
      const done = qu.progress >= qu.goal; const claimed = !!state.claimed['quest:' + qu.id];
      const b = qu.brawler ? game.brawlers.brawlers.find((x) => x.id === qu.brawler) : null;
      const row = h('div.plate.row.quest' + (done && !claimed ? '.done' : ''),
        h('div.qi' + (b ? '.portrait' : ''), b ? h('img', { src: url(b.art) }) : icon(cur === 'special' ? 'shield' : 'quests')),
        h('div.qt', h('div.ttl.t', {}, qu.title), h('div.bar', h('i', { style: { width: Math.min(100, (qu.progress / qu.goal) * 100) + '%' } }), h('span', {}, `${fmt(Math.min(qu.progress, qu.goal))} / ${fmt(qu.goal)}`))),
        h('div.rw', icon(kindIcon[qu.reward.kind] || 'token'), fmt(qu.reward.amount)),
        claimed ? h('button.btn.small.grey.disabled', {}, 'CLAIMED') : done ? h('button.btn.small.green', { onClick: (e) => { state.claimed['quest:' + qu.id] = true; save(); giveReward(qu.reward, centerOf(e.currentTarget)); renderHome(); render(); } }, 'CLAIM') : h('button.btn.small.grey.disabled', {}, 'IN PROGRESS'));
      list.append(row);
    }
    stagger(list, 45);
  };
  for (const [id, label] of tabs) bar.append(h('button.tab-btn', { dataset: { id }, onClick: () => { cur = id; render(); } }, label));
  render(); container.append(bar, list);
}

// ---------------------------------------------------------------- menu drawer
export function menu() {
  drawer('Menu', (body, api) => {
    const item = (ic, t, s, fn) => h('div.menu-item', { onClick: () => { sfx('click'); fn(); } }, icon(ic), h('div', h('div.mi-t.t', {}, t), h('div.mi-s', {}, s)), h('div.chev', {}, '›'));
    body.append(
      item('shield', 'Account', `${state.name} · Level ${state.level}`, () => { api.close(); profile(); }),
      item('settings_gear', 'Settings', 'Music, sound, hints, reset', () => { api.close(); settings(); }),
      item('gadget', 'Controls', 'Joystick size, auto-aim, button layout', () => { api.close(); controls(); }),
      item('quests', 'Game Log', 'Your recent matches', () => { api.close(); gameLog(); }),
      item('trophy', 'Leaderboard', 'Top players in Castle Crew and the school', () => { api.close(); leaderboard(); }),
      item('inbox', 'Support', 'Nobles Brawl · menu prototype v0.5', () => toast('Support: message the dev', { iconName: 'inbox' })),
    );
    body.append(h('div', { style: { marginTop: 'auto', font: '800 16px var(--font-body)', color: 'var(--text-dim)', textAlign: 'center' } }, 'Noble and Greenough School · Dedham, MA · "Where Today and Tomorrow Meet"'));
  }, { name: 'menu' });
}

function controls() {
  popup('Controls', (body, api) => {
    const s = state.settings;
    const row = (label, hint, key, opts) => {
      const v = s[key] ?? opts[0];
      const seg = h('div', { style: { display: 'flex', gap: '6px' } });
      opts.forEach((o) => seg.append(h('button.btn.small' + (v === o ? '.blue' : '.grey'), { onClick: () => { s[key] = o; save(); api.close(); controls(); } }, String(o).toUpperCase())));
      return h('div.setting', h('div', h('div.lbl.t', {}, label), h('div.hint', {}, hint)), seg);
    };
    body.append(row('Joystick', 'Left-hand movement stick', 'joystick', ['fixed', 'floating']), row('Auto-aim', 'Tap to fire at the nearest target', 'autoaim', ['on', 'off']), row('Button size', 'Attack / super / gadget buttons', 'btnsize', ['small', 'medium', 'large']), row('Haptics', 'Vibration on hits', 'haptics', ['on', 'off']));
  }, { name: 'controls' });
}

function gameLog() {
  openScreen((el, api) => {
    el.append(topbar(api, 'Game Log', { sub: 'recent matches' }));
    const content = h('div.content.scroll'); const list = h('div.list');
    for (const g of game.data.gameLog) {
      const b = game.brawlers.brawlers.find((x) => x.id === g.brawler) || game.brawlers.brawlers[0];
      const cls = g.result === 'Victory' ? 'win' : g.result === 'Defeat' ? 'loss' : 'rank';
      list.append(h('div.plate.row', h('div.avatar', h('img', { src: url(b.art) })), h('div.who', h('div.n.t', {}, `${g.mode} · ${g.map}`), h('div.s', {}, `${b.name} · ${g.ago}`)),
        h('div.log-res.t.outline.hair.' + cls, {}, g.result.toUpperCase()), h('div.tr', icon('trophy'), (g.trophies >= 0 ? '+' : '') + g.trophies)));
    }
    stagger(list, 50); content.append(list); el.append(content);
  }, { name: 'gamelog' });
}

function leaderboard() {
  openScreen((el, api) => {
    el.append(topbar(api, 'Leaderboard', { sub: 'Nobles · this season' }));
    const content = h('div.content.scroll'); const list = h('div.list');
    const rows = [...game.data.leaderboard, { name: state.name, trophies: state.trophies, brawler: state.selectedBrawler, me: true }].sort((a, b) => b.trophies - a.trophies);
    rows.forEach((r, i) => {
      const b = game.brawlers.brawlers.find((x) => x.id === r.brawler) || game.brawlers.brawlers[0];
      list.append(h('div.plate.row' + (r.me ? '.me' : ''), h('div.rank-n' + (i < 3 ? '.top' : ''), {}, '#' + (i + 1)), h('div.avatar', h('img', { src: url(b.art) })), h('div.who', h('div.n.t', {}, r.name), h('div.s', {}, b.name)), h('div.tr', icon('trophy'), fmt(r.trophies))));
    });
    stagger(list, 40); content.append(list); el.append(content);
  }, { name: 'leaderboard' });
}
