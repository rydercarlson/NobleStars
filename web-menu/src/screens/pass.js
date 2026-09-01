// NOBLES PASS — Brawl Pass layout: season hero card on the left, REWARDS / QUESTS tabs,
// XP bar, and a two-lane reward track (premium lane on top, free lane below) with tier pins.

import { h, icon, fmt, openScreen, toast, burst, centerOf, confirm, $$ } from '../ui.js';
import { state, save, emit, addCurrency } from '../state.js';
import { url, slot } from '../assets.js';
import { game, renderHome } from '../main.js';
import { sfx } from '../audio.js';
import { openStarDrop, skinArt, skinKey } from './shop.js';
import { questList } from './progress.js';

const kindIcon = { coins: 'coin', gems: 'gem', power_points: 'power_point', dawg_treat: 'dawg_treat', pin: null, skin: null, bling: 'bling', brawler: null };
const kindLabel = { coins: 'COINS', gems: 'GEMS', power_points: 'POWER POINTS', dawg_treat: 'DAWG TREAT', bling: 'BLING' };

export function pass() {
  openScreen((el, api) => {
    const d = game.data; const s = d.season;
    const hero = game.brawlers.brawlers.find((b) => b.id === s.heroBrawler) || game.brawlers.brawlers[0];
    el.querySelector('.screen-bg').classList.add('pass-bg');
    let tab = 'rewards';

    // ---- top bar: back · season title · tabs · gems · home
    const bar = h('div.topbar.pass-top',
      h('button.btn-back', { onClick: () => api.close(), dataset: { sfx: 'back' } }, icon('back')),
      h('div.season-title.t.outline', {}, `SEASON ${s.number}`, h('br'), s.name),
      h('div.spacer'),
      h('div.pass-tabs',
        h('button.tab-btn.on', { dataset: { id: 'rewards' }, onClick: () => setTab('rewards') }, 'REWARDS'),
        h('button.tab-btn', { dataset: { id: 'quests' }, onClick: () => setTab('quests') }, 'QUESTS')),
      h('div.spacer'),
      h('div.currency.plate', icon('gem'), h('span.v.num.cur-gems', {}, fmt(state.gems))),
      h('button.btn-close', { onClick: () => api.close(), dataset: { sfx: 'back' } }, icon('close')));
    el.append(bar);

    const body = h('div.pass-body');
    // ---- hero card (left)
    const heroArt = game.passHero || url(hero.art);
    const card = h('div.pass-card' + (state.passPremium ? '.plus' : ''),
      h('div.pc-label.t.outline.hair', {}, state.passPremium ? 'NOBLES PASS PLUS' : 'NOBLES PASS'),
      h('div.pc-head', h('div.pc-ticket', icon('shield')), h('div.pc-season', h('div.t.outline.hair', {}, `SEASON ${s.number}`), h('div.pc-days', icon('token'), `${s.endsInDays}d 23h`))),
      h('img.pc-hero', { src: heroArt, alt: s.heroSkin }),
      h('div.pc-perks', icon('gem'), icon('dawg_treat'), icon('bling')),
      state.passPremium ? h('div.pc-active.t.outline.hair', {}, 'PLUS MODE ACTIVATED') : h('button.btn.yellow.big.pc-get', { onClick: () => buyPass(api) }, 'GET'));
    body.append(card);

    // ---- right side: XP bar + track (or quests)
    const right = h('div.pass-right');
    const xp = h('div.xp-row',
      h('div.xp-badge.t', {}, 'XP'),
      h('div.xp-bar', h('i', { style: { width: Math.round(((state.passTokens % s.xpPerTier) / s.xpPerTier) * 100) + '%' } }), h('span.num', {}, `${state.passTokens % s.xpPerTier}/${s.xpPerTier}`)),
      h('div.xp-arrow', {}, '▶'), h('div.xp-tier.num', {}, String(state.passTier)));
    const track = h('div.pass-track2');
    const lane = (kind) => h('div.lane.' + kind);
    const top = lane('premium'), mid = h('div.tier-line'), bot = lane('free');
    for (const t of d.passRewards) {
      top.append(rewardCard(t, 'premium', api));
      bot.append(rewardCard(t, 'free', api));
      const reached = t.tier <= state.passTier;
      mid.append(h('div.tier-pin' + (reached ? '.reached' : '') + (t.tier === state.passTier ? '.current' : ''), h('span.num', {}, String(t.tier))));
    }
    track.append(top, mid, bot);
    const questsView = h('div.pass-quests.hidden');
    right.append(xp, track, questsView);
    body.append(right); el.append(body);

    function setTab(id) {
      tab = id; $$('.pass-tabs .tab-btn', bar).forEach((b) => b.classList.toggle('on', b.dataset.id === id));
      track.classList.toggle('hidden', id !== 'rewards'); xp.classList.toggle('hidden', id !== 'rewards'); questsView.classList.toggle('hidden', id !== 'quests');
      if (id === 'quests' && !questsView.children.length) questList(questsView, api);
      sfx('click');
    }
    // scroll to current tier
    requestAnimationFrame(() => { const cur = mid.querySelector('.tier-pin.current'); if (cur) track.scrollLeft = Math.max(0, cur.offsetLeft - 420); });
    track.addEventListener('wheel', (e) => { track.scrollLeft += e.deltaY + e.deltaX; e.preventDefault(); }, { passive: false });
    let dx = null, sl = 0; track.addEventListener('pointerdown', (e) => { dx = e.clientX; sl = track.scrollLeft; });
    const scale = () => parseFloat(getComputedStyle(document.querySelector('#stage')).getPropertyValue('--stage-scale')) || 1;
    window.addEventListener('pointermove', (e) => { if (dx == null) return; track.scrollLeft = sl - (e.clientX - dx) / scale(); });
    window.addEventListener('pointerup', () => { dx = null; });
  }, { name: 'pass' });
}

