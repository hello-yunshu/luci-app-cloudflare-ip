'use strict';
const fs = require('fs');
const path = require('path');
const { execFileSync } = require('child_process');
const { chromium } = require('playwright');
const base = 'http://127.0.0.1:18080';
const container = 'cfip-ui-gate';
const out = '/tmp/cfip-audit/tokens';
fs.mkdirSync(out, { recursive: true });
const sh = c => execFileSync('docker', ['exec', container, 'sh', '-c', c], { encoding: 'utf8' });
const pages = ['overview', 'settings', 'sources', 'intelligence', 'openclash', 'passwall', 'advanced', 'logs'];
const themes = { bootstrap: { media: '/luci-static/bootstrap', storage: null }, 'aurora-light': { media: '/luci-static/aurora', storage: 'light' }, 'aurora-dark': { media: '/luci-static/aurora', storage: 'dark' } };
async function login(page) {
  await page.goto(base + '/cgi-bin/luci/', { waitUntil: 'domcontentloaded' });
  const u = page.locator('input[name="luci_username"]');
  if (await u.count()) { await u.fill('root'); await page.locator('input[name="luci_password"]').fill('cfip-gate'); await page.locator('button:has-text("Log in"), button:has-text("Login"), input[type="submit"]').first().click(); await page.waitForTimeout(2500); }
}
(async () => {
  sh('printf "#!/bin/sh\\nexit 1\\n" > /etc/init.d/openclash; printf "#!/bin/sh\\nexit 1\\n" > /etc/init.d/passwall; chmod +x /etc/init.d/openclash /etc/init.d/passwall; rm -rf /tmp/luci-indexcache* /tmp/luci-modulecache');
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
      for (const p of pages) {
        await page.goto(base + '/cgi-bin/luci/admin/services/cf_ip/' + p, { waitUntil: 'domcontentloaded' });
        await page.waitForFunction(() => {
          const text = (document.querySelector('#maincontent') || document.body).innerText;
          return text.length > 100 && !/Loading view/.test(text);
        }, null, { timeout: 60000 }).catch(() => {});
        await page.waitForTimeout(300);
        rows.push(await page.evaluate(pg => {
          const footer = document.querySelector('.ys-tool-footer');
          const section = document.querySelector('.cfi-dashboard .cbi-section, .cfi-form-map .cbi-section');
          const stat = document.querySelector('.cfi-stat-card');
          const table = document.querySelector('.cfi-table-wrap > .table');
          return {
            page: pg,
            theme: document.documentElement.getAttribute('data-darkmode') === 'true' ? 'dark' : 'light',
            css: !!document.getElementById('cfi-shared-css'),
            footer: footer ? 1 : 0,
            footerText: footer ? footer.innerText.replace(/\s+/g, ' ').trim().slice(0, 80) : '',
            sectionRadius: section ? getComputedStyle(section).borderTopLeftRadius : null,
            statRadius: stat ? getComputedStyle(stat).borderTopLeftRadius : null,
            tableRadius: table ? getComputedStyle(table).borderTopLeftRadius : null,
            overflow: document.documentElement.scrollWidth > innerWidth
          };
        }, p));
      }
    }
  } finally {
    await browser.close();
    sh('rm -f /etc/init.d/openclash /etc/init.d/passwall; rm -rf /tmp/luci-indexcache* /tmp/luci-modulecache');
  }
  fs.writeFileSync(path.join(out, 'tokens.json'), JSON.stringify({ rows }, null, 2) + '\n');
  console.log(rows.map(r => `${r.page}: css=${r.css} footer=${r.footer} section=${r.sectionRadius} stat=${r.statRadius} table=${r.tableRadius} overflow=${r.overflow}`).join('\n'));
})().catch(e => { console.error(e); process.exit(1); });
