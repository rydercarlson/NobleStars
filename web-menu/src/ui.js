// UI helpers: DOM building, press feedback, screens stack, popups, toasts, particles, counters.

import { sfx } from './audio.js';
import { slot } from './assets.js';
import { state } from './state.js';

export const $ = (sel, root = document) => root.querySelector(sel);
export const $$ = (sel, root = document) => Array.from(root.querySelectorAll(sel));

/** h('div.card.clickable', {onClick, style, dataset}, children...) */
export function h(tag, props = {}, ...children) {
  if (props == null || props.nodeType || typeof props !== 'object' || Array.isArray(props)) { children.unshift(props); props = {}; }
  const [name, ...classes] = tag.split('.');
  const el = document.createElement(name || 'div');
  if (classes.length) el.className = classes.join(' ');
  for (const k in props) {
    const v = props[k];
    if (v == null) continue;
    if (k === 'class') el.className += (el.className ? ' ' : '') + v;
    else if (k === 'style' && typeof v === 'object') Object.assign(el.style, v);
    else if (k === 'dataset') Object.assign(el.dataset, v);
    else if (k.startsWith('on') && typeof v === 'function') el.addEventListener(k.slice(2).toLowerCase(), v);
    else if (k === 'html') el.innerHTML = v;
    else if (k in el && k !== 'list') { try { el[k] = v; } catch (e) { el.setAttribute(k, v); } }
    else el.setAttribute(k, v);
  }
  for (const c of children.flat(Infinity)) {
    if (c == null || c === false) continue;
    el.append(c.nodeType ? c : document.createTextNode(String(c)));
  }
  return el;
}

export const icon = (name, cls = '') => h('img', { src: slot('icons.' + name), alt: '', class: cls });

export function fmt(n) { return Number(n || 0).toLocaleString('en-US'); }

/** Animate a number in an element from its current value to target. */
export function countTo(el, target, dur = 700) {
  const start = parseInt(String(el.textContent).replace(/[^\d-]/g, ''), 10) || 0;
  if (start === target) { el.textContent = fmt(target); return; }
  const t0 = performance.now();
  const tick = (now) => {
    const k = Math.min(1, (now - t0) / dur); const e = 1 - Math.pow(1 - k, 3);
    el.textContent = fmt(Math.round(start + (target - start) * e));
    if (k < 1) requestAnimationFrame(tick); else el.textContent = fmt(target);
  };
  requestAnimationFrame(tick);
}

/** Press feedback for anything clickable (pointer down -> .pressed, release -> click sound). */
export function installPressFeedback(root = document) {
  root.addEventListener('pointerdown', (e) => {
    const b = e.target.closest('button, .clickable, .card.clickable');
    if (!b || b.classList.contains('disabled')) return;
    b.classList.add('pressed');
    const up = () => { b.classList.remove('pressed'); window.removeEventListener('pointerup', up); window.removeEventListener('pointercancel', up); };
    window.addEventListener('pointerup', up); window.addEventListener('pointercancel', up);
  });
  root.addEventListener('click', (e) => {
    const b = e.target.closest('button, .clickable');
    if (!b || b.classList.contains('disabled')) return;
    if (b.dataset.sfx !== 'none') sfx(b.dataset.sfx || 'click');
  });
}

// ---------------------------------------------------------------- screens
const screensRoot = () => $('#screens');
const stack = [];

export function openScreen(build, { popup = false, name = '' } = {}) {
  const el = h('div.screen' + (popup ? '.popup-style' : ''), { dataset: { name } });
  el.append(h('div.screen-bg'));
  const api = { el, close: () => closeScreen(el), name };
  build(el, api);
  const below = stack[stack.length - 1];
  screensRoot().append(el);
  stack.push(el);
  if (below) { below.dataset.hiddenBy = '1'; setTimeout(() => { if (stack[stack.length - 1] !== below && stack.includes(below)) below.style.visibility = 'hidden'; }, 380); }
  $('#stage').classList.add('dimmed');
  $('#home').classList.add('hidden');
  if (!popup) sfx('open');
  document.dispatchEvent(new CustomEvent('screen', { detail: { open: true, name } }));
  return api;
}

