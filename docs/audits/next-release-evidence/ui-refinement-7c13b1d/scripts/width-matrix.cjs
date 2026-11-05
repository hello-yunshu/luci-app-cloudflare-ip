'use strict';
const fs = require('fs');
const path = require('path');
const { execFileSync } = require('child_process');
const { chromium } = require('playwright');

const container = process.argv[2];
const base = process.argv[3];
const label = process.argv[4];
const out = path.join('/tmp/cfip-evidence/width-matrix', label);
fs.mkdirSync(out, { recursive: true });
const sh = c => execFileSync('docker', ['exec', container, 'sh', '-c', c], { encoding: 'utf8' });

const themes = {
  bootstrap: { media: '/luci-static/bootstrap', storage: null },
  'aurora-light': { media: '/luci-static/aurora', storage: 'light' },
  'aurora-dark': { media: '/luci-static/aurora', storage: 'dark' }
};
const viewports = [[320, 900], [375, 900], [640, 900], [768, 900], [900, 900], [1280, 900]];
const pages = ['settings', 'sources', 'intelligence'];

async function setTheme(page, name) {
  const t = themes[name];
  sh(`uci set luci.main.mediaurlbase='${t.media}'; uci commit luci; rm -rf /tmp/luci-indexcache* /tmp/luci-modulecache; /etc/init.d/uhttpd restart >/dev/null 2>&1`);
  await page.waitForTimeout(700);
  if (t.storage !== null) {
    await page.goto(base + '/cgi-bin/luci/', { waitUntil: 'domcontentloaded' });
    await page.evaluate(v => localStorage.setItem('aurora.theme', v), t.storage);
  }
}

(async () => {
  const browser = await chromium.launch({ headless: true });
  const ctx = await browser.newContext({ viewport: { width: 1280, height: 900 } });
  const page = await ctx.newPage();
  const rows = [];
  try {
    await page.goto(base + '/cgi-bin/luci/', { waitUntil: 'domcontentloaded' });
    const user = page.locator('input[name="luci_username"]');
    if (await user.count()) {
      await user.fill('root');
      await page.locator('input[name="luci_password"]').fill('cfip-gate');
      await page.locator('button:has-text("Log in"), button:has-text("Login"), input[type="submit"]').first().click();
      await page.waitForTimeout(2500);
    }
    for (const theme of Object.keys(themes)) {
      await setTheme(page, theme);
      for (const [w, h] of viewports) {
        await page.setViewportSize({ width: w, height: h });
        for (const p of pages) {
          await page.goto(base + '/cgi-bin/luci/admin/services/cf_ip/' + p, { waitUntil: 'domcontentloaded' });
          await page.locator('.cfi-form-map').waitFor({ timeout: 30000 });
          await page.waitForTimeout(250);
          const m = await page.evaluate(() => {
            const map = document.querySelector('.cfi-form-map');
            const main = document.querySelector('#maincontent');
            const val = document.querySelector('.cbi-value');
            const grid = val ? getComputedStyle(val).gridTemplateColumns : '';
            const cols = grid ? grid.split(' ').filter(Boolean).length : 0;
            return {
              innerWidth,
              mainWidth: main ? Math.round(main.getBoundingClientRect().width * 100) / 100 : null,
              mapWidth: map ? Math.round(map.getBoundingClientRect().width * 100) / 100 : null,
              gridTemplateColumns: grid,
              gridColumns: cols,
              media600: matchMedia('(max-width: 600px)').matches,
              media900: matchMedia('(max-width: 900px)').matches,
              container600: CSS.supports('container-type: inline-size') && map ? map.getBoundingClientRect().width <= 600 : null,
              container900: CSS.supports('container-type: inline-size') && map ? map.getBoundingClientRect().width <= 900 : null,
              dark: document.documentElement.getAttribute('data-darkmode'),
              overflow: document.documentElement.scrollWidth > innerWidth || document.body.scrollWidth > innerWidth,
              scrollWidth: document.documentElement.scrollWidth
            };
          });
          rows.push({ theme, viewport: w + 'x' + h, page: p, ...m });
          if (p === 'settings' && (w === 768 || w === 375 || w === 640)) {
            const file = path.join(out, `${theme}-${w}x${h}-settings.png`);
            await page.screenshot({ path: file });
          }
        }
      }
    }
  } finally {
    await browser.close();
  }
  fs.writeFileSync(path.join(out, 'matrix.json'), JSON.stringify({ container, base, label, rows }, null, 2) + '\n');
  console.log(rows.map(r => `${r.theme} ${r.viewport} ${r.page}: vw=${r.innerWidth} main=${r.mainWidth} map=${r.mapWidth} cols=${r.gridColumns} m600=${r.media600} c600=${r.container600} m900=${r.media900} c900=${r.container900} dark=${r.dark} overflow=${r.overflow}`).join('\n'));
})().catch(e => { console.error(e); process.exit(1); });
