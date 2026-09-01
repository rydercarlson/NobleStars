// NEWS / FRIENDS / CLUB / INBOX

import { h, icon, fmt, openScreen, topbar, toast, stagger, flyTo, centerOf, popup } from '../ui.js';
import { state, save, emit } from '../state.js';
import { url } from '../assets.js';
import { game, renderHome } from '../main.js';
import { sfx } from '../audio.js';

const portraitOf = (id) => { const b = game.brawlers.brawlers.find((x) => x.id === id) || game.brawlers.brawlers[0]; return url(b.portrait); };

export function news() {
  openScreen((el, api) => {
    el.append(topbar(api, 'News'));
    const content = h('div.content.scroll'); const grid = h('div.grid.news-grid');
    for (const n of game.data.news) {
      grid.append(h('div.card.news-card', { style: { '--ac': n.accent } },
        h('div.tag.t', {}, n.tag), h('div.ttl.t.outline.thin', {}, n.title), h('div.body', {}, n.body), h('div.date', {}, n.date)));
    }
    stagger(grid, 60); content.append(grid); el.append(content);
  }, { name: 'news' });
}

export function friends() {
  openScreen((el, api) => {
    const list = game.data.friends;
    el.append(topbar(api, 'Friends', { sub: `${list.filter((f) => f.status === 'online').length} online` }));
    const content = h('div.content.scroll'); const rows = h('div.list');
    const sorted = [...list].sort((a, b) => order(a.status) - order(b.status));
    for (const f of sorted) {
      rows.append(h('div.plate.row',
        h('div.avatar', h('img', { src: portraitOf(f.brawler) }), h('div.status.' + f.status)),
        h('div.who', h('div.n.t', {}, f.name), h('div.s.' + (f.status === 'online' ? 'online' : ''), {}, f.activity)),
        h('div.tr', icon('trophy'), fmt(f.trophies)),
        f.status === 'online' ? h('button.btn.small.green', { onClick: () => { sfx('open'); toast(`Invite sent to ${f.name}`, { iconName: 'friends' }); } }, 'INVITE') : h('button.btn.small.grey', { onClick: () => toast(`${f.name} is ${f.status}`) }, 'PROFILE'),
      ));
    }
    stagger(rows, 50);
    content.append(rows);
    content.append(h('div', { style: { display: 'flex', justifyContent: 'center', marginTop: '26px' } },
      h('button.btn.blue', { onClick: () => popup('Add Friend', (body, p) => {
        const inp = h('input.text-input', { placeholder: 'Enter a player tag, e.g. #NOBLES' });
        body.append(inp, h('button.btn.green', { onClick: () => { if (!inp.value.trim()) { sfx('error'); return; } toast(`Friend request sent to ${inp.value.trim()}`, { iconName: 'check' }); p.close(); } }, 'SEND REQUEST'));
        setTimeout(() => inp.focus(), 50);
      }) }, 'ADD FRIEND')));
    el.append(content);
  }, { name: 'friends' });
}
const order = (s) => ({ online: 0, away: 1, offline: 2 })[s] ?? 3;