function buyPass(api) {
  confirm('Nobles Pass', 'Unlock the premium reward lane for this season for 169 gems?', { okLabel: 'UNLOCK · 169' }).then((ok) => {
    if (!ok) return;
    if (state.gems < 169) { sfx('error'); toast('Not enough gems', { iconName: 'gem' }); return; }
    state.gems -= 169; state.passPremium = true; save(); emit('currency', {}); sfx('reward');
    burst(300, 540, 'gem', 18); toast('Nobles Pass unlocked!', { iconName: 'shield' });
    api.close(); pass();
  });
}

function rewardCard(t, lane, api) {
  const r = t[lane]; const id = `pass:${t.tier}:${lane}`;
  const claimed = !!state.claimed[id];
  const lockedLane = lane === 'premium' && !state.passPremium;
  const reached = t.tier <= state.passTier;
  const claimable = reached && !claimed && !lockedLane;
  const isSkin = r.kind === 'skin', isPin = r.kind === 'pin', isBrawler = r.kind === 'brawler';
  const br = (isSkin || isPin || isBrawler) ? game.brawlers.brawlers.find((b) => b.id === (r.brawler || r.id) || (r.name || '').toLowerCase().includes(b.name.toLowerCase())) : null;
  let art;
  if (isPin) art = h('div.pin-frame', h('img', { src: url(br.art) }), h('div.pin-bubble', {}, '•••'));
  else if (isSkin) art = h('img.rw-art.big', { src: skinArt(r.name, br) });
  else if (isBrawler) art = h('img.rw-art.big', { src: url(br.art) });
  else art = h('img.rw-art', { src: slot('icons.' + (r.kind === 'dawg_treat' ? (r.minTier >= 3 ? 'treat_epic' : 'treat_rare') : kindIcon[r.kind] || 'token')) });
  const label = isPin ? h('div.rw-name.t', {}, `${br.name}'S`, h('br'), 'NEW PIN') : isSkin ? h('div.rw-name.t', {}, 'NEW SKIN', h('br'), r.name.toUpperCase()) : isBrawler ? h('div.rw-name.t', {}, 'NEW BRAWLER', h('br'), br.name) : h('div.rw-amt', icon(kindIcon[r.kind] || 'token'), h('span.num.t.outline.hair', {}, fmt(r.amount)));
  const cell = h('div.rcard.' + lane + (claimed ? '.claimed' : claimable ? '.claimable' : '.locked') + (isSkin ? '.plus' : ''),
    lockedLane && !claimed ? h('div.rlock', icon('lock')) : null,
    claimed ? h('div.rcheck', icon('check')) : null,
    isSkin ? h('div.plus-tag.t.outline.hair', {}, 'PLUS') : null,
    art, label);
  if (claimable) cell.addEventListener('click', () => {
    state.claimed[id] = true;
    if (r.kind === 'brawler') { state.unlocked[r.id] = true; emit('profile'); toast(`Unlocked ${br.name}!`, { iconName: 'brawlers' }); }
    else if (r.kind === 'skin') { state.ownedSkins[skinKey(br, r.name)] = true; toast(`${r.name} skin unlocked!`, { iconName: 'hanger' }); }
    else if (r.kind === 'pin') toast(`${r.name} unlocked!`, { iconName: 'star_points' });
    else if (r.kind === 'dawg_treat') { for (let i = 0; i < r.amount; i++) setTimeout(() => openStarDrop(r.minTier || 0), 300 + i * 120); }
    else { addCurrency(r.kind, r.amount); toast(`+${fmt(r.amount)} ${kindLabel[r.kind] || r.kind}`, { iconName: kindIcon[r.kind] || 'token' }); }
    save(); sfx('reward');
    const c = centerOf(cell); burst(c.x, c.y, kindIcon[r.kind] || 'star_points', 12);
    cell.classList.remove('claimable'); cell.classList.add('claimed'); cell.prepend(h('div.rcheck', icon('check')));
    renderHome();
  });
  else if (lockedLane && reached && !claimed) cell.addEventListener('click', () => { sfx('error'); toast('Get the Nobles Pass to claim this lane', { iconName: 'lock' }); });
  return cell;
}
