// SHOP — Brawl-style: bottom tabs (OFFERS / DAILY DEALS / SKINS / RESOURCES), big offer
// cards with timer ribbons, strikethrough "was" prices, OFF / value badges. Purchases update
// state and fly currency particles. Also owns the Dawg Treat reveal (openStarDrop).

import { h, icon, fmt, openScreen, toast, stagger, burst, flyTo, centerOf, confirm, $$ } from '../ui.js';
import { state, save, emit, canAfford, spend, addCurrency } from '../state.js';
import { url, slot } from '../assets.js';
import { game, renderHome } from '../main.js';
import { sfx } from '../audio.js';

const kindIcon = { coins: 'coin', gems: 'gem', power_points: 'power_point', dawg_treat: 'dawg_treat', bling: 'bling', gadget: 'gadget', pin: 'token' };
const kindLabel = { coins: 'COINS', gems: 'GEMS', power_points: 'POWER POINTS', dawg_treat: 'DAWG TREAT', bling: 'BLING', gadget: 'TRICK' };
const curIcon = { gems: 'gem', coins: 'coin', bling: 'bling', power_points: 'power_point' };
const brawlerOf = (id) => game.brawlers.brawlers.find((b) => b.id === id);
export const skinArt = (skin, br) => (game.skinArt && game.skinArt[skin]) || url(br.art);
/** 'Field Day Tony' + tony → 'tony:field_day' (matches the ids in team.js SKINS) */
export const skinKey = (br, name) => br.id + ':' + name.replace(new RegExp(br.name, 'i'), '').trim().toLowerCase().replace(/\s+/g, '_');
const treatIcon = (minTier = 0) => 'treat_' + (minTier >= 4 ? 'legendary' : minTier >= 3 ? 'epic' : minTier >= 1 ? 'rare' : 'common');

function resetTime() {
  const now = new Date(); const end = new Date(now); end.setHours(24, 0, 0, 0);
  const s = Math.floor((end - now) / 1000); return `${Math.floor(s / 3600)}h ${Math.floor((s % 3600) / 60)}m`;
}
const hoursLeft = (hrs) => (hrs >= 24 ? `${Math.floor(hrs / 24)}d ${hrs % 24}h` : `${hrs}h ${(37 + hrs * 7) % 60}m`);

const TABS = [['offers', 'OFFERS', 'shop'], ['daily', 'DAILY DEALS', 'token'], ['skins', 'SKINS', 'hanger'], ['resources', 'RESOURCES', 'gem']];

export function shop(startTab = 'offers') {
  openScreen((el, api) => {
    const d = game.data.shop;
    el.querySelector('.screen-bg').classList.add('shop-bg');
    let tab = startTab;

    const bar = h('div.topbar.shop-top',
      h('button.btn-back', { onClick: () => api.close(), dataset: { sfx: 'back' } }, icon('back')),
      h('div.title.t.outline', {}, 'SHOP'),
      h('div.spacer'),
      h('div.currency.plate', icon('coin'), h('span.v.num.cur-coins', {}, fmt(state.coins))),
      h('div.currency.plate', icon('gem'), h('span.v.num.cur-gems', {}, fmt(state.gems))),
      h('div.currency.plate', icon('bling'), h('span.v.num.cur-bling', {}, fmt(state.bling))),
      h('button.btn-close', { onClick: () => api.close(), dataset: { sfx: 'back' } }, icon('close')));
    const body = h('div.shop-body');
    const tabs = h('div.shop-tabs');
    for (const [id, label, ic] of TABS) tabs.append(h('button.shop-tab' + (id === tab ? '.on' : ''), { dataset: { id }, onClick: () => { tab = id; sfx('click'); render(); } }, icon(ic), h('span.t', {}, label)));
    el.append(bar, body, tabs);

    function render() {
      $$('.shop-tab', tabs).forEach((b) => b.classList.toggle('on', b.dataset.id === tab));
      body.replaceChildren(); body.classList.toggle('vscroll', tab === 'resources');
      const row = h('div.shop-row');
      if (tab === 'offers') { for (const o of d.offers) row.append(offerCard(o, api)); }
      else if (tab === 'daily') { body.append(h('div.shop-h.t.outline.thin', {}, 'DAILY DEALS', h('span.timer', {}, 'New deals in ' + resetTime()))); for (const it of d.daily) row.append(dailyCard(it)); row.classList.add('daily'); }
      else if (tab === 'skins') { for (const sk of d.skins) row.append(skinCard(sk)); row.classList.add('skins'); }
      else { body.append(h('div.shop-h.t.outline.thin', {}, 'RESOURCES')); for (const r of d.resources) row.append(resourceCard(r)); body.append(row); const gh = h('div.shop-h.t.outline.thin', {}, 'GEMS'); const gr = h('div.shop-row.gems'); for (const g of d.gems) gr.append(gemCard(g)); body.append(gh, gr); stagger(gr, 40); }
      if (tab !== 'resources') body.append(row);
      stagger(row, 55);
      body.scrollLeft = 0;
    }
    render();
    body.addEventListener('wheel', (e) => { if (Math.abs(e.deltaY) > Math.abs(e.deltaX)) { body.scrollLeft += e.deltaY; e.preventDefault(); } }, { passive: false });
    let dx = null, sl = 0; body.addEventListener('pointerdown', (e) => { dx = e.clientX; sl = body.scrollLeft; });
    const scale = () => parseFloat(getComputedStyle(document.querySelector('#stage')).getPropertyValue('--stage-scale')) || 1;
    window.addEventListener('pointermove', (e) => { if (dx == null) return; body.scrollLeft = sl - (e.clientX - dx) / scale(); });
    window.addEventListener('pointerup', () => { dx = null; });
  }, { name: 'shop' });
}