export function club() {
  openScreen((el, api) => {
    const c = game.data.club;
    el.append(topbar(api, 'Club'));
    const content = h('div.content');
    const left = h('div', { style: { display: 'flex', flexDirection: 'column', minHeight: 0 } });
    left.append(h('div.plate.club-head',
      h('div.emblem', icon('club')),
      h('div', { style: { flex: 1, minWidth: 0 } }, h('div.n.t.outline.thin', {}, c.name), h('div.tag', {}, `${c.tag} · ${c.type} · ${c.members}/${c.maxMembers} members`), h('div.desc', {}, c.description))));
    left.append(h('div.club-stats',
      h('div.stat', h('div.k', {}, 'Club trophies'), h('div.v', icon('trophy'), fmt(c.trophies))),
      h('div.stat', h('div.k', {}, 'Required'), h('div.v', icon('trophy'), fmt(c.required))),
      h('div.stat', h('div.k', {}, 'Members'), h('div.v', {}, `${c.members}/${c.maxMembers}`))));
    const roster = h('div.list', { style: { overflowY: 'auto', flex: 1, minHeight: 0, paddingRight: '4px', scrollbarWidth: 'none' } });
    const me = { ...c.roster.find((r) => r.isYou), name: state.name, trophies: state.trophies };
    const members = c.roster.map((r) => (r.isYou ? me : r)).sort((a, b) => b.trophies - a.trophies);
    members.forEach((r, i) => roster.append(h('div.plate.row' + (r.isYou ? '.me' : ''), { style: { minHeight: '84px', padding: '8px 18px' } },
      h('div.t', { style: { font: '30px/1 var(--font-display)', width: '46px', color: i < 3 ? 'var(--yellow-hi)' : 'var(--text-dim)' } }, '#' + (i + 1)),
      h('div.who', h('div.n.t', {}, r.name), h('div.s', {}, r.role)),
      h('div.tr', icon('trophy'), fmt(r.trophies)))));
    left.append(h('div.t.outline.hair', { style: { font: '28px/1 var(--font-display)', margin: '4px 0 10px' } }, 'MEMBERS'), roster);

    // chat
    const chat = h('div.plate.chat');
    const msgs = h('div.msgs');
    const all = [...c.chat, ...state.clubChat];
    const addMsg = (m, me = false) => { msgs.append(h('div.msg' + (me ? '.me' : ''), h('div.w', {}, m.who), h('div.txt', {}, m.text))); msgs.scrollTop = msgs.scrollHeight; };
    all.forEach((m) => addMsg(m, m.who === state.name));
    const inp = h('input', { placeholder: 'Say something to the club…', maxLength: 120 });
    const send = () => { const t = inp.value.trim(); if (!t) { sfx('error'); return; } const m = { who: state.name, text: t }; state.clubChat.push(m); save(); addMsg(m, true); inp.value = ''; sfx('click');
      setTimeout(() => addMsg({ who: 'Bulldog_Ben', text: replies[Math.floor(Math.random() * replies.length)] }), 900 + Math.random() * 1200); };
    inp.addEventListener('keydown', (e) => { if (e.key === 'Enter') send(); e.stopPropagation(); });
    chat.append(msgs, h('div.input', inp, h('button.btn.small.green', { onClick: send, dataset: { sfx: 'none' } }, 'SEND')));
    const cols = h('div.two-col', left, chat);
    content.append(cols); el.append(content);
  }, { name: 'club' });
}
const replies = ['gg', 'nice one', 'who wants to duo?', 'showdown weekend lets gooo', 'someone bring snacks to the auditorium', 'W club'];

export function inbox() {
  openScreen((el, api) => {
    const mail = game.data.inbox;
    el.append(topbar(api, 'Inbox'));
    const content = h('div.content.scroll'); const rows = h('div.list');
    const render = () => {
      rows.replaceChildren();
      for (const m of mail) {
        const unread = m.unread && !state.readMail[m.id];
        rows.append(h('div.plate.row.clickable' + (unread ? '.unread' : ''), { onClick: () => openMail(m, render) },
          h('div.avatar', icon('shield')),
          h('div.who', h('div.n.t', {}, m.title), h('div.s', {}, m.from)),
          m.reward && !state.claimed['mail:' + m.id] ? h('div.reward-pill', icon(m.reward.kind === 'gems' ? 'gem' : 'coin'), fmt(m.reward.amount)) : null,
          h('div.date', {}, m.date)));
      }
      stagger(rows, 50);
    };
    render();
    content.append(rows); el.append(content);
  }, { name: 'inbox' });
}

function openMail(m, onClose) {
  if (!state.readMail[m.id]) { state.readMail[m.id] = true; save(); renderHome(); }
  openScreen((el, api) => {
    el.append(topbar(api, 'Message'));
    const content = h('div.content.scroll');
    const v = h('div.plate.message-view', h('div.from', {}, `${m.from} · ${m.date}`), h('div.ttl.t.outline.thin', {}, m.title), h('div.body', {}, m.body));
    if (m.reward) {
      const claimed = !!state.claimed['mail:' + m.id];
      const btn = h('button.btn' + (claimed ? '.grey.disabled' : '.green'), { onClick: (e) => {
        state.claimed['mail:' + m.id] = true; state[m.reward.kind] += m.reward.amount; save(); emit('currency', {}); sfx('purchase');
        const c = centerOf(e.currentTarget); flyTo(c.x, c.y, m.reward.kind, 10);
        btn.className = 'btn grey disabled'; btn.textContent = 'CLAIMED';
        toast(`+${fmt(m.reward.amount)} ${m.reward.kind}`, { iconName: m.reward.kind === 'gems' ? 'gem' : 'coin' });
      } }, claimed ? 'CLAIMED' : [icon(m.reward.kind === 'gems' ? 'gem' : 'coin'), `CLAIM ${fmt(m.reward.amount)}`]);
      v.append(h('div', { style: { display: 'flex', gap: '14px', alignItems: 'center' } }, btn));
    }
    content.append(v); el.append(content);
    const onScreen = (e) => { if (e.detail.name === 'mail' && !e.detail.open) { document.removeEventListener('screen', onScreen); onClose(); } };
    document.addEventListener('screen', onScreen);
  }, { name: 'mail' });
}
