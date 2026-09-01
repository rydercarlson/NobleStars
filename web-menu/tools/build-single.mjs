// Builds dist/nobles-brawl.html — the whole menu in ONE file (JS bundled, every asset
// embedded as a data: URL). Handy for sharing a review build or publishing as an artifact.
// Usage: node tools/build-single.mjs [--models <dir>] [--out <file>] [--fragment]
//   --models   use GLBs from another folder (e.g. smaller textures for a size cap)
//   --fragment emit body-only HTML (no doctype/html/head/body) for hosts that add their own skeleton
import { readFileSync, writeFileSync, mkdirSync, readdirSync, statSync, existsSync } from 'node:fs';
import { join, extname, relative, resolve, dirname } from 'node:path';
import { fileURLToPath } from 'node:url';
import { build } from 'esbuild';

const root = resolve(dirname(fileURLToPath(import.meta.url)), '..');
const args = process.argv.slice(2);
const opt = (k, d) => { const i = args.indexOf(k); return i >= 0 ? args[i + 1] : d; };
const modelsDir = resolve(opt('--models', join(root, 'assets/models')));
const out = resolve(opt('--out', join(root, 'dist/nobles-brawl.html')));
const fragment = args.includes('--fragment');
const slim = args.includes('--slim'); // skip unused spares (decor, panels, 3D portraits) to fit hosted size caps

const mime = { '.png': 'image/png', '.jpg': 'image/jpeg', '.jpeg': 'image/jpeg', '.svg': 'image/svg+xml', '.webp': 'image/webp', '.glb': 'model/gltf-binary', '.woff2': 'font/woff2', '.json': 'application/json', '.mp3': 'audio/mpeg', '.ogg': 'audio/ogg' };
const dataUrl = (file) => `data:${mime[extname(file).toLowerCase()] || 'application/octet-stream'};base64,${readFileSync(file).toString('base64')}`;

// 1. collect assets ---------------------------------------------------------
const assets = {};
const walk = (dir, mapTo) => { for (const f of readdirSync(dir)) { const p = join(dir, f); if (statSync(p).isDirectory()) walk(p, mapTo); else if (mime[extname(f).toLowerCase()]) assets[mapTo(p)] = dataUrl(p); } };
const rel = (p) => relative(root, p).replace(/\\/g, '/');
walk(join(root, 'assets/ui'), rel);
walk(join(root, 'assets/cards'), rel);
if (!slim) walk(join(root, 'assets/portraits'), rel);
if (slim) for (const k of Object.keys(assets)) if (/^assets\/ui\/(decor\/(?!logo|pass_hero|skin_)|panels\/|generated\/)/.test(k)) delete assets[k];
if (slim) { assets['assets/ui/generated/rank_badge.svg'] = dataUrl(join(root, 'assets/ui/generated/rank_badge.svg')); for (const f of ['close','back','check','online','hanger','quests','bling','hypercharge','token','star_drop','settings_gear','gear','lock','gadget','star_power','power_point','star_points','trophy','coin','gem']) { const p = join(root, 'assets/ui/generated', f + '.svg'); if (existsSync(p)) assets[rel(p)] = dataUrl(p); } }
walk(join(root, 'assets/fonts'), (p) => relative(root, p).replace(/\\/g, '/'));
walk(join(root, 'data'), (p) => relative(root, p).replace(/\\/g, '/'));
walk(modelsDir, (p) => 'assets/models/' + relative(modelsDir, p).replace(/\\/g, '/'));
assets['assets/manifest.json'] = dataUrl(join(root, 'assets/manifest.json'));

// 2. bundle JS ---------------------------------------------------------------
const bundle = await build({
  entryPoints: [join(root, 'src/main.js')],
  bundle: true, format: 'iife', minify: true, write: false, target: 'es2020', legalComments: 'none',
  alias: { three: join(root, 'vendor/three/three.module.min.js'), 'three/addons': join(root, 'vendor/three/addons') },
  define: { 'import.meta.url': '""' },
  logLevel: 'error',
});
const js = bundle.outputFiles[0].text;

// 3. CSS with inlined url() -------------------------------------------------
let css = readFileSync(join(root, 'styles.css'), 'utf8');
css = css.replace(/url\(['"]?([^'")]+)['"]?\)/g, (m, p) => (assets[p] ? `url("${assets[p]}")` : m));

// 4. HTML ------------------------------------------------------------------------
let html = readFileSync(join(root, 'index.html'), 'utf8');
const bodyStart = html.indexOf('<body>') + 6, bodyEnd = html.lastIndexOf('</body>');
let body = html.slice(bodyStart, bodyEnd).replace(/<script type="module" src="src\/main.js"><\/script>/, '');
const title = fragment ? '<title>Nobles Brawl</title>\n' : '';
const head = `${title}<style>${css}</style>\n<script>window.__NB_ASSETS=${JSON.stringify(assets)};</script>\n`;
const scripts = `\n<script>${js}</script>\n`;
let result;
if (fragment) result = head + body + scripts;
else result = `<!doctype html>\n<html lang="en">\n<head>\n<meta charset="utf-8">\n<meta name="viewport" content="width=device-width, initial-scale=1, maximum-scale=1, user-scalable=no, viewport-fit=cover">\n<title>Nobles Brawl</title>\n${head}</head>\n<body>${body}${scripts}</body>\n</html>\n`;
mkdirSync(dirname(out), { recursive: true });
writeFileSync(out, result);
console.log(`wrote ${relative(process.cwd(), out)} (${(result.length / 1e6).toFixed(1)} MB, ${Object.keys(assets).length} embedded assets)`);
