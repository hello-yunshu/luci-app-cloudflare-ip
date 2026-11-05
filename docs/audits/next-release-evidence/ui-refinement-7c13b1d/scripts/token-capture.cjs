'use strict';
const fs = require('fs');
const path = require('path');
const { chromium } = require('playwright');

const base = process.argv[2];
const label = process.argv[3];
const out = path.join('/tmp/cfip-evidence/token-footer', label);
fs.mkdirSync(out, { recursive: true });

(async () => {
  const browser = await chromium.launch({ headless: true });
  const ctx = await browser.newContext({ viewport: { width: 1280, height: 900 } });
  const page = await ctx.newPage();
  await page.goto(base + '/cgi-bin/luci/', { waitUntil: 'domcontentloaded' });
  const user = page.locator('input[name="luci_username"]');
  if (await user.count()) {
    await user.fill('root');
    await page.locator('input[name="luci_password"]').fill('cfip-gate');
    await page.locator('button:has-text("Log in"), button:has-text("Login"), input[type="submit"]').first().click();
    await page.waitForTimeout(2500);
  }
  const rows = [];
  for (const p of ['overview', 'settings', 'sources']) {
    await page.goto(base + '/cgi-bin/luci/admin/services/cf_ip/' + p, { waitUntil: 'domcontentloaded' });
    await page.waitForTimeout(1200);
    await page.screenshot({ path: path.join(out, p + '.png') });
    rows.push(await page.evaluate(pg => {
      const cs = s => { const e = document.querySelector(s); if (!e) return null; const c = getComputedStyle(e); return { radius: c.borderTopLeftRadius, shadow: c.boxShadow }; };
      return {
        page: pg,
        section: cs('.cfi-form-map .cbi-section, .cfi-dashboard .cbi-section'),
        stat: cs('.cfi-stat-card'),
        table: cs('.cfi-table-wrap > .table, .cfi-section-table'),
        cmd: cs('.cfi-cmd-box'),
        badge: cs('.cfi-badge'),
        footer: cs('.ys-tool-footer'),
        footerMark: cs('.ys-tool-footer-mark'),
        footerLink: cs('.ys-tool-footer-link')
      };
    }, p));
  }
  fs.writeFileSync(path.join(out, 'metrics.json'), JSON.stringify({ base, label, rows }, null, 2) + '\n');
  console.log(JSON.stringify(rows, null, 2));
  await browser.close();
})().catch(e => { console.error(e); process.exit(1); });
