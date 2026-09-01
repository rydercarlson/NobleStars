// BRAWLERS: roster grid -> detail view with live 3D preview, stats, select.

import { h, icon, fmt, openScreen, topbar, toast, stagger, $, $$, popup, burst, centerOf } from '../ui.js';
import { canAfford, spend } from '../state.js';
import { state, save, emit } from '../state.js';
import { url, slot } from '../assets.js';
import { game } from '../main.js';
import { BrawlerView } from '../brawler3d.js';
import { sfx } from '../audio.js';

const rankFromTrophies = (t) => Math.max(1, Math.min(35, Math.floor(Math.sqrt(t / 4)) + 1));
const rankGoal = (r) => 4 * r * r;
const roman = (n) => { const m = [[10,'X'],[9,'IX'],[5,'V'],[4,'IV'],[1,'I']]; let s = ''; for (const [v, r] of m) while (n >= v) { s += r; n -= v; } return s || 'I'; };

export function brawlers() {
  openScreen((el, api) => {
    const data = game.brawlers; const rar = data.rarities;
    const bar = topbar(api, 'Brawlers', { sub: `${Object.keys(state.unlocked).length}/${data.brawlers.length} unlocked` });
    // sort / filter dropdown
    const SORTS = [['rarity', 'RARITY'], ['trophies', 'TROPHIES'], ['power', 'POWER LEVEL'], ['rank', 'CLOSEST TO NEXT RANK']];
    let sortBy = state.settings.brawlerSort || 'trophies';
    const sortWrap = h('div.sort-wrap'); const sortBtn = h('button.sort-btn', {}, icon('quests'), h('span.lbl', {}, 'SORT: ' + SORTS.find((s) => s[0] === sortBy)[1]), h('span.arrow', {}, '▼'));
    let menuEl = null;
    sortBtn.addEventListener('click', () => {
      if (menuEl) { menuEl.remove(); menuEl = null; return; }
      menuEl = h('div.sort-menu');
      for (const [id, label] of SORTS) menuEl.append(h('button' + (id === sortBy ? '.on' : ''), { onClick: () => { sortBy = id; state.settings.brawlerSort = id; save(); sortBtn.querySelector('.lbl').textContent = 'SORT: ' + label; menuEl.remove(); menuEl = null; render(); } }, label));
      sortWrap.append(menuEl);
    });
    sortWrap.append(sortBtn); bar.insertBefore(sortWrap, bar.querySelector('.btn-close'));
    el.append(bar);
    const content = h('div.content.scroll');
    const grid = h('div.grid.brawler-grid');
    const rarityOrder = ['starting', 'rare', 'super_rare', 'epic', 'mythic', 'legendary'];
    const render = () => {
    grid.replaceChildren();
    const list = [...data.brawlers].sort((a, b2) => {
      const ua = !!state.unlocked[a.id], ub = !!state.unlocked[b2.id]; if (ua !== ub) return ua ? -1 : 1;
      const ta = state.brawlerTrophies[a.id] ?? a.trophies, tb = state.brawlerTrophies[b2.id] ?? b2.trophies;
      const pa = state.brawlerPower[a.id] ?? a.power, pb = state.brawlerPower[b2.id] ?? b2.power;
      if (sortBy === 'rarity') return rarityOrder.indexOf(b2.rarity) - rarityOrder.indexOf(a.rarity) || tb - ta;
      if (sortBy === 'power') return pb - pa || tb - ta;
      if (sortBy === 'rank') { const ga = rankGoal(rankFromTrophies(ta)) - ta, gb = rankGoal(rankFromTrophies(tb)) - tb; return ga - gb; }
      return tb - ta;
    });
    for (const b of list) {
      const unlocked = !!state.unlocked[b.id];
      const tro = state.brawlerTrophies[b.id] ?? b.trophies;
      const pw = state.brawlerPower[b.id] ?? b.power;
      const r = rar[b.rarity];
      const rank = rankFromTrophies(tro);
      const card = h('div.card.clickable.brawler-card' + (unlocked ? '' : '.locked') + (state.selectedBrawler === b.id ? '.selected' : ''), {
        style: { '--rc': r.color, '--rc-dark': r.dark, '--rc-hi': r.hi || r.color },
        onClick: () => { if (unlocked) detail(b, api); else toast(b.unlockHint || 'Locked', { iconName: 'lock' }); },
      },
        h('div.top', h('div.rank', {}, unlocked ? roman(rank) : ''), unlocked ? h('div.tro.outline.hair', icon('trophy'), fmt(tro)) : h('div.tro', { style: { font: '800 20px var(--font-body)' } }, 'LOCKED')),
        h('div.art', {}, h('img', { src: url(b.art), alt: b.name })),
        h('div.name.t.outline.hair', {}, b.name),
        unlocked ? null : h('div.hint', {}, b.unlockHint || ''),
        h('div.bottom',
          h('div.power', {}, unlocked ? pw : '?'),
          h('div.bar', h('i', { style: { width: (unlocked ? Math.min(100, pw * 9) : 0) + '%' } })),
          h('div.slot' + (unlocked && pw >= 7 ? '' : '.off'), { style: { backgroundImage: `url(${slot('icons.gadget')})` } }),
          h('div.slot' + (unlocked && pw >= 9 ? '' : '.off'), { style: { backgroundImage: `url(${slot('icons.star_power')})` } }),
          h('div.slot' + (unlocked && pw >= 8 ? '' : '.off'), { style: { backgroundImage: `url(${slot('icons.gear')})` } }),
        ),
      );
      grid.append(card);
    }
    stagger(grid, 45);
    };
    render();
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
    // ---- upgrade matrix: Power Points + Coins, green when affordable, red deficits
    const costPP = 20 * pw + 10 * pw * pw, costCoins = 150 * pw + 50 * pw * pw;
    const okPP = state.powerPoints >= costPP, okCoins = state.coins >= costCoins; const canUp = okPP && okCoins && pw < 11;
    const costRow = (ic, need, have, ok) => h('div.c' + (ok ? '' : '.lack'), icon(ic), fmt(need), h('span.have', {}, ok ? `(have ${fmt(have)})` : `(need ${fmt(need - have)} more)`));
    const upgradeBtn = h('button.btn' + (canUp ? '.green.ready' : '.grey'), { onClick: () => {
      if (!canUp) { sfx('error'); toast(pw >= 11 ? 'Max power level' : !okPP ? `Need ${fmt(costPP - state.powerPoints)} more Power Points` : `Need ${fmt(costCoins - state.coins)} more coins`, { iconName: !okPP ? 'power_point' : 'coin' }); return; }
      state.coins -= costCoins; state.powerPoints -= costPP; state.brawlerPower[b.id] = pw + 1; save(); emit('currency', {}); sfx('purchase');
      const c = centerOf(upgradeBtn); burst(c.x, c.y, 'power_point', 14);
      toast(`${b.name} is now Power ${pw + 1}!`, { iconName: 'power_point' });
      api.close(); detail(b, parentApi);
    } }, 'UPGRADE');
    const upgradeBox = h('div.upgrade-box', h('div.lvl', {}, 'POWER', h('b', {}, pw >= 11 ? 'MAX' : `${pw} → ${pw + 1}`)), h('div.cost', costRow('power_point', costPP, state.powerPoints, okPP), costRow('coin', costCoins, state.coins, okCoins)), upgradeBtn);
    // ---- equipment hub
    const EQUIP = [
      { key: 'gadget', label: 'Trick', ic: 'gadget', name: b.gadget || 'Foam Refill', req: 7, price: 1000, cur: 'coins' },
      { key: 'star_power', label: 'Honor Roll', ic: 'star_power', name: b.starPower || 'Second Wind', req: 9, price: 2000, cur: 'coins' },
      { key: 'gear', label: 'Locker Gear', ic: 'gear', name: b.gear || 'Speed Gear', req: 8, price: 1000, cur: 'coins' },
      { key: 'hypercharge', label: 'Spirit Week', ic: 'hypercharge', name: b.hypercharge || 'Overdrive', req: 11, price: 5000, cur: 'coins' },
    ];
    const equipGrid = h('div.equip');
    for (const e of EQUIP) {
      const owned = !!state.claimed[`eq:${b.id}:${e.key}`]; const equipped = state.settings[`eq:${b.id}`] === e.key;
      const cell = h('div.eq' + (owned ? '' : '.off') + (equipped ? '.selected' : ''), icon(e.ic), h('div.k', {}, e.label), h('div.n' + (owned ? '' : '.dim'), {}, owned ? e.name : pw >= e.req ? 'AVAILABLE' : `POWER ${e.req}`));
      cell.addEventListener('click', () => equipPopup(b, e, pw, owned, () => { api.close(); detail(b, parentApi); }));
      equipGrid.append(cell);
    }
    panel.append(h('div.t.outline.hair', { style: { font: '24px/1 var(--font-display)', marginTop: '4px' } }, 'UPGRADE'), upgradeBox);
    view.append(equipGrid);
    panel.append(h('div.actions', selectBtn));
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

/** Equipment sub-menu: buy / equip without leaving the brawler page. */
function equipPopup(b, e, pw, owned, refresh) {
  popup(e.label, (body, api) => {
    const unlocked = pw >= e.req;
    body.append(h('div', { style: { display: 'flex', gap: '20px', alignItems: 'center' } },
      h('div', { style: { width: '120px', height: '120px', borderRadius: '18px', border: '3px solid var(--line)', background: 'rgba(0,0,0,.35)', display: 'flex', alignItems: 'center', justifyContent: 'center' } }, icon(e.ic)),
      h('div', h('div.t.outline.thin', { style: { font: '40px/1 var(--font-display)' } }, e.name), h('div', { style: { font: '800 22px var(--font-body)', color: 'var(--text-dim)', marginTop: '6px' } }, `${b.name} · ${e.label}${unlocked ? '' : ` · unlocks at Power ${e.req}`}`))));
    body.querySelector('img').style.height = '80px';
    body.append(h('div', { style: { font: '700 24px/1.4 var(--font-body)', color: '#d8def0' } }, ({ gadget: 'A once-per-match trick. Tap the trick button in battle to pull it off.', star_power: 'Make the Honor Roll: a passive upgrade that changes how ' + b.name + ' plays.', gear: 'Locker gear — equip one for a permanent stat boost.', hypercharge: 'Spirit Week: charge it up in battle for a supercharged Super.' })[e.key]));
    const row = h('div', { style: { display: 'flex', gap: '14px', justifyContent: 'flex-end' } });
    if (!unlocked) row.append(h('button.btn.grey.disabled', {}, icon('lock'), `POWER ${e.req} REQUIRED`));
    else if (!owned) row.append(h('button.btn.yellow', { onClick: (ev) => {
      if (!canAfford(e.cur, e.price)) { sfx('error'); toast(`Not enough ${e.cur}`, { iconName: 'coin' }); return; }
      spend(e.cur, e.price); state.claimed[`eq:${b.id}:${e.key}`] = true; state.settings[`eq:${b.id}`] = e.key; save(); sfx('purchase');
      const c = centerOf(ev.currentTarget); burst(c.x, c.y, e.ic, 12); toast(`${e.name} unlocked!`, { iconName: e.ic }); api.close(); refresh();
    } }, icon('coin'), h('span.price', {}, fmt(e.price)), ' UNLOCK'));
    else row.append(h('button.btn.green', { onClick: () => { state.settings[`eq:${b.id}`] = e.key; save(); sfx('reward'); toast(`${e.name} equipped`, { iconName: 'check' }); api.close(); refresh(); } }, 'EQUIP'));
    body.append(row);
  }, { name: 'equip' });
}