export function closeScreen(el) {
  const i = stack.indexOf(el); if (i < 0) return;
  stack.splice(i, 1);
  el.classList.add('leaving');
  el.style.pointerEvents = 'none';
  setTimeout(() => el.remove(), 320);
  const top = stack[stack.length - 1]; if (top) top.style.visibility = '';
  if (!stack.length) { $('#stage').classList.remove('dimmed'); $('#home').classList.remove('hidden'); }
  document.dispatchEvent(new CustomEvent('screen', { detail: { open: false, name: el.dataset.name } }));
}

export function closeAllScreens() { [...stack].forEach(closeScreen); }
export function screenDepth() { return stack.length; }

/** Standard screen top bar: back button, title, optional subtitle, currency pills, close. */
export function topbar(api, title, { sub = '', currencies = true, close = true } = {}) {
  const bar = h('div.topbar',
    h('button.btn-back', { onClick: () => api.close(), dataset: { sfx: 'back' } }, icon('back')),
    h('div.title.t.outline', {}, title),
    sub ? h('div.sub.t', {}, sub) : null,
    h('div.spacer'),
    currencies ? currencyPills() : null,
    close ? h('button.btn-close', { onClick: () => api.close(), dataset: { sfx: 'back' } }, icon('close')) : null,
  );
  return bar;
}

export function currencyPills() {
  const wrap = h('div', { style: { display: 'flex', gap: '12px' } });
  const coins = h('button.currency.plate.clickable', { dataset: { sfx: 'click', open: 'shop' } }, icon('coin'), h('span.v.num.cur-coins', {}, fmt(state.coins)), h('span.plus', {}, '+'));
  const gems = h('button.currency.plate.clickable', { dataset: { sfx: 'click', open: 'shop' } }, icon('gem'), h('span.v.num.cur-gems', {}, fmt(state.gems)), h('span.plus', {}, '+'));
  wrap.append(coins, gems);
  return wrap;
}

export function refreshCurrencies() {
  $$('.cur-coins, #cur-coins').forEach((el) => countTo(el, state.coins));
  $$('.cur-gems, #cur-gems').forEach((el) => countTo(el, state.gems));
}

// ---------------------------------------------------------------- popups
export function popup(title, buildBody, { wide = false, name = 'popup' } = {}) {
  return openScreen((el, api) => {
    const box = h('div.popup.plate' + (wide ? '.wide' : ''),
      h('div.ph', h('div.title.t.outline.thin', {}, title), h('button.btn-close', { onClick: () => api.close(), dataset: { sfx: 'back' } }, icon('close'))),
    );
    const body = h('div.pb');
    buildBody(body, api);
    box.append(body);
    const wrap = h('div.popup-wrap', { onClick: (e) => { if (e.target === wrap) api.close(); } }, box);
    el.append(wrap);
  }, { popup: true, name });
}

export function confirm(title, text, { okLabel = 'OK', okClass = 'yellow', cancelLabel = 'CANCEL' } = {}) {
  return new Promise((resolve) => {
    let done = false;
    const p = popup(title, (body, api) => {
      body.append(h('div', { style: { font: "700 26px/1.4 var(--font-body)", color: '#e3e8f5' } }, text));
      body.append(h('div', { style: { display: 'flex', gap: '16px', justifyContent: 'flex-end', marginTop: '10px' } },
        h('button.btn.grey', { onClick: () => { done = true; resolve(false); api.close(); }, dataset: { sfx: 'back' } }, cancelLabel),
        h('button.btn.' + okClass, { onClick: () => { done = true; resolve(true); api.close(); } }, okLabel),
      ));
    });
    const check = setInterval(() => { if (!document.body.contains(p.el)) { clearInterval(check); if (!done) resolve(false); } }, 200);
  });
}