// ---------------------------------------------------------------- cards
function ribbon(o) { return o.hours ? h('div.ribbon-timer', icon('token'), h('span.num', {}, hoursLeft(o.hours))) : null; }

function offerCard(o, api) {
  const claimed = !!state.claimed[o.id];
  const card = h('div.ocard' + (o.wide ? '.wide' : '') + (claimed ? '.claimed' : ''), { style: { '--ac': o.accent } }, ribbon(o));
  if (o.kind === 'free_brawler') {
    const br = brawlerOf(o.brawler); const owned = !!state.unlocked[br.id];
    card.append(h('div.oc-title.t.outline.hair', {}, o.title), h('img.oc-art.big', { src: url(br.art) }),
      h('div.oc-name.t.outline.hair', {}, br.name),
      owned ? h('button.btn.grey.disabled', {}, 'UNLOCKED') : h('button.btn.green', { onClick: async (e) => {
        const ok = await confirm('Nobles ID', `Connect your Nobles ID to unlock ${br.name} for free?`, { okLabel: 'CONNECT', okClass: 'green' }); if (!ok) return;
        state.unlocked[br.id] = true; state.claimed[o.id] = true; save(); emit('profile'); sfx('reward');
        const c = centerOf(e.currentTarget); burst(c.x, c.y - 80, 'star_points', 18); toast(`Unlocked ${br.name}!`, { iconName: 'brawlers' });
        e.currentTarget.replaceWith(h('button.btn.grey.disabled', {}, 'UNLOCKED')); renderHome();
      } }, o.cta || 'CONNECT'));
  } else if (o.kind === 'bundle') {
    const items = h('div.oc-items');
    for (const c of o.contents) items.append(h('div.oc-item', c.kind === 'dawg_treat' ? icon('treat_epic') : icon(kindIcon[c.kind]), h('div.t.outline.hair', {}, c.label || `${fmt(c.amount)} ${kindLabel[c.kind]}`)));
    card.append(o.badge ? h('div.badge-new.t.outline.hair', {}, o.badge) : null, h('div.oc-title.t.outline.hair', {}, o.title.toUpperCase()), items,
      o.value ? h('div.value-tag.t.outline.hair', {}, `${o.value} VALUE`) : null,
      priceButton(o, claimed, (btn) => buy(o, btn, () => { for (const c of o.contents) { if (c.kind === 'dawg_treat') setTimeout(() => openStarDrop(3), 300); else addCurrency(c.kind, c.amount); } })));
  } else if (o.kind === 'brawler_offer') {
    const br = brawlerOf(o.brawler); const owned = !!state.unlocked[br.id];
    card.append(h('div.oc-title.t.outline.hair', {}, o.title), h('img.oc-art.big', { src: url(br.art) }), h('div.oc-name.t.outline.hair', {}, `NEW BRAWLER · ${br.name}`),
      h('div.oc-rarity.t.outline.hair', { style: { color: game.brawlers.rarities[br.rarity]?.hi || '#fff' } }, (game.brawlers.rarities[br.rarity]?.label || '').toUpperCase()),
      owned ? h('button.btn.grey.disabled', {}, 'UNLOCKED') : priceButton(o, claimed, (btn) => buy(o, btn, () => { state.unlocked[br.id] = true; emit('profile'); toast(`Unlocked ${br.name}!`, { iconName: 'brawlers' }); renderHome(); })));
  } else if (o.kind === 'skin_offer') {
    const br = brawlerOf(o.brawler); const key = skinKey(br, o.skin); const owned = !!state.ownedSkins[key];
    card.append(h('div.oc-title.t.outline.hair', {}, o.title), o.off ? h('div.off-tag.t.outline.hair', {}, o.off) : null,
      h('img.oc-art.big.skin', { src: skinArt(o.skin, br) }), h('div.oc-name.t.outline.hair', {}, 'NEW SKIN', h('br'), o.skin.toUpperCase()),
      owned ? h('button.btn.grey.disabled', {}, 'OWNED') : priceButton(o, claimed, (btn) => buy(o, btn, () => { state.ownedSkins[key] = true; toast(`${o.skin} unlocked!`, { iconName: 'hanger' }); })));
  } else if (o.kind === 'treat_pack') {
    card.append(h('div.oc-title.t.outline.hair', {}, o.title),
      h('div.treat-stack', ...Array.from({ length: Math.min(o.count, 4) }, (_, i) => h('img', { src: slot('icons.' + treatIcon(o.minTier)), style: { '--i': i } }))),
      h('div.oc-name.t.outline.hair', {}, `${o.count}× ${o.label}`),
      o.value ? h('div.value-tag.t.outline.hair', {}, `${o.value} VALUE`) : null,
      priceButton(o, false, (btn) => buy(o, btn, () => { for (let i = 0; i < o.count; i++) setTimeout(() => openStarDrop(o.minTier || 0), 300 + i * 150); }, { repeatable: true })));
  }
  return card;
}

