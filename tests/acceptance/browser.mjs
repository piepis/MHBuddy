import { chromium } from 'playwright-core';
import { mkdir, writeFile } from 'node:fs/promises';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const base = process.env.BASE_URL || 'http://127.0.0.1:8080';
const out = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '../../docs/execution/browser-qa');
await mkdir(out, { recursive: true });

const browser = await chromium.launch({
  executablePath: process.env.CHROME || '/usr/bin/google-chrome',
  headless: true,
  args: ['--no-sandbox', '--disable-dev-shm-usage'],
});

const notes = [];
function check(name, ok, detail = '') {
  notes.push(`${ok ? 'PASS' : 'FAIL'} ${name} ${detail}`.trim());
  if (!ok) throw new Error(name + ' ' + detail);
}

async function fresh(width, height) {
  const page = await browser.newPage({ viewport: { width, height } });
  await page.goto(base + '/', { waitUntil: 'domcontentloaded' });
  await page.evaluate(async () => {
    const regs = await navigator.serviceWorker.getRegistrations();
    await Promise.all(regs.map((r) => r.unregister()));
    const keys = await caches.keys();
    await Promise.all(keys.map((k) => caches.delete(k)));
  });
  await page.reload({ waitUntil: 'networkidle' });
  return page;
}

async function run(width, height, label) {
  const page = await fresh(width, height);
  await page.getByText('首页').first().waitFor({ timeout: 20000 });
  check(`${label} home`, await page.getByText('查看任务').first().isVisible() || await page.getByText('当前没有限时任务').isVisible());
  await page.screenshot({ path: path.join(out, `${label}-home.png`), fullPage: true });
  await page.getByText('百科').first().click();
  await page.waitForURL('**/entries**', { waitUntil: 'commit' });
  await page.getByRole('textbox').first().fill('稀有矿');
  await page.getByText('夹具稀有矿').click();
  await page.getByText('地图查看').click();
  await page.waitForURL('**/maps/**', { waitUntil: 'commit' });
  check(`${label} map`, await page.getByText('夹具：可能出现').isVisible());
  await page.screenshot({ path: path.join(out, `${label}-map.png`), fullPage: true });
  await page.screenshot({ path: path.join(out, `${label}-wiki.png`), fullPage: false });
  await page.goto(base + '/builds/pub-fixture-wilds-1', { waitUntil: 'networkidle' });
  check(`${label} public build`, await page.getByText('夹具公开配装').first().isVisible());
  await page.goto(base + '/builds/missing-private', { waitUntil: 'networkidle' });
  check(`${label} private hidden`, await page.getByText('没有这条公开记录').isVisible());
  const anon = await page.evaluate(async () => {
    const res = await fetch('/v1/sync/push', { method: 'POST', headers: { 'content-type': 'application/json' }, body: JSON.stringify({ ops: [{ opId: 'x', recordType: 'build', recordId: 'b', gameId: 'world', action: 'upsert', payload: {} }] }) });
    return res.status;
  });
  check(`${label} anon sync`, anon === 401, String(anon));
  await page.close();
}

try {
  await run(1440, 900, 'desktop');
  await run(390, 844, 'mobile');
  const theme = await (async () => {
    const page = await fresh(390, 844);
    await page.goto(base + '/me', { waitUntil: 'networkidle' });
    await page.getByRole('button', { name: '切换外观' }).click();
    await page.screenshot({ path: path.join(out, 'mobile-dark.png'), fullPage: true });
    await page.getByRole('button', { name: '切换外观' }).click();
    await page.screenshot({ path: path.join(out, 'mobile-light.png'), fullPage: true });
    await page.close();
    return true;
  })();
  check('theme toggle', theme);
  await writeFile(path.join(out, 'result.txt'), notes.join('\n') + '\n');
  console.log(notes.join('\n'));
} finally {
  await browser.close();
}