// ---------------------------------------------------------------- toasts
export function toast(text, { iconName = null, cls = '', ms = 2200 } = {}) {
  const t = h('div.toast.plate' + (cls ? '.' + cls : ''), {}, iconName ? icon(iconName) : null, h('span.outline.thin', {}, text));
  $('#toasts').append(t);
  setTimeout(() => { t.classList.add('out'); setTimeout(() => t.remove(), 320); }, ms);
}

// ---------------------------------------------------------------- particles
/** Burst of icons from a screen point (stage coordinates) flying up and fading. */
export function burst(x, y, iconName = 'coin', count = 14) {
  const layer = $('#fx');
  for (let i = 0; i < count; i++) {
    const p = h('div.particle', {}, icon(iconName));
    p.style.left = x - 20 + 'px'; p.style.top = y - 20 + 'px';
    layer.append(p);
    const ang = -Math.PI / 2 + (Math.random() - 0.5) * 2.2; const sp = 260 + Math.random() * 360;
    const vx = Math.cos(ang) * sp, vy = Math.sin(ang) * sp; const rot = (Math.random() - 0.5) * 720;
    const t0 = performance.now(); const life = 700 + Math.random() * 400;
    const tick = (now) => {
      const t = (now - t0) / 1000; const k = (now - t0) / life;
      if (k >= 1) { p.remove(); return; }
      const dx = vx * t, dy = vy * t + 900 * t * t;
      p.style.transform = `translate(${dx}px, ${dy}px) rotate(${rot * k}deg) scale(${1 - k * 0.4})`;
      p.style.opacity = String(1 - k * k);
      requestAnimationFrame(tick);
    };
    requestAnimationFrame(tick);
  }
}

/** Fly N icons from a point to the currency pill for `kind` (coins/gems). */
export function flyTo(x, y, kind = 'coins', count = 8) {
  const layer = $('#fx');
  const target = $$('.cur-' + kind + ', #cur-' + kind).find((el) => el.offsetParent !== null);
  if (!target) return burst(x, y, kind === 'gems' ? 'gem' : 'coin', count);
  const stage = $('#stage'); const r = target.getBoundingClientRect(); const s = stage.getBoundingClientRect();
  const scale = s.width / stage.offsetWidth;
  const tx = (r.left - s.left) / scale + r.width / 2 - 20, ty = (r.top - s.top) / scale + r.height / 2 - 20;
  for (let i = 0; i < count; i++) {
    const p = h('div.particle', {}, icon(kind === 'gems' ? 'gem' : 'coin'));
    const sx = x - 20 + (Math.random() - 0.5) * 120, sy = y - 20 + (Math.random() - 0.5) * 80;
    p.style.left = sx + 'px'; p.style.top = sy + 'px'; layer.append(p);
    const delay = i * 40; const t0 = performance.now() + delay; const dur = 520;
    const tick = (now) => {
      if (now < t0) { requestAnimationFrame(tick); return; }
      const k = Math.min(1, (now - t0) / dur); const e = k * k * (3 - 2 * k);
      const cx = sx + (tx - sx) * e, cy = sy + (ty - sy) * e - Math.sin(k * Math.PI) * 120;
      p.style.transform = `translate(${cx - sx}px, ${cy - sy}px) scale(${1 - k * 0.3})`;
      if (k < 1) requestAnimationFrame(tick); else { p.remove(); target.parentElement.animate([{ transform: 'scale(1.18)' }, { transform: 'scale(1)' }], { duration: 220 }); }
    };
    requestAnimationFrame(tick);
  }
}

/** Stage-space coordinates of an element's center. */
export function centerOf(el) {
  const stage = $('#stage'); const r = el.getBoundingClientRect(); const s = stage.getBoundingClientRect();
  const scale = s.width / stage.offsetWidth;
  return { x: (r.left - s.left) / scale + r.width / 2 / scale, y: (r.top - s.top) / scale + r.height / 2 / scale };
}

export function stagger(container, step = 40) {
  Array.from(container.children).forEach((c, i) => { c.style.animationDelay = i * step + 'ms'; });
}