function dailyCard(it) {
  const claimed = !!state.claimed[it.id];
  const br = it.brawler ? brawlerOf(it.brawler) : null;
  const card = h('div.ocard.small' + (claimed ? '.claimed' : ''),
    it.currency === 'free' && !claimed ? h('div.free-tag.t.outline.hair', {}, 'FREE') : null,
    it.kind === 'gadget' ? h('div.oc-gadget', h('img', { src: url(br.art) }), icon('gadget', 'gi'))
      : it.kind === 'dawg_treat' ? h('img.oc-art', { src: slot('icons.' + treatIcon(it.minTier)) })
      : h('img.oc-art', { src: slot('icons.' + kindIcon[it.kind]) }),
    h('div.oc-name.t.outline.hair', {}, it.amount ? `${fmt(it.amount)} ${kindLabel[it.kind]}` : (it.name || '').toUpperCase()),
    br ? h('div.oc-sub', {}, br.name) : h('div.oc-sub', {}, it.label === 'FREE TREAT' ? 'Daily gift' : 'Daily deal'),
    priceButton(it, claimed, (btn) => buy(it, btn, () => applyItem(it))));
  return card;
}

function skinCard(sk) {
  const br = brawlerOf(sk.brawler); const key = skinKey(br, sk.name); const owned = !!state.ownedSkins[key];
  const item = { id: 'skin:' + key, price: sk.price, currency: sk.currency, kind: 'skin' };
  return h('div.ocard.skin' + (owned ? '.claimed' : ''), { style: { '--ac': sk.accent } },
    h('div.oc-title.t.outline.hair', {}, (sk.rarity || '').replace('_', ' ').toUpperCase() + ' SKIN'),
    h('img.oc-art.big.skin', { src: skinArt(sk.name, br) }), h('div.oc-name.t.outline.hair', {}, sk.name.toUpperCase()),
    owned ? h('button.btn.grey.disabled', {}, 'OWNED') : priceButton(item, false, (btn) => buy(item, btn, () => { state.ownedSkins[key] = true; toast(`${sk.name} unlocked!`, { iconName: 'hanger' }); })));
}

function resourceCard(r) {
  const item = { ...r, id: r.id + ':' + Date.now() };
  return h('div.ocard.small.res', r.value ? h('div.value-tag.t.outline.hair', {}, r.value) : null,
    h('img.oc-art', { src: slot('icons.' + (r.kind === 'dawg_treat' ? treatIcon(r.minTier) : kindIcon[r.kind])) }),
    h('div.oc-name.t.outline.hair', {}, r.kind === 'dawg_treat' ? (r.label || 'DAWG TREAT') : `${fmt(r.amount)} ${kindLabel[r.kind]}`),
    priceButton(item, false, (btn) => buy(item, btn, () => applyItem(r), { repeatable: true })));
}

