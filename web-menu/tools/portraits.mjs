// Renders assets/portraits/<id>.png for every brawler in data/brawlers.json.
// Usage: npm start (in another terminal, on :3000) then `npm run portraits` [-- http://localhost:3000]
import { chromium } from 'playwright';
import { readFileSync } from 'node:fs';
const base = process.argv[2] || 'http://localhost:3000';
const data = JSON.parse(readFileSync(new URL('../data/brawlers.json', import.meta.url)));
const browser = await chromium.launch({ args: ['--use-gl=angle', '--use-angle=swiftshader', '--enable-unsafe-swiftshader', '--ignore-gpu-blocklist'] });
for (const b of data.brawlers) {
  const page = await browser.newPage({ viewport: { width: 512, height: 512 } });
  await page.goto(`${base}/tools/portrait.html?m=${encodeURIComponent('../' + b.model)}&s=${b.stance || 'relaxed'}`);
  await page.waitForFunction('window.__done === true', null, { timeout: 60000 });
  await page.screenshot({ path: new URL('../' + b.portrait, import.meta.url).pathname, omitBackground: true });
  console.log('rendered', b.portrait);
  await page.close();
}
await browser.close();
