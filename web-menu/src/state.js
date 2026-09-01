// Player state, persisted to localStorage. Everything the menu can change lives here.

const KEY = 'nobles-brawl.save.v1';

const defaults = () => ({
  name: 'GUEST',
  coins: 1250,
  gems: 90,
  powerPoints: 340,
  bling: 1200,
  tokens: 0,
  trophies: 905,
  starPoints: 120,
  level: 6,
  selectedBrawler: 'leon',
  selectedMode: 'showdown_solo',
  unlocked: { leon: true, sanjit: true, tony: true },
  brawlerTrophies: {},
  brawlerPower: {},
  claimed: {},          // shop item id / pass reward id -> true
  readMail: {},         // inbox id -> true
  passTier: 9,
  passTokens: 340,
  passPremium: false,
  clubChat: [],
  settings: { music: true, sfx: true, hints: true },
  firstRun: true,
  matches: 0,
  team1: null,
  team2: null,
  skins: { leon: 'default', sanjit: 'default', tony: 'default', kovacs: 'default', henry: 'default' },
  ownedSkins: {},
});

// brawler ids were renamed once; keep old saves working
const RENAMED = { dart: 'leon', sensei: 'sanjit', grit: 'kovacs', paddles: 'henry', ace: 'tony' };
function migrate(s) {
  const mapKeys = (o) => { if (!o) return o; const out = {}; for (const k in o) out[RENAMED[k] || k] = o[k]; return out; };
  if (s.selectedBrawler) s.selectedBrawler = RENAMED[s.selectedBrawler] || s.selectedBrawler;
  s.unlocked = mapKeys(s.unlocked); s.brawlerTrophies = mapKeys(s.brawlerTrophies); s.brawlerPower = mapKeys(s.brawlerPower); s.skins = mapKeys(s.skins);
  return s;
}

export const state = load();

function load() {
  try {
    const raw = localStorage.getItem(KEY);
    if (raw) { const s = migrate(JSON.parse(raw)); return deepMerge(defaults(), s); }
  } catch (e) { /* ignore */ }
  return defaults();
}

function deepMerge(base, over) {
  for (const k in over) {
    if (over[k] && typeof over[k] === 'object' && !Array.isArray(over[k]) && base[k] && typeof base[k] === 'object') base[k] = deepMerge(base[k], over[k]);
    else base[k] = over[k];
  }
  return base;
}

let saveTimer = null;
export function save() {
  clearTimeout(saveTimer);
  saveTimer = setTimeout(() => { try { localStorage.setItem(KEY, JSON.stringify(state)); } catch (e) { /* private mode */ } }, 80);
}

export function resetSave() {
  try { localStorage.removeItem(KEY); } catch (e) {}
  location.reload();
}

// ---- simple event bus so screens can react to state changes ----
const listeners = {};
export function on(evt, fn) { (listeners[evt] ||= []).push(fn); return () => { listeners[evt] = listeners[evt].filter((f) => f !== fn); }; }
export function emit(evt, data) { (listeners[evt] || []).forEach((f) => f(data)); }

export const CURRENCY_KEY = { coins: 'coins', gems: 'gems', power_points: 'powerPoints', bling: 'bling', trophies: 'trophies', star_points: 'starPoints', tokens: 'passTokens' };
export function addCurrency(kind, amount) {
  if (kind === 'coins') state.coins += amount;
  else if (kind === 'gems') state.gems += amount;
  else if (kind === 'power_points') state.powerPoints += amount;
  else if (kind === 'bling') state.bling += amount;
  else if (kind === 'tokens') state.passTokens += amount;
  else if (kind === 'trophies') state.trophies += amount;
  else if (kind === 'star_points') state.starPoints += amount;
  save(); emit('currency', { kind, amount });
}

export function canAfford(currency, price) {
  if (currency === 'free' || !price) return true;
  return (state[CURRENCY_KEY[currency] || currency] ?? 0) >= price;
}

export function spend(currency, price) {
  if (currency === 'free' || !price) return true;
  if (!canAfford(currency, price)) return false;
  state[CURRENCY_KEY[currency] || currency] -= price; save(); emit('currency', { kind: currency, amount: -price });
  return true;
}
