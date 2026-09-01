// EVENTS overlay (active + upcoming with countdowns) and in-place matchmaking on the home screen:
// PLAY turns into a searching state, team slots fill with players, MATCH FOUND -> battle hand-off -> result.

import { h, icon, fmt, openScreen, topbar, toast, stagger, burst, popup, $, $$ } from '../ui.js';
import { state, save, emit } from '../state.js';
import { url } from '../assets.js';
import { game, currentBrawler, currentMode, renderHome, eventEndsIn, eventStartsIn, fmtCountdown } from '../main.js';
import { sfx } from '../audio.js';

export function modes() {
  openScreen((el, api) => {
    el.append(topbar(api, 'Events', { sub: 'active map pool' }));
    const content = h('div.content.scroll');
    content.append(h('div.section-h', {}, 'Active events', h('span.n', {}, 'tap an event to select it')));
    const grid = h('div.grid.events-grid');
    for (const m of game.data.modes) {
      grid.append(h('div.card.clickable.event-card' + (m.id === state.selectedMode ? '.selected' : ''), { style: { '--mc': m.color }, onClick: () => modeDetail(m, api) },
        h('div.top', icon(m.icon), h('div', h('div.nm.t.outline.thin', {}, m.name), h('div.sb', {}, m.sub + ' · ' + m.players))),
        h('div.mp.t', {}, m.map), h('div.cd', {}, 'Ends in ' + fmtCountdown(eventEndsIn(m)))));
    }
    stagger(grid, 40); content.append(grid);
    content.append(h('div.section-h', { style: { marginTop: '30px' } }, 'Upcoming', h('span.n', {}, 'rotates in when the timer hits zero')));
    const up = h('div.grid.events-grid');
    for (const m of game.data.upcoming) {
      up.append(h('div.card.event-card.upcoming', { style: { '--mc': m.color }, onClick: () => toast(`${m.name} ${m.sub} starts in ${fmtCountdown(eventStartsIn(m))}`, { iconName: m.icon }) },
        h('div.top', icon(m.icon), h('div', h('div.nm.t.outline.thin', {}, m.name), h('div.sb', {}, m.sub))),
        h('div.mp.t', {}, m.map), h('div.cd', {}, 'Starts in ' + fmtCountdown(eventStartsIn(m)))));
    }
    stagger(up, 40); content.append(up); el.append(content);
  }, { name: 'modes' });
}

function modeDetail(m, parentApi) {
  openScreen((el, api) => {
    el.append(topbar(api, m.name, { sub: m.sub }));
    const content = h('div.content');
    const wrap = h('div.mode-detail', { style: { '--mc': m.color } },
      h('div.card.map', icon(m.icon), h('div.t.outline.thin', { style: { position: 'absolute', bottom: '30px', left: 0, right: 0, textAlign: 'center', font: '44px/1 var(--font-display)' } }, m.map)),
      h('div.card.info',
        h('div.nm.t.outline.thin', {}, m.name), h('div.mp.t', {}, m.map), h('div', { style: { font: '800 24px var(--font-body)', color: 'var(--text-dim)' } }, `${m.sub} · ${m.players} · ends in ${fmtCountdown(eventEndsIn(m))}`), h('div.tx', {}, m.text),
        h('div.actions',
          h('button.btn.grey', { onClick: () => api.close() }, 'BACK'),
          h('button.btn.yellow.big', { onClick: () => { state.selectedMode = m.id; save(); emit('mode'); sfx('reward'); api.close(); parentApi.close(); toast(`${m.name} ${m.sub} selected`, { iconName: m.icon }); } }, 'SELECT'))));
    content.append(wrap); el.append(content);
  }, { name: 'mode-detail' });
}

let search = null;

/** PLAY: searching happens right on the home screen (Brawl-style), the PLAY button becomes CANCEL. */
export function matchmaking() {
  if (search) return;
  const m = currentMode(); const total = m.id.startsWith('showdown') ? 10 : 6;
  const bottom = $('#bottom'); const status = $('#search-status'); const row = $('#found-row'); const text = $('#search-text');
  bottom.classList.add('searching'); status.classList.remove('hidden'); $('#cancel-btn').classList.remove('hidden');
  const team = [state.team1, state.team2].filter(Boolean).length; let found = 1 + team;
  row.replaceChildren();
  const me = currentBrawler(); const pool = game.brawlers.brawlers;
  const addFound = (b) => { row.append(h('div.f', h('img', { src: url(b.art) }))); };
  addFound(me); [state.team1, state.team2].filter(Boolean).forEach((id) => { const fr = game.data.friends.find((x) => x.id === id); addFound(pool.find((x) => x.id === fr?.brawler) || pool[0]); });
  for (let i = found; i < total; i++) row.append(h('div.f.empty'));
  const setText = () => { text.textContent = `SEARCHING FOR PLAYERS ${found}/${total}`; };
  setText();
  search = { cancelled: false };
  const step = () => {
    if (!search || search.cancelled) return;
    if (found < total) {
      found++; const b = pool[Math.floor(Math.random() * pool.length)];
      const empty = row.querySelector('.f.empty'); const f = h('div.f', h('img', { src: url(b.art) })); empty.replaceWith(f);
      sfx('tick'); setText();
      search.timer = setTimeout(step, 240 + Math.random() * 480);
    } else {
      text.textContent = 'MATCH FOUND!'; text.style.color = 'var(--green)'; sfx('found');
      row.animate([{ transform: 'scale(1)' }, { transform: 'scale(1.06)' }, { transform: 'scale(1)' }], { duration: 400 });
      search.timer = setTimeout(() => { endSearch(); battleStub(m); }, 1500);
    }
  };
  search.timer = setTimeout(step, 600);
}

