'use strict';
const fs = require('fs');
const path = require('path');
const { execFileSync } = require('child_process');
const { chromium } = require('playwright');

const container = process.argv[2] || 'cfip-ui-gate';
const base = process.argv[3] || 'http://127.0.0.1:18080';
const sha = process.argv[4] || execFileSync('git', ['rev-parse', '--short', 'HEAD'], { encoding: 'utf8' }).trim();
const out = '/tmp/cfip-evidence/visual';
fs.mkdirSync(out, { recursive: true });
const sh = c => execFileSync('docker', ['exec', container, 'sh', '-c', c], { encoding: 'utf8' });

const themes = {
  bootstrap: { media: '/luci-static/bootstrap', storage: null },
  'aurora-light': { media: '/luci-static/aurora', storage: 'light' },
  'aurora-dark': { media: '/luci-static/aurora', storage: 'dark' }
};
const pages = ['overview', 'settings', 'sources', 'intelligence', 'openclash', 'passwall', 'advanced', 'logs'];
const viewports = [[375, 900], [768, 900], [1280, 900]];
const rows = [];

async function login(page) {
  await page.goto(base + '/cgi-bin/luci/', { waitUntil: 'domcontentloaded' });
  const user = page.locator('input[name="luci_username"]');
  if (await user.count()) {
    await user.fill('root');
    await page.locator('input[name="luci_password"]').fill('cfip-gate');
    await page.locator('button:has-text("Log in"), button:has-text("Login"), input[type="submit"]').first().click();
    await page.waitForTimeout(2500);
  }
}

async function setTheme(page, name) {
  const t = themes[name];
  sh(`uci set luci.main.mediaurlbase='${t.media}'; uci commit luci; rm -rf /tmp/luci-indexcache* /tmp/luci-modulecache; /etc/init.d/uhttpd restart >/dev/null 2>&1`);
  await page.waitForTimeout(700);
  if (t.storage !== null) {
    await page.goto(base + '/cgi-bin/luci/', { waitUntil: 'domcontentloaded' });
    await page.evaluate(v => localStorage.setItem('aurora.theme', v), t.storage);
  }
}

async function capture(page, theme, vp, pg, interaction) {
  const dir = path.join(out, theme, vp);
  fs.mkdirSync(dir, { recursive: true });
  const file = path.join(dir, pg + '.png');
  await page.goto(base + '/cgi-bin/luci/admin/services/cf_ip/' + pg, { waitUntil: 'domcontentloaded' });
  await page.waitForTimeout(1200);
  await page.screenshot({ path: file });
  const m = await page.evaluate(() => ({
    title: document.title,
    path: location.pathname,
    w: innerWidth,
    h: innerHeight,
    scrollWidth: document.documentElement.scrollWidth,
    overflow: document.documentElement.scrollWidth > innerWidth || document.body.scrollWidth > innerWidth,
    textLen: (document.querySelector('#maincontent') || document.body).innerText.length,
    dark: document.documentElement.getAttribute('data-darkmode'),
    login: !!document.querySelector('input[name="luci_password"]')
  }));
  rows.push({ sha, theme, viewport: vp, page: pg, state: 'normal', interaction: interaction || 'page', ...m, file: path.relative(out, file) });
}

(async () => {
  const browser = await chromium.launch({ headless: true });
  const ctx = await browser.newContext({ viewport: { width: 1280, height: 900 } });
  const page = await ctx.newPage();
  try {
    await login(page);
    sh('printf "#!/bin/sh\\nexit 1\\n" > /etc/init.d/openclash; printf "#!/bin/sh\\nexit 1\\n" > /etc/init.d/passwall; chmod +x /etc/init.d/openclash /etc/init.d/passwall; rm -rf /tmp/luci-indexcache* /tmp/luci-modulecache');
    for (const theme of Object.keys(themes)) {
      await setTheme(page, theme);
      for (const [w, h] of viewports) {
        await page.setViewportSize({ width: w, height: h });
        for (const pg of pages) await capture(page, theme, `${w}x${h}`, pg, 'page');
      }
      await page.setViewportSize({ width: 320, height: 900 });
      await capture(page, theme, '320x900', 'overview', 'narrow-boundary');
      await page.setViewportSize({ width: 640, height: 900 });
      await capture(page, theme, '1280x900-200pct-effective-640', 'sources', 'zoom-200');
    }
  } finally {
    try { sh('rm -f /etc/init.d/openclash /etc/init.d/passwall; rm -rf /tmp/luci-indexcache* /tmp/luci-modulecache'); } catch (e) {}
    await browser.close();
  }
  fs.writeFileSync(path.join(out, 'captures.json'), JSON.stringify({ sha, container, base, rows }, null, 2) + '\n');
  console.log('captured', rows.length, 'screenshots', rows.filter(r => r.overflow).length, 'overflow');
})().catch(e => { console.error(e); process.exit(1); });
