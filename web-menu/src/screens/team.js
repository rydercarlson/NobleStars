// Team slot invite popup + Skins popup (hanger button)

import { h, icon, fmt, popup, toast, stagger, burst, centerOf, drawer } from '../ui.js';
import { state, save, emit, canAfford, spend } from '../state.js';
import { url } from '../assets.js';
import { game, currentBrawler, inviteFriend, renderHome } from '../main.js';
import { sfx } from '../audio.js';
import { skinArt } from './shop.js';

export function teamInvite(slotN = '1') {
  const friendsTab = (body, api) => {
    const list = h('div.list');
    const friends = [...game.data.friends].sort((a, b) => (a.status === 'online' ? 0 : 1) - (b.status === 'online' ? 0 : 1));
    for (const f of friends) {
      const br = game.brawlers.brawlers.find((x) => x.id === f.brawler) || game.brawlers.brawlers[0];
      const taken = state.team1 === f.id || state.team2 === f.id;
      list.append(h('div.plate.row', { style: { minHeight: '90px' } },
        h('div.avatar', h('img', { src: url(br.art) }), h('div.status.' + f.status)),
        h('div.who', h('div.n.t', {}, f.name), h('div.s.' + (f.status === 'online' ? 'online' : ''), {}, f.activity)),
        h('div.tr', icon('trophy'), fmt(f.trophies)),
        taken ? h('button.btn.small.grey.disabled', {}, 'IN TEAM') : f.status === 'online'
          ? h('button.btn.small.green', { onClick: () => { inviteFriend(f, slotN); api.close(); } }, 'INVITE')
          : h('button.btn.small.grey', { onClick: () => { sfx('error'); toast(`${f.name} is ${f.status}`); } }, 'OFFLINE')));
    }
    stagger(list, 40); body.append(list);
  };
  const clubTab = (body, api) => {
    const list = h('div.list');
    for (const r of game.data.club.roster.filter((x) => !x.isYou)) {
      const f = game.data.friends.find((x) => x.name === r.name); const online = f && f.status === 'online';
      const br = game.brawlers.brawlers.find((x) => x.id === f?.brawler) || game.brawlers.brawlers[1];
      list.append(h('div.plate.row', { style: { minHeight: '90px' } },
        h('div.avatar', h('img', { src: url(br.art) }), h('div.status.' + (online ? 'online' : 'offline'))),
        h('div.who', h('div.n.t', {}, r.name), h('div.s', {}, r.role)), h('div.tr', icon('trophy'), fmt(r.trophies)),
        online && f && !(state.team1 === f.id || state.team2 === f.id) ? h('button.btn.small.green', { onClick: () => { inviteFriend(f, slotN); api.close(); } }, 'INVITE') : h('button.btn.small.grey.disabled', {}, online ? 'IN TEAM' : 'OFFLINE')));
    }
    stagger(list, 40); body.append(list);
  };
  drawer('Invite to team', null, { name: 'team-invite', tabs: [{ id: 'friends', label: 'FRIENDS', build: friendsTab }, { id: 'club', label: 'CLUB', build: clubTab }] });
}

const SKINS = {
  leon: [{ id: 'default', name: 'Leon', price: 0 }, { id: 'homecoming', name: 'Homecoming Leon', price: 900, accent: '#ffc21a' }, { id: 'field_day', name: 'Field Day Leon', price: 1500, accent: '#57c81e' }],
  sanjit: [{ id: 'default', name: 'Sanjit', price: 0 }, { id: 'black_belt', name: 'Black Belt Sanjit', price: 900, accent: '#1d2030' }],
  tony: [{ id: 'default', name: 'Tony', price: 0 }, { id: 'field_day', name: 'Field Day Tony', price: 900, accent: '#57c81e' }],
  kovacs: [{ id: 'default', name: 'Kovacs', price: 0 }, { id: 'varsity', name: 'Varsity Kovacs', price: 1500, accent: '#1f4fdc' }],
  henry: [{ id: 'default', name: 'Henry', price: 0 }, { id: 'lifeguard', name: 'Lifeguard Henry', price: 1500, accent: '#ea3b3b' }],
};

export function skins() {
  const b = currentBrawler(); const list = SKINS[b.id] || [{ id: 'default', name: b.name, price: 0 }];
  popup(b.name + ' skins', (body, api) => {
    const grid = h('div.grid', { style: { gridTemplateColumns: 'repeat(3, 1fr)' } });
    const cur = state.skins[b.id] || 'default';
    for (const s of list) {
      const owned = s.price === 0 || !!state.ownedSkins[b.id + ':' + s.id];
      const selected = cur === s.id;
      const card = h('div.card.skin-item' + (selected ? '.selected' : ''), { style: { outline: selected ? '5px solid var(--yellow)' : 'none', outlineOffset: '-2px' } },
        h('div.ic.portrait', { style: { background: s.accent ? `radial-gradient(ellipse at 50% 30%, ${s.accent}, #10131f 80%)` : '#10131f' } }, h('img', { src: skinArt(s.name, b), style: { filter: s.accent && !(game.skinArt && game.skinArt[s.name]) ? `drop-shadow(0 0 0 ${s.accent}) hue-rotate(18deg)` : 'none' } })),
        h('div.amt.t.outline.thin', {}, s.name.toUpperCase()),
        owned ? h('button.btn' + (selected ? '.grey.disabled' : '.yellow'), { onClick: () => { state.skins[b.id] = s.id; save(); sfx('reward'); toast(`${s.name} equipped`, { iconName: 'check' }); api.close(); skins(); } }, selected ? 'EQUIPPED' : 'EQUIP')
          : h('button.btn.blue', { onClick: (e) => {
            if (!canAfford('bling', s.price)) { sfx('error'); toast('Not enough Bling', { iconName: 'bling' }); return; }
            spend('bling', s.price); state.ownedSkins[b.id + ':' + s.id] = true; state.skins[b.id] = s.id; save(); emit('currency', {}); sfx('purchase');
            const c = centerOf(e.currentTarget); burst(c.x, c.y - 40, 'dawg_treat', 12); toast(`${s.name} unlocked!`, { iconName: 'dawg_treat' }); api.close(); skins();
          } }, icon('bling'), h('span.price', {}, fmt(s.price))));
      grid.append(card);
    }
    stagger(grid, 60); body.append(grid);
    body.append(h('div', { style: { font: '800 20px var(--font-body)', color: 'var(--text-dim)', textAlign: 'center' } }, 'Skins cost Bling (cosmetic currency). 3D skin models come later — this build previews the color.'));
  }, { name: 'skins', wide: true });
}
