'use strict';
const fs = require('fs');
const path = require('path');
const { execFileSync } = require('child_process');
const { chromium } = require('playwright');
const base = 'http://127.0.0.1:18080';
const container = 'cfip-ui-gate';
const out = '/tmp/cfip-audit/matrix';
fs.mkdirSync(out, { recursive: true });
const sh = c => execFileSync('docker', ['exec', container, 'sh', '-c', c], { encoding: 'utf8' });

async function login(page) {
  await page.goto(base + '/cgi-bin/luci/', { waitUntil: 'domcontentloaded' });
  const u = page.locator('input[name="luci_username"]');
  if (await u.count()) { await u.fill('root'); await page.locator('input[name="luci_password"]').fill('cfip-gate'); await page.locator('button:has-text("Log in"), button:has-text("Login"), input[type="submit"]').first().click(); await page.waitForTimeout(2500); }
}
async function waitView(page) {
  await page.waitForFunction(() => {
    const t = (document.querySelector('#maincontent') || document.body).innerText;
    return t.length > 100 && !/Loading view/.test(t);
  }, null, { timeout: 60000 });
}
async function getUci(page, section, option) {
  return page.evaluate(async ([s, o]) => { const u = await L.require('uci'); return u.get('cf_ip', s, o); }, [section, option]);
}
async function savePoint(page, id, pageName, label, value, section, option, out) {
  await page.goto(base + '/cgi-bin/luci/admin/services/cf_ip/' + pageName, { waitUntil: 'domcontentloaded' });
  await waitView(page);
  if (!page.url().includes('/cf_ip/' + pageName)) throw new Error('redirected to ' + page.url());
  await page.screenshot({ path: path.join(out, `${id}-before.png`) });
  const field = page.locator('.cbi-value', { hasText: label }).first().locator('input, select, textarea').first();
  await field.fill(value);
  await page.locator('button.cbi-button-save').first().click();
  await page.waitForTimeout(1200);
  const browserValue = await getUci(page, section, option);
  const changes = await page.evaluate(async () => { const u = await L.require('uci'); return u.changes('cf_ip'); });
  await page.screenshot({ path: path.join(out, `${id}-after.png`) });
  return { id, page: pageName, assertions: { browserValue, changes: Object.keys(changes || {}).length, formValue: await field.inputValue().catch(() => null) } };
}
(async () => {
  const browser = await chromium.launch({ headless: true });
  const ctx = await browser.newContext({ viewport: { width: 1280, height: 900 } });
  const page = await ctx.newPage();
  const results = [];
  try {
    sh('printf "#!/bin/sh\\nexit 1\\n" > /etc/init.d/openclash; printf "#!/bin/sh\\nexit 1\\n" > /etc/init.d/passwall; chmod +x /etc/init.d/openclash /etc/init.d/passwall; rm -rf /tmp/luci-indexcache* /tmp/luci-modulecache');
    await login(page);
    results.push(await savePoint(page, 'set-save', 'settings', 'IP Count', '16', 'main', 'ip_count', out));
    results.push(await savePoint(page, 'src-save', 'sources', 'CFST Candidate IP Count', '256', 'main', 'candidate_budget', out));
    results.push(await savePoint(page, 'int-save', 'intelligence', 'Probe Batch Size', '5', 'main', 'probe_batch_size', out));
    results.push(await savePoint(page, 'oc-save', 'openclash', 'Backup Count', '3', 'openclash', 'backup_count', out));
    results.push(await savePoint(page, 'pw-save', 'passwall', 'Node Name Suffix', ' [CF-{n}]', 'passwall', 'name_suffix', out));
    results.push(await savePoint(page, 'adv-save', 'advanced', 'Download Retries', '3', 'main', 'download_retries', out));

    // Real Save & Apply + server readback
    await page.goto(base + '/cgi-bin/luci/admin/services/cf_ip/settings', { waitUntil: 'domcontentloaded' });
    await waitView(page);
    await page.screenshot({ path: path.join(out, 'set-apply-before.png') });
    const f = page.locator('.cbi-value', { hasText: 'IP Count' }).first().locator('input').first();
    await f.fill('8');
    const dd = page.locator('.cbi-dropdown').filter({ hasText: 'Save & Apply' }).first();
    await dd.click();
    await page.waitForTimeout(300);
    await page.locator('.cbi-dropdown ul li').filter({ hasText: 'Save & Apply' }).first().click();
    await page.waitForTimeout(4000);
    const serverValue = sh('uci get cf_ip.main.ip_count').trim();
    await page.screenshot({ path: path.join(out, 'set-apply-after.png') });
    results.push({ id: 'set-apply', page: 'settings', assertions: { serverValue, formValue: await f.inputValue() } });

    // Intelligence long-field content check (read-only)
    await page.goto(base + '/cgi-bin/luci/admin/services/cf_ip/intelligence', { waitUntil: 'domcontentloaded' });
    await waitView(page);
    await page.screenshot({ path: path.join(out, 'int-long-values-before.png') });
    const metrics = await page.evaluate(() => {
      const fields = [...document.querySelectorAll('.cbi-value-field')];
      const long = fields.filter(f => f.textContent.trim().length > 80);
      return { fields: fields.length, longFields: long.length, overflow: document.documentElement.scrollWidth > innerWidth, clipped: long.filter(f => f.scrollWidth > f.clientWidth + 1).length };
    });
    await page.screenshot({ path: path.join(out, 'int-long-values-after.png') });
    results.push({ id: 'int-long-values', page: 'intelligence', assertions: metrics, readOnly: true });
    fs.writeFileSync(path.join(out, 'fixes.json'), JSON.stringify(results, null, 2) + '\n');
    console.log(JSON.stringify(results, null, 2));
  } finally {
    await browser.close();
    sh('uci revert cf_ip >/dev/null 2>&1 || true; rm -f /etc/init.d/openclash /etc/init.d/passwall; rm -rf /tmp/luci-indexcache*');
  }
})().catch(e => { console.error(e); process.exit(1); });
