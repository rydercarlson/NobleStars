// MODE SELECT + MATCHMAKING (lobby -> searching -> match found -> Godot)

import { h, icon, openScreen, topbar, toast, stagger } from '../ui.js';
import { state, save, emit } from '../state.js';
import { url } from '../assets.js';
import { game, currentBrawler, currentMode, lighten } from '../main.js';
import { sfx } from '../audio.js';

export function modes() {
  openScreen((el, api) => {
    el.append(topbar(api, 'Choose Event'));
    const content = h('div.content.scroll'); const grid = h('div.grid.mode-grid');
    for (const m of game.data.modes) {
      grid.append(h('div.card.clickable.mode-card' + (m.id === state.selectedMode ? '.selected' : ''), { style: { '--mc': m.color }, onClick: () => modeDetail(m, api) },
        h('div.ic', icon(m.icon)),
        h('div.nm.t.outline.thin', {}, m.name), h('div.sb', {}, m.sub + ' · ' + m.players), h('div.mp', {}, m.map)));
    }
    stagger(grid, 45); content.append(grid); el.append(content);
  }, { name: 'modes' });
}

function modeDetail(m, parentApi) {
  openScreen((el, api) => {
    el.append(topbar(api, m.name, { sub: m.sub }));
    const content = h('div.content');
    const wrap = h('div.mode-detail', { style: { '--mc': m.color } },
      h('div.card.map', icon(m.icon), h('div.t.outline.thin', { style: { position: 'absolute', bottom: '30px', left: 0, right: 0, textAlign: 'center', font: '44px/1 var(--font-display)' } }, m.map)),
      h('div.card.info',
        h('div.nm.t.outline.thin', {}, m.name), h('div.mp.t', {}, m.map), h('div', { style: { font: '800 24px var(--font-body)', color: 'var(--text-dim)' } }, m.sub + ' · ' + m.players), h('div.tx', {}, m.text),
        h('div.actions',
          h('button.btn.grey', { onClick: () => api.close() }, 'BACK'),
          h('button.btn.yellow.big', { onClick: () => { state.selectedMode = m.id; save(); emit('mode'); sfx('reward'); api.close(); parentApi.close(); toast(`${m.name} ${m.sub} selected`, { iconName: m.icon }); } }, 'SELECT'))));
    content.append(wrap); el.append(content);
  }, { name: 'mode-detail' });
}

const bots = ['Bulldog_Ben', 'CoachK', 'TennisTessa', 'CastleGhost', 'Dorm_Dan', 'QuadKing', 'LateForChapel', 'PianoMan', 'SnackRaider', 'HallMonitor', 'DeanOfBrawl', 'FieldDayFury'];

