// BRAWLERS: roster grid -> detail view with live 3D preview, stats, select.

import { h, icon, fmt, openScreen, topbar, toast, stagger, $, $$ } from '../ui.js';
import { state, save, emit } from '../state.js';
import { url } from '../assets.js';
import { game } from '../main.js';
import { BrawlerView } from '../brawler3d.js';
import { sfx } from '../audio.js';

const rankFromTrophies = (t) => Math.max(1, Math.min(35, Math.floor(Math.sqrt(t / 4)) + 1));
const rankGoal = (r) => 4 * r * r;

export function brawlers() {
  openScreen((el, api) => {
    const data = game.brawlers; const rar = data.rarities;
    el.append(topbar(api, 'Brawlers', { sub: `${Object.keys(state.unlocked).length}/${data.brawlers.length} unlocked` }));
    const content = h('div.content.scroll');
    const grid = h('div.grid.brawler-grid');
    for (const b of data.brawlers) {
      const unlocked = !!state.unlocked[b.id];
      const tro = state.brawlerTrophies[b.id] ?? b.trophies;
      const pw = state.brawlerPower[b.id] ?? b.power;
      const r = rar[b.rarity];
      const card = h('div.card.clickable.brawler-card' + (unlocked ? '' : '.locked') + (state.selectedBrawler === b.id ? '.selected' : ''), {
        style: { '--rc': r.color, '--rc-dark': r.dark },
        onClick: () => { if (unlocked) detail(b, api); else toast(b.unlockHint || 'Locked', { iconName: 'lock' }); },
      },
        h('div.art', {},
          h('img', { src: url(b.portrait), alt: b.name }),
          unlocked ? h('div.rank', {}, icon('trophy'), fmt(tro)) : null,
          unlocked ? h('div.power.t', {}, 'P' + pw) : null,
        ),
        h('div.name.t.outline.hair', {}, b.name),
      );
      grid.append(card);
    }
    stagger(grid, 45);
    content.append(grid);
    el.append(content);
  }, { name: 'brawlers' });
}

function detail(b, parentApi) {
  openScreen((el, api) => {
    const rar = game.brawlers.rarities[b.rarity];
    const tro = state.brawlerTrophies[b.id] ?? b.trophies;
    const pw = state.brawlerPower[b.id] ?? b.power;
    const rank = rankFromTrophies(tro); const goal = rankGoal(rank);
    el.append(topbar(api, b.name, { sub: b.title }));
    const content = h('div.content'); const wrap = h('div.detail');
    const view = h('div.view3d'); const canvas = h('canvas'); view.append(canvas);
    // animation buttons
    const animRow = h('div.anim-row');
    view.append(animRow);
    const panel = h('div.panel',
      h('div.head', h('div.rarity.t.outline.hair', { style: { '--rc': rar.color } }, rar.label), h('div.role', {}, b.role)),
      h('div.desc', {}, b.description),
      h('div.trophy-road', icon('trophy'), h('div.bar', h('i')), h('div.n', {}, `${fmt(tro)} / ${fmt(goal)}`), h('div.n', { style: { color: '#fff' } }, 'RANK ' + rank)),
      h('div.stat-list',
        stat('Health', fmt(b.stats.health)), stat('Damage', fmt(b.stats.damage)), stat('Speed', b.stats.speed), stat('Range', b.stats.range),
        stat('Power', 'LVL ' + pw), stat('Pins', String(b.pins))),
      ability('atk', 'A', b.attack), ability('sup', 'S', b.super),
    );
    const isSel = () => state.selectedBrawler === b.id;
    const selectBtn = h('button.btn.big' + (isSel() ? '.grey' : '.yellow'), { onClick: () => {
      if (isSel()) return;
      state.selectedBrawler = b.id; save(); emit('brawler');
      selectBtn.className = 'btn big grey'; selectBtn.textContent = 'SELECTED'; sfx('reward');
      toast(`${b.name} is ready to brawl!`, { iconName: 'check' });
      setTimeout(() => { api.close(); parentApi.close(); }, 500);
    } }, isSel() ? 'SELECTED' : 'SELECT');
    const upgradeBtn = h('button.btn.blue', { onClick: () => {
      const cost = 200 * pw;
      if (state.coins < cost) { sfx('error'); toast(`Need ${fmt(cost)} coins`, { iconName: 'coin' }); return; }
      state.coins -= cost; state.brawlerPower[b.id] = pw + 1; save(); emit('currency'); sfx('purchase');
      toast(`${b.name} is now Power ${pw + 1}!`, { iconName: 'power_point' });
      api.close(); detail(b, parentApi);
    } }, icon('coin'), h('span.price', {}, fmt(200 * pw)), ' UPGRADE');
    panel.append(h('div.actions', upgradeBtn, selectBtn));
    wrap.append(view, panel); content.append(wrap); el.append(content);
    requestAnimationFrame(() => { view.querySelector && (panel.querySelector('.trophy-road .bar i').style.width = Math.min(100, (tro / goal) * 100) + '%'); });

    // 3D preview
    const v = new BrawlerView(canvas, { fov: 24, fill: 0.74, lookY: 0.5, onTap: () => sfx('hit') });
    game.detailView = v; v.resize();
    v.load(b).then(() => {
      const atk = (b.attackClips || []).filter((n) => v.actions[n]);
      atk.forEach((n, i) => animRow.append(h('button.btn.small.grey', { onClick: () => { v.play(n); sfx('hit'); }, dataset: { sfx: 'none' } }, atk.length > 1 ? 'ATTACK ' + (i + 1) : 'ATTACK')));
      if (b.moveClip && v.actions[b.moveClip]) animRow.append(h('button.btn.small.grey', { onClick: () => { v.play(b.moveClip); sfx('hit'); }, dataset: { sfx: 'none' } }, 'RUN'));
      animRow.append(h('button.btn.small.grey', { onClick: () => { v._toIdle(0.3); }, dataset: { sfx: 'click' } }, 'IDLE'));
    });
    const stop = () => { v.dispose(); game.detailView = null; };
    const obs = new MutationObserver(() => { if (!document.body.contains(el)) { stop(); obs.disconnect(); } });
    obs.observe($('#screens'), { childList: true });
  }, { name: 'brawler-detail' });
}

const stat = (k, v) => h('div.stat', h('div.k', {}, k), h('div.v', {}, v));
const ability = (cls, letter, ab) => h('div.ability', h('div.ic.' + cls + '.t.outline.hair', {}, letter), h('div', h('div.ab-name.t', {}, ab.name), h('div.ab-text', {}, ab.text)));
