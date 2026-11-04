'use strict';
const fs = require('fs');
const path = require('path');
const { execFileSync } = require('child_process');
const { chromium } = require('playwright');
const base = 'http://127.0.0.1:18080';
const container = 'cfip-ui-gate';
const root = '/Users/yunshu/Documents/GitHub/cfip-docs-evidence/docs/audits/next-release-evidence/ui-refinement-7c13b1d';
const visualRoot = path.join(root, 'visual');
const manifestPath = path.join(visualRoot, 'captures.json');
const sh = c => execFileSync('docker', ['exec', container, 'sh', '-c', c], { encoding: 'utf8' });
const themes = { bootstrap: { media: '/luci-static/bootstrap', storage: null }, 'aurora-light': { media: '/luci-static/aurora', storage: 'light' }, 'aurora-dark': { media: '/luci-static/aurora', storage: 'dark' } };

async function login(page) {
  await page.goto(base + '/cgi-bin/luci/', { waitUntil: 'domcontentloaded' });
  const u = page.locator('input[name="luci_username"]');
  if (await u.count()) { await u.fill('root'); await page.locator('input[name="luci_password"]').fill('cfip-gate'); await page.locator('button:has-text("Log in"), button:has-text("Login"), input[type="submit"]').first().click(); await page.waitForTimeout(2500); }
}
async function waitView(page) {
  await page.waitForFunction(() => {
    const text = (document.querySelector('#maincontent') || document.body).innerText;
    return text.includes('Measurement Policy') && !/Loading view/.test(text);
  }, null, { timeout: 60000 });
}
(async () => {
  const browser = await chromium.launch({ headless: true });
  const ctx = await browser.newContext({ viewport: { width: 1280, height: 900 } });
  const page = await ctx.newPage();
  const rows = [];
  try {
    await login(page);
    for (const theme of Object.keys(themes)) {
      const t = themes[theme];
      sh(`uci set luci.main.mediaurlbase='${t.media}'; uci commit luci; rm -rf /tmp/luci-indexcache* /tmp/luci-modulecache; /etc/init.d/uhttpd restart >/dev/null 2>&1`);
      await page.waitForTimeout(700);
      if (t.storage) { await page.goto(base + '/cgi-bin/luci/', { waitUntil: 'domcontentloaded' }); await page.evaluate(v => localStorage.setItem('aurora.theme', v), t.storage); }
      for (const [w, h] of [[375, 900], [768, 900], [1280, 900]]) {
        await page.setViewportSize({ width: w, height: h });
        await page.goto(base + '/cgi-bin/luci/admin/services/cf_ip/intelligence', { waitUntil: 'domcontentloaded' });
        await waitView(page);
        await page.waitForTimeout(300);
        const dir = path.join(visualRoot, theme, `${w}x${h}`);
        fs.mkdirSync(dir, { recursive: true });
        const file = path.join(dir, 'intelligence.png');
        await page.screenshot({ path: file });
        const m = await page.evaluate(() => ({
          w: innerWidth, h: innerHeight, scrollWidth: document.documentElement.scrollWidth,
          overflow: document.documentElement.scrollWidth > innerWidth || document.body.scrollWidth > innerWidth,
          textLen: (document.querySelector('#maincontent') || document.body).innerText.length,
          dark: document.documentElement.getAttribute('data-darkmode'),
          footer: !!document.querySelector('.ys-tool-footer'),
          css: !!document.getElementById('cfi-shared-css')
        }));
        rows.push({ sha: '9adb2d5', theme, viewport: `${w}x${h}`, page: 'intelligence', state: 'normal', interaction: 'page', w: m.w, h: m.h, scrollWidth: m.scrollWidth, overflow: m.overflow, textLen: m.textLen, dark: m.dark, login: false, file: `${theme}/${w}x${h}/intelligence.png`, footer: m.footer, css: m.css });
        console.log(theme, `${w}x${h}`, 'textLen', m.textLen, 'footer', m.footer, 'css', m.css);
      }
    }
    const data = JSON.parse(fs.readFileSync(manifestPath, 'utf8'));
    for (const row of rows) {
      const idx = data.rows.findIndex(r => r.theme === row.theme && r.viewport === row.viewport && r.page === 'intelligence');
      const clean = { sha: row.sha, theme: row.theme, viewport: row.viewport, page: row.page, state: row.state, interaction: row.interaction, w: row.w, h: row.h, scrollWidth: row.scrollWidth, overflow: row.overflow, textLen: row.textLen, dark: row.dark, login: row.login, file: row.file };
      if (idx >= 0) data.rows[idx] = clean; else data.rows.push(clean);
    }
    fs.writeFileSync(manifestPath, JSON.stringify(data, null, 2) + '\n');
    fs.writeFileSync('/tmp/cfip-audit/intelligence-recapture.json', JSON.stringify({ rows }, null, 2) + '\n');
    console.log('updated', rows.length, 'intelligence captures');
  } finally {
    await browser.close();
  }
})().catch(e => { console.error(e); process.exit(1); });
