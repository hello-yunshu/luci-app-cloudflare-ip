'use strict';
const fs = require('fs');
const path = require('path');
const { execFileSync } = require('child_process');
const { chromium } = require('playwright');
const base = 'http://127.0.0.1:18080';
const container = 'cfip-ui-gate';
const out = '/tmp/phase-d/openclash';
const sh = c => execFileSync('docker', ['exec', container, 'sh', '-c', c], { encoding: 'utf8' });
const cfg = '/etc/openclash/config/config.yaml';
(async () => {
  sh(`printf 'mixed-port: 7893\\nallow-lan: false\\nmode: rule\\nlog-level: warning\\nproxies: []\\nproxy-groups: []\\nrules:\\n  - MATCH,DIRECT\\n' > ${cfg}.bak.20261104000004; chmod 600 ${cfg}.bak.20261104000004; rm -rf /tmp/luci-indexcache* /tmp/luci-modulecache; /etc/init.d/openclash restart >/dev/null 2>&1`);
  const browser = await chromium.launch({ headless: true });
  const ctx = await browser.newContext({ viewport: { width: 1280, height: 900 } });
  const page = await ctx.newPage();
  let navigations = 0;
  page.on('framenavigated', f => { if (f === page.mainFrame()) navigations++; });
  try {
    await page.goto(base + '/cgi-bin/luci/', { waitUntil: 'domcontentloaded' });
    const u = page.locator('input[name="luci_username"]');
    if (await u.count()) { await u.fill('root'); await page.locator('input[name="luci_password"]').fill('cfip-gate'); await page.locator('button:has-text("Log in"), button:has-text("Login"), input[type="submit"]').first().click(); await page.waitForTimeout(2500); }
    await page.goto(base + '/cgi-bin/luci/admin/services/cf_ip/openclash', { waitUntil: 'domcontentloaded' });
    await page.waitForFunction(() => { const t = (document.querySelector('#maincontent') || document.body).innerText; return t.includes('Config Backups') && !/Loading view/.test(t); }, null, { timeout: 30000 });
    await page.evaluate(() => { window.__phaseDSentinel = true; });
    const beforeNav = navigations;
    await page.locator('button:has-text("Delete")').first().click();
    await page.locator('.modal').waitFor();
    await page.locator('.modal button:has-text("Delete")').click();
    await page.locator('text=Backup deleted').waitFor({ timeout: 10000 });
    await page.screenshot({ path: path.join(out, 'delete-success-notice.png') });
    await page.waitForTimeout(1500);
    const sentinel = await page.evaluate(() => window.__phaseDSentinel === true).catch(() => false);
    const fileAfter = sh(`test -f ${cfg}.bak.20261104000004 && echo present || echo missing`).trim();
    const result = { path: 'delete-success', notification: 'Backup deleted', reloadCount: navigations - beforeNav, sentinelAfter: sentinel, fileAfter };
    fs.writeFileSync(path.join(out, 'delete-success.json'), JSON.stringify(result, null, 2) + '\n');
    console.log(JSON.stringify(result, null, 2));
  } finally {
    await browser.close();
  }
})().catch(e => { console.error(e); process.exit(1); });