export function cancelSearch() { if (!search) return; search.cancelled = true; clearTimeout(search.timer); endSearch(); toast('Search cancelled'); }
function endSearch() {
  search = null; $('#bottom').classList.remove('searching'); $('#search-status').classList.add('hidden'); $('#cancel-btn').classList.add('hidden');
  $('#search-text').style.color = ''; $('#found-row').replaceChildren();
}

function battleStub(m) {
  openScreen((el, api) => {
    const content = h('div.content.center');
    const box = h('div.plate', { style: { width: '900px', padding: '40px', display: 'flex', flexDirection: 'column', alignItems: 'center', gap: '18px', textAlign: 'center' } },
      icon(m.icon, ''), h('div.t.outline', { style: { font: '70px/1 var(--font-display)' } }, m.map.toUpperCase()),
      h('div', { style: { font: '800 26px/1.4 var(--font-body)', color: '#d8def0' } }, 'The battle scene is the next thing to build. The menu hands off here with the selected event, map and brawler:'),
      h('div', { style: { display: 'flex', gap: '20px', alignItems: 'center', margin: '10px 0' } },
        h('div', { style: { width: '120px', height: '120px', borderRadius: '18px', border: '3px solid var(--line)', overflow: 'hidden', background: '#10131f' } }, h('img', { src: url(currentBrawler().art), style: { width: '130%', margin: '10% 0 0 -15%' } })),
        h('div', { style: { textAlign: 'left' } }, h('div.t.outline.thin', { style: { font: '40px/1 var(--font-display)' } }, currentBrawler().name), h('div', { style: { font: '800 22px var(--font-body)', color: 'var(--text-dim)' } }, `${m.name} · ${m.sub}`))),
      h('div', { style: { display: 'flex', gap: '16px' } },
        h('button.btn.yellow.big', { onClick: () => {
          const won = Math.random() < 0.6; const dt = won ? 8 : -4; const coins = won ? 40 : 10;
          state.trophies = Math.max(0, state.trophies + dt); state.coins += coins; state.matches++; state.powerPoints += 10;
          const bt = state.brawlerTrophies[currentBrawler().id] ?? currentBrawler().trophies; state.brawlerTrophies[currentBrawler().id] = Math.max(0, bt + dt);
          state.passTokens += 100; const s = game.data.season; while (state.passTokens >= s.tokensPerTier && state.passTier < s.maxTier) { state.passTokens -= s.tokensPerTier; state.passTier++; }
          const q = game.data.quests.daily[0]; if (won && q.progress < q.goal) q.progress++;
          save(); emit('currency', {}); emit('profile');
          api.close(); results(won, dt, coins);
        } }, 'SIMULATE RESULT'),
        h('button.btn.grey', { onClick: () => api.close() }, 'BACK TO MENU')));
    box.querySelector('img').style.height = '140px';
    content.append(box); el.append(content);
  }, { name: 'battle', popup: true });
}

function results(won, dt, coins) {
  openScreen((el, api) => {
    const content = h('div.content.center');
    const box = h('div.plate', { style: { width: '760px', padding: '40px', display: 'flex', flexDirection: 'column', alignItems: 'center', gap: '16px' } },
      h('div.t.outline', { style: { font: '110px/1 var(--font-display)', color: won ? 'var(--green)' : 'var(--red)' } }, won ? 'VICTORY!' : 'DEFEAT'),
      h('div', { style: { display: 'flex', gap: '30px' } },
        h('div.reward-pill', icon('trophy'), (dt >= 0 ? '+' : '') + dt),
        h('div.reward-pill', icon('coin'), '+' + coins),
        h('div.reward-pill', icon('power_point'), '+10'),
        h('div.reward-pill', icon('token'), '+100')),
      h('button.btn.yellow.big', { onClick: () => api.close(), style: { marginTop: '14px' } }, 'CONTINUE'));
    content.append(box); el.append(content);
    setTimeout(() => burst(960, 380, won ? 'trophy' : 'token', 20), 200);
    sfx(won ? 'found' : 'error');
  }, { name: 'results', popup: true });
}
