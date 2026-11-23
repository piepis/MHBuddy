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
  await page.waitForTimeout(600);
}

try {
  const cold = await browser.newContext();
  const builds = await cold.newPage({ viewport: { width: 1440, height: 900 }, locale: 'zh-CN' });
  await open(builds, '/g/world/builds');
  const buildText = await textOf(builds);
  check('direct build skill 3', buildText.includes('夹具攻击') && buildText.includes('3'), buildText.slice(0, 500));
  check('direct build jewels 2', buildText.includes('2'), buildText.slice(0, 500));
  await builds.getByText('搜索配装').last().click({ force: true });
  await builds.getByText('已搜完').first().waitFor({ timeout: 15000 });
  const solved = await textOf(builds);
  check('result readable', solved.includes('已搜完') && solved.includes('夹具，不是游戏实数'), solved.slice(0, 800));
  await builds.close();
  await cold.close();

  const events = await browser.newPage({ viewport: { width: 1440, height: 900 }, locale: 'zh-CN' });
  await open(events, '/g/world/events/fixture-event-ancient');
  const eventText = await textOf(events);
  check('event reward', eventText.includes('夹具古代树果实'), eventText.slice(0, 600));
  check('event local time', !eventText.includes('T00:00:00Z') && eventText.includes('订阅提醒') && eventText.includes('下载日历'), eventText.slice(0, 600));
  await events.close();

  const wilds = await browser.newPage({ viewport: { width: 1440, height: 900 }, locale: 'zh-CN' });
  await open(wilds, '/g/wilds');
  await wilds.getByText('荒野试炼').first().waitFor({ timeout: 10000 });
  check('wilds route', true);
  await wilds.close();

  const ice = await browser.newPage({ viewport: { width: 1440, height: 900 }, locale: 'zh-CN' });
  await open(ice, '/g/world/entries');
  await ice.getByRole('button', { name: '冰原', exact: true }).click({ force: true });
  await ice.getByRole('textbox').first().fill('冰原', { force: true });
  await ice.waitForTimeout(500);
  check('iceborne search', (await textOf(ice)).includes('夹具冰原古龙'));
  await ice.close();

  const skill = await browser.newPage({ viewport: { width: 1440, height: 900 }, locale: 'zh-CN' });
  await open(skill, '/g/wilds/entries/skill/fixture-skill-x');
  check('skill jewel', (await textOf(skill)).includes('夹具珠J'));
  await skill.close();

  const map = await browser.newPage({ viewport: { width: 390, height: 844 }, locale: 'zh-CN' });
  await map.goto(base + '/g/world/maps/fixture-ancient-forest?resource=fixture-rare-ore', { waitUntil: 'domcontentloaded', timeout: 60000 });
  await map.getByText('fixture-rare-ore').first().waitFor({ timeout: 30000 });
  await map.waitForTimeout(400);
  const mapText = await textOf(map);
  check('map deep link', mapText.includes('fixture-rare-ore') && mapText.includes('夹具：可能出现') && !mapText.includes('尚未下载'), mapText.slice(0, 700));
  await map.close();

  const account = await browser.newContext();
  const me = await account.newPage({ viewport: { width: 1440, height: 900 }, locale: 'zh-CN' });
  await open(me, '/me');
  check('account chooser', (await me.getByRole('textbox').count()) === 0);
  await me.getByText('登录以同步 hunter-b').click({ force: true });
  await me.getByText('hunter-b').first().waitFor({ timeout: 10000 });
  await me.reload({ waitUntil: 'domcontentloaded' });
  await me.getByText('hunter-b').first().waitFor({ timeout: 15000 });
  check('session survives refresh', !(await textOf(me)).includes('访客') || (await textOf(me)).includes('hunter-b'));
  await me.close();
  await account.close();

  const fav = await browser.newPage({ viewport: { width: 1440, height: 900 }, locale: 'zh-CN' });
  await open(fav, '/g/world/entries/material/fixture-rare-ore');
  await fav.getByRole('button', { name: '收藏' }).first().click({ force: true });
  await open(fav, '/me');
  check('favorite added', (await textOf(fav)).includes('收藏') );
  await open(fav, '/g/world/entries/material/fixture-rare-ore');
  await fav.getByRole('button', { name: '取消收藏' }).or(fav.getByRole('button', { name: '已收藏' })).first().click({ force: true });
  await open(fav, '/me');
  const after = await textOf(fav);
  check('favorite removed', after.includes('\n0') || after.includes('收藏\n0') || !after.includes('收藏\n1'), after.slice(0, 800));
  await fav.close();
} finally {
  await browser.close();
}
