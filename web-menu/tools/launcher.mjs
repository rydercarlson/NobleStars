import { createReadStream, existsSync, statSync } from 'node:fs';
import { createServer } from 'node:http';
import { dirname, extname, resolve, sep } from 'node:path';
import { spawn } from 'node:child_process';
import { fileURLToPath } from 'node:url';

const menuRoot = resolve(dirname(fileURLToPath(import.meta.url)), '..');
const godotRoot = resolve(menuRoot, '..', 'godot');
const port = Number.parseInt(process.env.NOBLES_MENU_PORT || '3000', 10);
const host = process.env.NOBLES_MENU_HOST || '127.0.0.1';

const brawlers = new Map([
  ['leon', 'Leon'],
  ['sanjit', 'Sanjit'],
  ['tony', 'Tony'],
  ['kovacs', 'Kovacs'],
  ['henry', 'Henry'],
]);

const contentTypes = {
  '.css': 'text/css; charset=utf-8',
  '.glb': 'model/gltf-binary',
  '.html': 'text/html; charset=utf-8',
  '.jpg': 'image/jpeg',
  '.js': 'text/javascript; charset=utf-8',
  '.json': 'application/json; charset=utf-8',
  '.mjs': 'text/javascript; charset=utf-8',
  '.png': 'image/png',
  '.svg': 'image/svg+xml',
  '.woff2': 'font/woff2',
};

let runningGame = null;

function json(res, status, body) {
  res.writeHead(status, { 'content-type': 'application/json; charset=utf-8' });
  res.end(JSON.stringify(body));
}

async function readJson(req) {
  let body = '';
  for await (const chunk of req) {
    body += chunk;
    if (body.length > 16_384) throw new Error('Request is too large');
  }
  return JSON.parse(body || '{}');
}

function godotCommand() {
  if (process.env.NOBLES_GODOT_BIN) return process.env.NOBLES_GODOT_BIN;
  const mac = '/Applications/Godot.app/Contents/MacOS/Godot';
  if (existsSync(mac)) return mac;
  return process.platform === 'win32' ? 'godot.exe' : 'godot4';
}

function launchGodot(kit, mode) {
  return new Promise((resolveLaunch, rejectLaunch) => {
    const child = spawn(godotCommand(), ['--path', godotRoot], {
      cwd: godotRoot,
      detached: process.platform !== 'win32',
      env: { ...process.env, NS3_KIT: kit, NS3_MODE: mode },
      stdio: 'ignore',
    });
    child.once('error', rejectLaunch);
    child.once('spawn', () => {
      runningGame = child;
      child.unref();
      child.once('exit', () => { if (runningGame === child) runningGame = null; });
      resolveLaunch(child.pid);
    });
  });
}

async function play(req, res) {
  try {
    const body = await readJson(req);
    const kit = brawlers.get(String(body.brawler || '').toLowerCase());
    if (!kit) return json(res, 400, { ok: false, error: 'Unknown brawler selection.' });
    if (body.mode !== 'showdown_solo') {
      return json(res, 422, { ok: false, error: 'Godot currently supports Solo Showdown only.' });
    }
    if (runningGame && runningGame.exitCode === null) {
      return json(res, 409, { ok: false, error: 'A Godot match is already running.' });
    }
    const pid = await launchGodot(kit, 'showdown');
    return json(res, 200, { ok: true, pid, kit, mode: 'showdown' });
  } catch (error) {
    return json(res, 500, { ok: false, error: `Could not launch Godot: ${error.message}` });
  }
}

function serveFile(req, res) {
  const pathname = decodeURIComponent(new URL(req.url, 'http://localhost').pathname);
  let file = resolve(menuRoot, '.' + pathname);
  if (file !== menuRoot && !file.startsWith(menuRoot + sep)) {
    res.writeHead(403); res.end('Forbidden'); return;
  }
  if (existsSync(file) && statSync(file).isDirectory()) file = resolve(file, 'index.html');
  if (!existsSync(file) || !statSync(file).isFile()) {
    res.writeHead(404); res.end('Not found'); return;
  }
  res.writeHead(200, { 'content-type': contentTypes[extname(file).toLowerCase()] || 'application/octet-stream' });
  createReadStream(file).pipe(res);
}

const server = createServer((req, res) => {
  if (req.method === 'POST' && req.url === '/api/play') return void play(req, res);
  if (req.method === 'GET' || req.method === 'HEAD') return serveFile(req, res);
  res.writeHead(405, { allow: 'GET, HEAD, POST' }); res.end('Method not allowed');
});

server.listen(port, host, () => {
  console.log(`Nobles Brawl menu: http://${host}:${port}`);
  console.log(`PLAY launches Godot from ${godotRoot}`);
});
