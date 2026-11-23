import { chromium } from 'playwright-core';

const base = process.env.BASE_URL || 'http://127.0.0.1:8080';
const chrome = process.env.CHROME || '/usr/bin/google-chrome';

const browser = await chromium.launch({
  executablePath: chrome,
  headless: true,
  args: ['--no-sandbox', '--disable-dev-shm-usage'],
});

function check(name, ok, detail = '') {
  if (!ok) throw new Error(`${name} ${detail}`);
  console.log(`PASS ${name}`);
}

async function textOf(page) {
  return page.evaluate(() => document.body.innerText || '');
}

async function open(page, url) {
  await page.goto(base + url, { waitUntil: 'domcontentloaded', timeout: 60000 });
  await page.getByText('首页').first().waitFor({ timeout: 30000 });
  await page.waitForTimeout(400);
}

try {
  const page = await browser.newPage({ viewport: { width: 1440, height: 900 }, locale: 'zh-CN' });
  await open(page, '/');
  check('home quest', (await textOf(page)).includes('查看任务'));

  await open(page, '/g/world/entries');
  await page.getByRole('textbox').first().fill('稀有矿', { force: true });
  await page.waitForTimeout(400);
  check('wiki search', (await textOf(page)).includes('夹具稀有矿'));

  await page.getByText('配装').first().click({ force: true });
  await page.getByText('模型未开通，使用条件配装。').first().waitFor({ timeout: 10000 });
  check('condition fallback', true);
  check('condition heading', (await textOf(page)).includes('条件'));
  await page.getByText('搜索配装').first().click({ force: true });
  await page.getByText('保存当前配装').first().waitFor({ timeout: 15000 });
  check('world solve result', true);

  await open(page, '/builds/pub-fixture-wilds-1');
  await page.getByText('夹具公开配装').first().waitFor({ timeout: 15000 });
  check('public build', true);
  await open(page, '/builds/missing-private');
  await page.getByText('没有这条公开记录').first().waitFor({ timeout: 15000 });
  check('private hidden', true);

  await open(page, '/g/world/events');
  const fields = page.locator('[data-semantics-role="text-field"]');
  check('event fields', (await fields.count()) >= 2, String(await fields.count()));
  await fields.nth(0).fill('古代树调查', { force: true });
  await fields.nth(1).fill('', { force: true });
  const icon = page.locator('[role=button]');
  const n = await icon.count();
  let clicked = false;
  for (let i = 0; i < n; i++) {
    const box = await icon.nth(i).boundingBox();
    const label = (await icon.nth(i).innerText()).trim();
    if (box && label === '' && box.y < 140 && box.x > 1000) {
      await icon.nth(i).click();
      clicked = true;
      break;
    }
  }
  check('event search clicked', clicked);
  await page.waitForTimeout(700);
  check('event name hit', (await textOf(page)).includes('夹具赏金：古代树调查'));

  await open(page, '/me');
  check('guest', (await textOf(page)).includes('访客'));
  check('no account field', (await page.getByRole('textbox').count()) === 0);
  await page.getByText('登录以同步').first().click({ force: true });
  await page.getByText('hunter-a').first().waitFor({ timeout: 10000 });
  const ent = await page.evaluate(async () => {
    const res = await fetch('/v1/me/entitlement', { credentials: 'include' });
    return { status: res.status, cache: res.headers.get('cache-control') };
  });
  check('entitlement', ent.status === 200 && (ent.cache || '').includes('no-store'), JSON.stringify(ent));
  await page.getByText('退出').first().click({ force: true });
  await page.getByText('访客').first().waitFor({ timeout: 10000 });
  const after = await page.evaluate(async () => (await fetch('/v1/me/entitlement', { credentials: 'include' })).status);
  check('logout', after === 401, String(after));

  await page.getByText('语言').first().click({ force: true });
  await page.waitForTimeout(300);
  check('locale hant', (await textOf(page)).includes('首頁') || (await textOf(page)).includes('語言'));
  await page.getByRole('button', { name: '切换外观' }).click({ force: true });
  check('dark label', (await textOf(page)).includes('深色'));

  const anon = await page.evaluate(async () => {
    const sync = await fetch('/v1/sync/push', {
      method: 'POST',
      headers: { 'content-type': 'application/json' },
      body: JSON.stringify({ ops: [{ opId: 'qa', recordType: 'build', recordId: 'b', gameId: 'world', action: 'upsert', payload: { title: 'a' } }] }),
    });
    const cal = await fetch('/v1/events/fixture-event-ancient/calendar.ics');
    const ics = await cal.text();
    return { sync: sync.status, cal: cal.status, uid: ics.includes('UID:'), seq: ics.includes('SEQUENCE:') };
  });
  check('anon sync', anon.sync === 401, JSON.stringify(anon));
  check('calendar', anon.cal === 200 && anon.uid && anon.seq, JSON.stringify(anon));
  await page.close();
} finally {
  await browser.close();
}
