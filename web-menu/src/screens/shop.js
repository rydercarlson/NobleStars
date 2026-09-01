// SHOP: daily deals, offers, gem packs. Purchases update state + fly currency particles.

import { h, icon, fmt, openScreen, topbar, toast, stagger, burst, flyTo, centerOf, confirm, popup } from '../ui.js';
import { state, save, emit, canAfford, spend } from '../state.js';
import { url } from '../assets.js';
import { game } from '../main.js';
import { sfx } from '../audio.js';

const kindIcon = { coins: 'coin', gems: 'gem', power_points: 'power_point', star_drop: 'star_drop', gadget: 'token', skin: null, pin: 'token', bundle: 'star_drop' };
const kindLabel = { coins: 'Coins', gems: 'Gems', power_points: 'Power Points', star_drop: 'Star Drop', gadget: 'Gadget', skin: 'Skin', pin: 'Pin' };

function resetTime() {
  const now = new Date(); const end = new Date(now); end.setHours(24, 0, 0, 0);
  const s = Math.floor((end - now) / 1000); return `${Math.floor(s / 3600)}h ${Math.floor((s % 3600) / 60)}m`;
}

export function shop() {
  openScreen((el, api) => {
    const d = game.data.shop;
    el.append(topbar(api, 'Shop'));
    const content = h('div.content.scroll');

    // ---- offers
    const offers = h('section.shop-section', h('h2.t.outline.thin', {}, 'Special Offers'));
    const og = h('div.grid.offer-grid');
    for (const o of d.offers) {
      const claimed = !!state.claimed[o.id];
      const card = h('div.card.offer', { style: { '--ac': o.accent } },
        h('div.left', h('div.name.t.outline.thin', {}, o.name), h('ul', o.contents.map((c) => h('li', {}, c))),
          priceButton(o, claimed, (btn) => buy(o, btn, () => { if (o.kind === 'bundle') { state.coins += 2000; state.starPoints += 100; } }))),
        h('div.art', icon(o.kind === 'bundle' ? 'star_drop' : 'star_drop')),
        o.badge ? h('div.badge.t.outline.hair', {}, o.badge) : null,
      );
      og.append(card);
    }
    stagger(og, 60); offers.append(og); content.append(offers);

    // ---- daily deals
    const daily = h('section.shop-section', h('h2.t.outline.thin', {}, 'Daily Deals', h('span.timer', {}, 'Resets in ' + resetTime())));
    const dg = h('div.grid.shop-grid');
    for (const it of d.daily) {
      const claimed = !!state.claimed[it.id];
      const br = it.brawler ? game.brawlers.brawlers.find((b) => b.id === it.brawler) : null;
      const isPortrait = it.kind === 'skin' || it.kind === 'gadget';
      const card = h('div.card.shop-item' + (claimed ? '.claimed' : ''),
        it.currency === 'free' && !claimed ? h('div.ribbon.t.outline.hair', {}, 'FREE') : null,
        h('div.ic' + (isPortrait ? '.portrait' : ''), isPortrait && br ? h('img', { src: url(br.portrait) }) : icon(kindIcon[it.kind] || 'token')),
        h('div.amt.t.outline.thin', {}, it.amount ? fmt(it.amount) : it.name),
        h('div.what', {}, (br ? br.name + ' · ' : '') + (kindLabel[it.kind] || it.kind)),
        priceButton(it, claimed, (btn) => buy(it, btn, () => applyItem(it))),
      );
      dg.append(card);
    }
    stagger(dg, 45); daily.append(dg); content.append(daily);

    // ---- gems
    const gems = h('section.shop-section', h('h2.t.outline.thin', {}, 'Gems'));
    const gg = h('div.grid.gem-grid');
    for (const g of d.gems) {
      const card = h('div.card.gem-pack', icon('gem'), h('div.amt.t.outline.thin', {}, fmt(g.amount)),
        h('button.btn.green', { onClick: async (e) => {
          const ok = await confirm('Get Gems', `This is a demo build — no real purchases. Add ${g.amount} gems to your account?`, { okLabel: 'ADD GEMS', okClass: 'green' });
          if (!ok) return;
          state.gems += g.amount; save(); emit('currency', {}); sfx('purchase');
          const c = centerOf(e.currentTarget); flyTo(c.x, c.y, 'gems', 10);
          toast(`+${g.amount} gems`, { iconName: 'gem' });
        } }, g.price));
      gg.append(card);
    }
    stagger(gg, 45); gems.append(gg); content.append(gems);
    el.append(content);
  }, { name: 'shop' });
}

function priceButton(item, claimed, onBuy) {
  if (claimed) return h('button.btn.grey.disabled', {}, item.claimedLabel || 'PURCHASED');
  const free = item.currency === 'free';
  const btn = h('button.btn' + (free ? '.green' : item.currency === 'gems' ? '.blue' : '.yellow'), { dataset: { sfx: 'none' } },
    free ? (item.label || 'FREE') : [icon(item.currency === 'gems' ? 'gem' : 'coin'), h('span.price', {}, fmt(item.price))]);
  btn.addEventListener('click', () => onBuy(btn));
  return btn;
}