export function matchmaking() {
  const m = currentMode(); const me = currentBrawler();
  const isShowdown = m.id.startsWith('showdown');
  const total = m.id === 'showdown_solo' ? 10 : m.id === 'showdown_duo' ? 10 : 6;
  openScreen((el, api) => {
    let cancelled = false;
    el.append(topbar(api, m.name, { sub: m.sub + ' · ' + m.map, currencies: false, close: false }));
    const content = h('div.content'); const box = h('div.mm');
    const title = h('div.searching.t.outline', {}, h('span', {}, 'SEARCHING FOR PLAYERS'), h('span.dots'));
    const slots = h('div.slots');
    const pool = [...game.brawlers.brawlers];
    const mkSlot = (name, brawler, mine = false) => h('div.plate.slot' + (mine ? '.me' : '') + (name ? '' : '.empty'),
      h('div.av', name ? h('img', { src: url(brawler.portrait) }) : null), h('div.nm', {}, name || '…'));
    const slotEls = [];
    for (let i = 0; i < total; i++) { const s = i === 0 ? mkSlot(state.name, me, true) : mkSlot(null); slotEls.push(s); slots.append(s); }
    const timer = h('div.timer', {}, 'Estimated wait: a few seconds');
    const cancel = h('button.btn.red', { onClick: () => { cancelled = true; sfx('back'); api.close(); }, dataset: { sfx: 'none' } }, 'CANCEL');
    box.append(title, slots, timer, cancel); content.append(box); el.append(content);

    // fill slots one by one
    const names = shuffle(bots).slice(0, total - 1); let i = 1;
    const fill = () => {
      if (cancelled || !document.body.contains(el)) return;
      if (i < total) {
        const b = pool[Math.floor(Math.random() * pool.length)];
        const s = mkSlot(names[i - 1], b); s.style.animation = 'pop-in .35s cubic-bezier(.2,1.3,.4,1) both';
        slotEls[i].replaceWith(s); slotEls[i] = s; sfx('tick'); i++;
        setTimeout(fill, 260 + Math.random() * 420);
      } else found();
    };
    const found = () => {
      sfx('found');
      title.replaceWith(h('div.found.t.outline', {}, 'MATCH FOUND!'));
      timer.textContent = 'Loading ' + m.map + '…'; cancel.remove();
      slots.animate([{ transform: 'scale(1)' }, { transform: 'scale(1.06)' }, { transform: 'scale(1)' }], { duration: 400 });
      setTimeout(async () => {
        if (cancelled || !document.body.contains(el)) return;
        timer.textContent = 'Starting Godot…';
        const result = await launchGodot(m);
        if (cancelled || !document.body.contains(el)) return;
        api.close();
        if (result.ok) toast(`${currentBrawler().name} is entering ${m.map}`, { iconName: m.icon });
        else launchError(m, result.error);
      }, 1800);
    };
    setTimeout(fill, 500);
  }, { name: 'matchmaking' });
}

async function launchGodot(m) {
  try {
    const response = await fetch('/api/play', {
      method: 'POST',
      headers: { 'content-type': 'application/json' },
      body: JSON.stringify({ brawler: currentBrawler().id, mode: m.id }),
    });
    const result = await response.json().catch(() => ({}));
    return { ok: response.ok && result.ok, error: result.error || `Launcher returned ${response.status}` };
  } catch (error) {
    return { ok: false, error: 'The Godot launcher is not connected. Start the menu with npm start.' };
  }
}

function launchError(m, message) {
  openScreen((el, api) => {
    const content = h('div.content.center');
    const box = h('div.plate', { style: { width: '900px', padding: '40px', display: 'flex', flexDirection: 'column', alignItems: 'center', gap: '18px', textAlign: 'center' } },
      icon(m.icon, ''), h('div.t.outline', { style: { font: '70px/1 var(--font-display)' } }, m.map.toUpperCase()),
      h('div.t.outline.thin', { style: { font: '42px/1 var(--font-display)', color: 'var(--red)' } }, 'COULD NOT START MATCH'),
      h('div', { style: { font: '800 26px/1.4 var(--font-body)', color: '#d8def0' } }, message),
      h('div', { style: { display: 'flex', gap: '20px', alignItems: 'center', margin: '10px 0' } },
        h('div', { style: { width: '120px', height: '120px', borderRadius: '18px', border: '3px solid var(--line)', overflow: 'hidden', background: '#10131f' } }, h('img', { src: url(currentBrawler().portrait), style: { width: '130%', margin: '10% 0 0 -15%' } })),
        h('div', { style: { textAlign: 'left' } }, h('div.t.outline.thin', { style: { font: '40px/1 var(--font-display)' } }, currentBrawler().name), h('div', { style: { font: '800 22px var(--font-body)', color: 'var(--text-dim)' } }, `${m.name} · ${m.sub}`))),
      h('button.btn.grey', { onClick: () => api.close() }, 'BACK TO MENU'));
    box.querySelector('img').style.height = '140px';
    content.append(box); el.append(content);
  }, { name: 'battle', popup: true });
}

function shuffle(a) { const b = [...a]; for (let i = b.length - 1; i > 0; i--) { const j = Math.floor(Math.random() * (i + 1)); [b[i], b[j]] = [b[j], b[i]]; } return b; }
