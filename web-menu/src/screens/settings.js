// SETTINGS popup (menu button) and PROFILE popup (guest panel).

import { h, icon, fmt, popup, toast, confirm } from '../ui.js';
import { state, save, emit, resetSave } from '../state.js';
import { url } from '../assets.js';
import { game, currentBrawler } from '../main.js';
import { sfx, music } from '../audio.js';

export function settings() {
  popup('Settings', (body, api) => {
    const row = (label, hint, key, onChange) => {
      const tg = h('button.toggle' + (state.settings[key] ? '.on' : ''), { dataset: { sfx: 'click' }, onClick: () => {
        state.settings[key] = !state.settings[key]; save(); tg.classList.toggle('on', state.settings[key]); tg.querySelector('span').textContent = state.settings[key] ? 'ON' : 'OFF'; onChange && onChange(state.settings[key]);
      } }, h('span', {}, state.settings[key] ? 'ON' : 'OFF'));
      return h('div.setting', h('div', h('div.lbl.t', {}, label), h('div.hint', {}, hint)), tg);
    };
    body.append(
      row('Music', 'Menu music', 'music', (v) => music(v)),
      row('Sound FX', 'Button and brawler sounds', 'sfx'),
      row('Hints', 'Show tips on the home screen', 'hints'),
      h('div.setting', h('div', h('div.lbl.t', {}, 'Player name'), h('div.hint', {}, 'Shown on your profile and in the club')), h('button.btn.small.blue', { onClick: () => { api.close(); profile(); } }, 'CHANGE')),
      h('div.setting', h('div', h('div.lbl.t', {}, 'Support'), h('div.hint', {}, 'Nobles Brawl · menu prototype v0.1')), h('button.btn.small.grey', { onClick: () => toast('Support: dm the dev', { iconName: 'inbox' }) }, 'HELP')),
      h('div.setting', h('div', h('div.lbl.t', {}, 'Reset progress'), h('div.hint', {}, 'Wipes coins, gems, unlocks and settings on this device')), h('button.btn.small.red', { onClick: async () => { if (await confirm('Reset progress?', 'This deletes your local save and reloads the menu.', { okLabel: 'RESET', okClass: 'red' })) resetSave(); } }, 'RESET')),
    );
  }, { name: 'settings' });
}

export function profile() {
  popup('Profile', (body, api) => {
    const b = currentBrawler();
    const head = h('div', { style: { display: 'flex', alignItems: 'center', gap: '22px' } },
      h('div', { style: { width: '140px', height: '140px', borderRadius: '20px', border: '3px solid var(--line)', overflow: 'hidden', background: '#10131f', flex: 'none' } }, h('img', { src: url(b.art), style: { width: '130%', margin: '10% 0 0 -15%' } })),
      h('div', { style: { flex: 1 } },
        h('div.t.outline.thin', { style: { font: '52px/1 var(--font-display)' } }, state.name),
        h('div', { style: { font: '800 22px var(--font-body)', color: 'var(--text-dim)', marginTop: '6px' } }, `#NOBLES${String(state.level).padStart(3, '0')} · Level ${state.level} · Club: ${game.data.club.name}`)),
    );
    const inp = h('input.text-input', { value: state.name, maxLength: 14, placeholder: 'Player name' });
    inp.addEventListener('keydown', (e) => e.stopPropagation());
    const nameRow = h('div', { style: { display: 'flex', gap: '12px' } }, inp, h('button.btn.green', { onClick: () => {
      const v = inp.value.trim().replace(/\s+/g, ' ').slice(0, 14);
      if (v.length < 2) { sfx('error'); toast('Name must be at least 2 characters'); return; }
      state.name = v.toUpperCase(); save(); emit('profile'); sfx('reward'); toast('Name updated!', { iconName: 'check' }); api.close();
    } }, 'SAVE'));
    const unlocked = Object.keys(state.unlocked).length;
    const stats = h('div.stat-grid',
      st('Trophies', fmt(state.trophies), 'trophy'), st('Highest', fmt(state.trophies + 60), 'trophy'), st('Brawlers', `${unlocked}/${game.brawlers.brawlers.length}`, 'brawlers'),
      st('3v3 wins', fmt(38 + state.matches), null), st('Solo wins', fmt(12 + state.matches), null), st('Star points', fmt(state.starPoints), 'star_points'));
    body.append(head, h('div.t.outline.hair', { style: { font: '26px/1 var(--font-display)', marginTop: '6px' } }, 'CHANGE NAME'), nameRow, h('div.t.outline.hair', { style: { font: '26px/1 var(--font-display)', marginTop: '6px' } }, 'STATS'), stats);
  }, { name: 'profile' });
}

const st = (k, v, ic) => h('div.st', h('div.k', {}, k), h('div.v', ic ? icon(ic) : null, v));