function gemCard(g) {
  return h('div.ocard.small.gems', h('img.oc-art', { src: slot('icons.gem') }), h('div.oc-name.t.outline.hair', {}, `${fmt(g.amount)} GEMS`),
    h('button.btn.green', { onClick: async (e) => {
      const ok = await confirm('Get Gems', `This is a demo build — no real purchases. Add ${g.amount} gems to your account?`, { okLabel: 'ADD GEMS', okClass: 'green' });
      if (!ok) return;
      addCurrency('gems', g.amount); sfx('purchase');
      const c = centerOf(e.currentTarget); flyTo(c.x, c.y, 'gems', 10); toast(`+${g.amount} gems`, { iconName: 'gem' });
    } }, g.price));
}

// ---------------------------------------------------------------- buying
function priceButton(item, claimed, onBuy) {
  if (claimed) return h('button.btn.grey.disabled', {}, item.claimedLabel || 'PURCHASED');
  const free = item.currency === 'free', usd = item.currency === 'usd';
  const btn = h('button.btn' + (free || usd ? '.green' : item.currency === 'gems' ? '.blue' : item.currency === 'bling' ? '.grey' : '.yellow'), { dataset: { sfx: 'none' } },
    free ? (item.label || 'FREE') : usd ? item.price : [icon(curIcon[item.currency] || 'coin'), h('span.price', {}, fmt(item.price))]);
  btn.addEventListener('click', () => onBuy(btn));
  if (item.was) return h('div.price-wrap', h('div.was', icon(curIcon[item.currency] || 'coin'), h('s.num', {}, fmt(item.was))), btn);
  return btn;
}

function buy(item, btn, apply, { repeatable = false } = {}) {
  if (item.currency === 'usd') {
    confirm('Purchase', `This is a demo build — no real purchases. Add ${item.title || 'this pack'} for ${item.price}?`, { okLabel: 'BUY', okClass: 'green' }).then((ok) => { if (ok) finish(); });
    return;
  }
  if (!canAfford(item.currency, item.price)) {
    sfx('error'); toast(`Not enough ${item.currency.replace('_', ' ')}`, { iconName: curIcon[item.currency] || 'coin' });
    btn.animate([{ transform: 'translateX(0)' }, { transform: 'translateX(-8px)' }, { transform: 'translateX(8px)' }, { transform: 'translateX(0)' }], { duration: 240 });
    return;
  }
  spend(item.currency, item.price); finish();
  function finish() {
    if (!repeatable) state.claimed[item.id] = true;
    apply && apply(); save(); emit('currency', {});
    sfx(item.kind === 'dawg_treat' ? 'reward' : 'purchase');
    const c = centerOf(btn);
    if (item.kind === 'coins') flyTo(c.x, c.y, 'coins', 10); else burst(c.x, c.y - 60, kindIcon[item.kind] || 'dawg_treat', 12);
    if (!repeatable) { const card = btn.closest('.ocard'); if (card) card.classList.add('claimed'); btn.replaceWith(h('button.btn.grey.disabled', {}, item.claimedLabel || 'PURCHASED')); }
    if (item.kind === 'dawg_treat') for (let i = 0; i < (item.amount || 1); i++) setTimeout(() => openStarDrop(item.minTier || 0), 250 + i * 150);
  }
}

function applyItem(it) {
  if (it.kind === 'coins' || it.kind === 'gems' || it.kind === 'bling') addCurrency(it.kind, it.amount);
  if (it.kind === 'power_points') addCurrency('power_points', it.amount);
  if (it.kind === 'gadget' && it.brawler) { state.equipment = state.equipment || {}; state.equipment[it.brawler + ':gadget'] = true; }
  save();
}

/** Dawg Treat opening: full-screen reveal with the rarity tiers (Common → Ultra Legendary). */
export const TREATS = [
  { id: 'common',      label: 'COMMON',          p: 0.34, color: '#c9d1e6', bg: '#5f6a8a', reward: { kind: 'coins', amount: 100 } },
  { id: 'rare',        label: 'RARE',            p: 0.28, color: '#7cf53a', bg: '#2e9a2b', reward: { kind: 'coins', amount: 250 } },
  { id: 'super_rare',  label: 'SUPER RARE',      p: 0.17, color: '#5fa8ff', bg: '#1f4fdc', reward: { kind: 'power_points', amount: 100 } },
  { id: 'epic',        label: 'EPIC',            p: 0.11, color: '#e06bff', bg: '#7a1fbf', reward: { kind: 'gems', amount: 30 } },
  { id: 'mythic',      label: 'MYTHIC',          p: 0.06, color: '#ff5f5f', bg: '#b3182a', reward: { kind: 'brawler', id: 'kovacs' } },
  { id: 'legendary',   label: 'LEGENDARY',       p: 0.03, color: '#ffe14f', bg: '#e6a100', reward: { kind: 'brawler', id: 'henry' } },
  { id: 'ultra',       label: 'ULTRA LEGENDARY', p: 0.01, color: '#fff', bg: 'linear-gradient(135deg, #ff5f5f, #ffcf3a 30%, #52e07a 55%, #4fa9ff 78%, #c86bff)', rainbow: true, reward: { kind: 'gems', amount: 250 } },
];

