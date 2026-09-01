// NOBLES PASS: season header + scrolling reward track (free / premium lanes).

import { h, icon, fmt, openScreen, topbar, toast, burst, centerOf, confirm } from '../ui.js';
import { state, save, emit } from '../state.js';
import { url } from '../assets.js';
import { game, renderHome } from '../main.js';
import { sfx } from '../audio.js';
import { openStarDrop } from './shop.js';

const kindIcon = { coins: 'coin', gems: 'gem', power_points: 'power_point', star_drop: 'star_drop', pin: 'token', skin: null };

export function pass() {
  openScreen((el, api) => {
    const d = game.data; const s = d.season;
    el.append(topbar(api, 'Nobles Pass', { sub: `Season ${s.number}` }));
    const content = h('div.content');

    const head = h('div.plate.pass-head',
      icon('shield', 'shield'),
      h('div.lines', h('div.l1.t.outline.thin', {}, `SEASON ${s.number}: ${s.name}`), h('div.l2', {}, `${s.endsInDays} days left · ${state.passPremium ? 'Nobles Pass active' : 'Free track'}`)),
      h('div.tokenbar', h('div.lbl', h('span', {}, 'Tokens to next tier'), h('span.num', {}, `${state.passTokens} / ${s.tokensPerTier}`)), h('div.bar', h('i'))),
      h('div.tier', h('div.k', {}, 'Tier'), h('div.v.num', {}, String(state.passTier))),
      state.passPremium ? h('button.btn.grey.disabled', {}, 'PASS ACTIVE') : h('button.btn.yellow', { onClick: async (e) => {
        const ok = await confirm('Nobles Pass', 'Unlock the premium reward lane for this season for 169 gems?', { okLabel: 'UNLOCK · 169' });
        if (!ok) return;
        if (state.gems < 169) { sfx('error'); toast('Not enough gems', { iconName: 'gem' }); return; }
        state.gems -= 169; state.passPremium = true; save(); emit('currency', {}); sfx('reward');
        const c = centerOf(e.currentTarget); burst(c.x, c.y, 'star_drop', 18);
        toast('Nobles Pass unlocked!', { iconName: 'shield' });
        api.close(); pass();
      } }, icon('gem'), '169 · UNLOCK'),
    );
    content.append(head);
    requestAnimationFrame(() => { head.querySelector('.bar i').style.width = Math.round((state.passTokens / s.tokensPerTier) * 100) + '%'; });

    // token earning demo: "collect tokens" button (simulates playing)
    const track = h('div.pass-track');
    for (const t of d.passRewards) {
      const col = h('div.tier-col' + (t.tier === state.passTier ? '.current' : t.tier < state.passTier ? '.claimed' : ''));
      col.append(h('div.tn.t', {}, 'TIER ' + t.tier));
      col.append(rewardCell(t, 'free', api));
      col.append(rewardCell(t, 'premium', api));
      track.append(col);
    }
    content.append(h('div.track-lane', h('span', {}, 'FREE ↑'), h('span', { style: { marginLeft: 'auto' } }, 'PASS ↓')));
    content.append(track);
    // auto-scroll to current tier
    requestAnimationFrame(() => { const cur = track.querySelector('.tier-col.current'); if (cur) track.scrollLeft = Math.max(0, cur.offsetLeft - 60); });
    // wheel -> horizontal
    track.addEventListener('wheel', (e) => { track.scrollLeft += e.deltaY; e.preventDefault(); }, { passive: false });
    // drag to scroll
    let dx = null, sl = 0; track.addEventListener('pointerdown', (e) => { dx = e.clientX; sl = track.scrollLeft; });
    window.addEventListener('pointermove', (e) => { if (dx == null) return; track.scrollLeft = sl - (e.clientX - dx) / (parseFloat(getComputedStyle(document.querySelector('#stage')).getPropertyValue('--stage-scale')) || 1); });
    window.addEventListener('pointerup', () => { dx = null; });

    content.append(h('div', { style: { display: 'flex', gap: '16px', justifyContent: 'center', marginTop: '18px' } },
      h('button.btn.blue', { onClick: (e) => {
        // simulate a match's worth of tokens
        const gained = 150 + Math.floor(Math.random() * 100);
        state.passTokens += gained;
        while (state.passTokens >= s.tokensPerTier && state.passTier < s.maxTier) { state.passTokens -= s.tokensPerTier; state.passTier++; sfx('reward'); }
        save(); renderHome(); sfx('purchase');
        const c = centerOf(e.currentTarget); burst(c.x, c.y - 40, 'token', 10);
        toast(`+${gained} tokens`, { iconName: 'token' });
        api.close(); pass();
      } }, icon('token'), 'COLLECT TOKENS (DEMO)')));
    el.append(content);
  }, { name: 'pass' });
}

function rewardCell(t, lane, api) {
  const r = t[lane]; const id = `pass:${t.tier}:${lane}`;
  const claimed = !!state.claimed[id];
  const lockedLane = lane === 'premium' && !state.passPremium;
  const reachable = t.tier <= state.passTier;
  const claimable = reachable && !claimed && !lockedLane;
  const cls = '.reward.card' + (lane === 'premium' ? '.premium' : '') + (claimed ? '.claimed' : lockedLane || !reachable ? '.locked' : '.claimable');
  const cell = h('div' + cls, {},
    r.kind === 'skin' ? h('img', { src: url(game.brawlers.brawlers.find((b) => r.name.toLowerCase().includes(b.name.toLowerCase()))?.portrait || game.brawlers.brawlers[0].portrait), style: { height: '110px', borderRadius: '12px' } }) : icon(kindIcon[r.kind] || 'token'),
    r.amount ? h('div.amt.t.outline.hair', {}, 'x' + r.amount) : null,
    h('div.nm', {}, r.name || ({ coins: 'Coins', gems: 'Gems', power_points: 'Power Points', star_drop: 'Star Drop' })[r.kind] || r.kind));
  if (claimable) cell.addEventListener('click', (e) => {
    state.claimed[id] = true;
    if (r.kind === 'coins' || r.kind === 'gems') { state[r.kind] += r.amount; emit('currency', {}); }
    save(); sfx('reward');
    const c = centerOf(cell); burst(c.x, c.y, kindIcon[r.kind] || 'star_drop', 12);
    cell.className = cell.className.replace('claimable', 'claimed'); cell.classList.add('claimed');
    toast(`Claimed ${r.amount ? r.amount + ' ' : ''}${r.name || r.kind.replace('_', ' ')}`, { iconName: kindIcon[r.kind] || 'token' });
    if (r.kind === 'star_drop') for (let i = 0; i < r.amount; i++) setTimeout(openStarDrop, 400 + i * 100);
  });
  else if (lockedLane && reachable && !claimed) cell.addEventListener('click', () => { sfx('error'); toast('Unlock the Nobles Pass to claim', { iconName: 'lock' }); });
  return cell;
}
