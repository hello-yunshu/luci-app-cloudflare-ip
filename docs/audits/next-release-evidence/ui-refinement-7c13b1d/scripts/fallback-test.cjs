'use strict';
const fs = require('fs');
const path = require('path');
const { chromium } = require('playwright');
const cssPath = '/Users/yunshu/Documents/GitHub/luci-app-cloudflare-ip/package/luci-app-cloudflare-ip/htdocs/luci-static/resources/cloudflare-ip/cloudflare-ip.css';
const base = 'http://127.0.0.1:18080';
const out = '/tmp/cfip-audit/fallback';
fs.mkdirSync(out, { recursive: true });

function stripContainerBlock(src) {
  const marker = '@supports (container-type: inline-size)';
  const start = src.indexOf(marker);
  if (start < 0) return src;
  let i = src.indexOf('{', start), depth = 0;
  for (; i < src.length; i++) {
    if (src[i] === '{') depth++;
    else if (src[i] === '}') { depth--; if (depth === 0) { i++; break; } }
  }
  return src.slice(0, start) + src.slice(i);
}

const full = fs.readFileSync(cssPath, 'utf8');
const stripped = stripContainerBlock(full);

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

async function measure(browser, variant, css, width, synthetic) {
  const ctx = await browser.newContext({ viewport: { width, height: 900 } });
  const page = await ctx.newPage();
  if (css) await page.route('**/cloudflare-ip.css*', route => route.fulfill({ status: 200, contentType: 'text/css', body: css }));
  await login(page);
  await page.goto(base + '/cgi-bin/luci/admin/services/cf_ip/settings', { waitUntil: 'domcontentloaded' });
  await page.locator('.cfi-form-map').waitFor({ timeout: 30000 });
  await page.waitForTimeout(500);
  if (synthetic) {
    await page.evaluate(() => {
      const m = document.querySelector('.cfi-form-map');
      m.style.width = '500px';
      m.style.maxWidth = '500px';
    });
    await page.waitForTimeout(300);
  }
  const m = await page.evaluate(() => {
    const map = document.querySelector('.cfi-form-map');
    const val = document.querySelector('.cbi-value');
    const grid = val ? getComputedStyle(val).gridTemplateColumns : '';
    return {
      viewport: innerWidth,
      mapWidth: map.getBoundingClientRect().width,
      grid,
      cols: grid.split(' ').filter(Boolean).length,
      media600: matchMedia('(max-width:600px)').matches,
      containerSupported: CSS.supports('container-type: inline-size'),
      overflow: document.documentElement.scrollWidth > innerWidth
    };
  });
  await page.screenshot({ path: path.join(out, `${variant}-${width}${synthetic ? '-synthetic500' : ''}.png`) });
  await ctx.close();
  return m;
}

(async () => {
  const browser = await chromium.launch({ headless: true });
  const rows = [];
  for (const width of [375, 640, 768]) {
    rows.push({ variant: 'full', width, synthetic: false, ...(await measure(browser, 'full', null, width, false)) });
    rows.push({ variant: 'stripped', width, synthetic: false, ...(await measure(browser, 'stripped', stripped, width, false)) });
  }
  rows.push({ variant: 'full', width: 768, synthetic: true, ...(await measure(browser, 'full', null, 768, true)) });
  rows.push({ variant: 'stripped', width: 768, synthetic: true, ...(await measure(browser, 'stripped', stripped, 768, true)) });
  await browser.close();
  fs.writeFileSync(path.join(out, 'fallback.json'), JSON.stringify({ cssFullBytes: full.length, cssStrippedBytes: stripped.length, rows }, null, 2) + '\n');
  console.log(rows.map(r => `${r.variant} ${r.width}${r.synthetic ? ' synthetic500' : ''}: map=${r.mapWidth} cols=${r.cols} media600=${r.media600} overflow=${r.overflow}`).join('\n'));
})().catch(e => { console.error(e); process.exit(1); });