export function rollTreat(minTier = 0) {
  const pool = TREATS.slice(minTier); const total = pool.reduce((a, t) => a + t.p, 0);
  let r = Math.random() * total; let pick = pool[0];
  for (const t of pool) { if (r < t.p) { pick = t; break; } r -= t.p; }
  let reward = pick.reward;
  if (reward.kind === 'brawler' && state.unlocked[reward.id]) reward = { kind: 'gems', amount: pick.id === 'legendary' ? 120 : 80 };
  return { ...pick, reward };
}

export function openStarDrop(minTier = 0) {
  const pick = rollTreat(minTier);
  openScreen((el, api) => {
    el.querySelector('.screen-bg').remove();
    const bg = h('div.treat-bg');
    const wrap = h('div.treat-wrap');
    const label = h('div.treat-label.t.outline', {}, 'DAWG TREAT');
    const treatImg = icon('treat_common', 'treat-img');
    const hint = h('div.treat-hint.t.outline.thin', {}, 'TAP TO OPEN!');
    wrap.append(label, treatImg, hint); el.append(bg, wrap);
    // escalate: shake through the tiers before landing on the roll (Brawl-style "chance to upgrade")
    const idx = TREATS.indexOf(TREATS.find((t) => t.id === pick.id));
    let stage = 0, opened = false;
    const setTier = (i) => { const t = TREATS[i]; bg.style.background = t.bg; bg.classList.toggle('rainbow', !!t.rainbow); label.textContent = t.label; label.style.color = t.color; treatImg.src = slot('icons.treat_' + t.id); };
    setTier(0);
    const step = () => {
      if (stage >= idx) return;
      stage++; setTier(stage); sfx('tick');
      treatImg.animate([{ transform: 'scale(1)' }, { transform: 'scale(1.25) rotate(-6deg)' }, { transform: 'scale(1)' }], { duration: 260, easing: 'cubic-bezier(.2,1.4,.4,1)' });
      const c = centerOf(treatImg); burst(c.x, c.y, 'star_points', 8);
      setTimeout(step, 520);
    };
    setTimeout(step, 700);
    const open = () => {
      if (opened || stage < idx) return; opened = true; sfx('reward'); hint.remove();
      treatImg.animate([{ transform: 'scale(1)' }, { transform: 'scale(1.4) rotate(12deg)' }, { transform: 'scale(0)' }], { duration: 450, fill: 'forwards' });
      setTimeout(() => {
        const rw = pick.reward; let rewardEl;
        if (rw.kind === 'brawler') {
          const b = game.brawlers.brawlers.find((x) => x.id === rw.id);
          state.unlocked[rw.id] = true; save(); emit('profile');
          rewardEl = h('div.treat-reward', h('img', { src: url(b.art), style: { height: '300px' } }), h('div.t.outline', { style: { font: '54px/1 var(--font-display)' } }, 'NEW BRAWLER: ' + b.name));
        } else {
          addCurrency(rw.kind, rw.amount);
          rewardEl = h('div.treat-reward', h('div', { style: { display: 'flex', alignItems: 'center', gap: '20px' } }, icon(rw.kind === 'gems' ? 'gem' : rw.kind === 'power_points' ? 'power_point' : 'coin'), h('div.t.outline', { style: { font: '100px/1 var(--font-display)' } }, '+' + fmt(rw.amount))),
            h('div.t.outline.thin', { style: { font: '34px/1 var(--font-display)', color: pick.color } }, ({ coins: 'COINS', gems: 'GEMS', power_points: 'POWER POINTS' })[rw.kind]));
          rewardEl.querySelector('img').style.height = '120px';
        }
        treatImg.replaceWith(rewardEl); rewardEl.animate([{ transform: 'scale(0)' }, { transform: 'scale(1.15)' }, { transform: 'scale(1)' }], { duration: 450, easing: 'cubic-bezier(.2,1.4,.4,1)' });
        const c = centerOf(rewardEl); burst(c.x, c.y, 'star_points', 22);
        wrap.append(h('button.btn.yellow.big', { onClick: () => { api.close(); renderHome(); }, style: { marginTop: '10px' } }, 'AWESOME'));
      }, 420);
    };
    wrap.addEventListener('click', open);
    bg.addEventListener('click', open);
  }, { name: 'dawgtreat', popup: true });
}