function buy(item, btn, apply) {
  if (!canAfford(item.currency, item.price)) {
    sfx('error'); toast(`Not enough ${item.currency}`, { iconName: item.currency === 'gems' ? 'gem' : 'coin' });
    btn.animate([{ transform: 'translateX(0)' }, { transform: 'translateX(-8px)' }, { transform: 'translateX(8px)' }, { transform: 'translateX(0)' }], { duration: 240 });
    return;
  }
  spend(item.currency, item.price);
  state.claimed[item.id] = true; save();
  apply && apply();
  emit('currency', {});
  sfx(item.kind === 'star_drop' ? 'reward' : 'purchase');
  const c = centerOf(btn);
  if (item.kind === 'coins') flyTo(c.x, c.y, 'coins', 10); else burst(c.x, c.y - 60, kindIcon[item.kind] || 'star_drop', 12);
  const card = btn.closest('.card'); card.classList.add('claimed');
  btn.replaceWith(h('button.btn.grey.disabled', {}, item.claimedLabel || 'PURCHASED'));
  if (item.kind === 'star_drop') openStarDrop();
}

function applyItem(it) {
  if (it.kind === 'coins') state.coins += it.amount;
  if (it.kind === 'power_points' && it.brawler) { /* power points are abstracted: bump power on threshold */ const cur = state.brawlerPower[it.brawler] ?? game.brawlers.brawlers.find((b) => b.id === it.brawler).power; state.brawlerPower[it.brawler] = cur; }
  save();
}

/** Star Drop opening popup with escalating rarity reveal. */
export function openStarDrop() {
  const rolls = [
    { p: 0.5, label: 'RARE', color: '#6df26a', reward: { kind: 'coins', amount: 150 } },
    { p: 0.28, label: 'SUPER RARE', color: '#4f8dff', reward: { kind: 'coins', amount: 400 } },
    { p: 0.15, label: 'EPIC', color: '#c56cff', reward: { kind: 'gems', amount: 25 } },
    { p: 0.06, label: 'MYTHIC', color: '#ff5f5f', reward: { kind: 'brawler', id: 'kovacs' } },
    { p: 0.01, label: 'LEGENDARY', color: '#ffe14f', reward: { kind: 'brawler', id: 'henry' } },
  ];
  let r = Math.random(); let pick = rolls[0];
  for (const x of rolls) { if (r < x.p) { pick = x; break; } r -= x.p; }
  if (pick.reward.kind === 'brawler' && state.unlocked[pick.reward.id]) pick = { ...pick, reward: { kind: 'gems', amount: 60 } };

  popup('Star Drop', (body, api) => {
    const box = h('div', { style: { display: 'flex', flexDirection: 'column', alignItems: 'center', gap: '18px', padding: '10px 0' } });
    const star = icon('star_drop'); star.style.height = '200px'; star.style.filter = 'drop-shadow(0 10px 0 rgba(0,0,0,.4))';
    star.style.animation = 'bob 1.2s ease-in-out infinite';
    const label = h('div.t.outline', { style: { font: '54px/1 var(--font-display)', color: pick.color } }, 'TAP TO OPEN');
    box.append(star, label); body.append(box);
    let opened = false;
    const open = () => {
      if (opened) return; opened = true; sfx('reward');
      star.style.animation = 'none'; star.animate([{ transform: 'scale(1)' }, { transform: 'scale(1.5) rotate(20deg)' }, { transform: 'scale(0)' }], { duration: 500, fill: 'forwards' });
      setTimeout(() => {
        label.textContent = pick.label; label.style.color = pick.color;
        const rw = pick.reward; let rewardEl;
        if (rw.kind === 'brawler') {
          const b = game.brawlers.brawlers.find((x) => x.id === rw.id);
          state.unlocked[rw.id] = true; save(); emit('profile');
          rewardEl = h('div', { style: { textAlign: 'center' } }, h('img', { src: url(b.portrait), style: { height: '220px' } }), h('div.t.outline.thin', { style: { font: '44px/1 var(--font-display)' } }, 'NEW BRAWLER: ' + b.name));
        } else {
          state[rw.kind] += rw.amount; save(); emit('currency', {});
          rewardEl = h('div', { style: { display: 'flex', alignItems: 'center', gap: '16px' } }, icon(rw.kind === 'gems' ? 'gem' : 'coin', ''), h('div.t.outline', { style: { font: '70px/1 var(--font-display)' } }, '+' + fmt(rw.amount)));
          rewardEl.querySelector('img').style.height = '90px';
        }
        star.replaceWith(rewardEl); rewardEl.animate([{ transform: 'scale(0)' }, { transform: 'scale(1.15)' }, { transform: 'scale(1)' }], { duration: 450, easing: 'cubic-bezier(.2,1.4,.4,1)' });
        const c = centerOf(rewardEl); burst(c.x, c.y, 'star_drop', 16);
        box.append(h('button.btn.yellow', { onClick: () => api.close(), style: { marginTop: '10px' } }, 'AWESOME'));
      }, 450);
    };
    box.addEventListener('click', open);
  }, { name: 'stardrop' });
}
