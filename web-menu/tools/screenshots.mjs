// Captures docs/*.jpg of every screen. Usage: npm start, then `npm run screenshots` [-- http://localhost:3000]
import { chromium } from 'playwright';
const base = process.argv[2] || 'http://localhost:3000';
const browser = await chromium.launch({ args: ['--use-gl=angle', '--use-angle=swiftshader', '--enable-unsafe-swiftshader'] });
const page = await browser.newPage({ viewport: { width: 1920, height: 1080 } });
await page.goto(base + '/index.html');
await page.waitForFunction(() => !document.querySelector('#loader'), null, { timeout: 60000 });
await page.waitForTimeout(1500);
const shots = [['home', null], ['brawlers', '[data-open=brawlers]'], ['shop', '[data-open=shop]'], ['pass', '[data-open=pass]'], ['news', '[data-open=news]'], ['friends', '[data-open=friends]'], ['club', '[data-open=club]'], ['inbox', '[data-open=inbox]'], ['modes', '[data-open=modes]'], ['settings', '#btn-menu']];
for (const [name, sel] of shots) {
  if (sel) { await page.click(sel); await page.waitForTimeout(1200); }
  await page.screenshot({ path: `docs/${name}.jpg`, type: 'jpeg', quality: 82 });
  if (sel) { await page.keyboard.press('Escape'); await page.waitForTimeout(600); }
}
await browser.close();
