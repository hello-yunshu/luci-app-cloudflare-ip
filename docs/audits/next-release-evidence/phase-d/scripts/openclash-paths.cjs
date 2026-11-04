'use strict';
const fs = require('fs');
const path = require('path');
const { execFileSync } = require('child_process');
const { chromium } = require('playwright');
const base = 'http://127.0.0.1:18080';
const container = 'cfip-ui-gate';
const out = '/tmp/phase-d/openclash';
fs.mkdirSync(out, { recursive: true });
const sh = c => execFileSync('docker', ['exec', container, 'sh', '-c', c], { encoding: 'utf8' });
const cfg = '/etc/openclash/config/config.yaml';

async function login(page) {
  await page.goto(base + '/cgi-bin/luci/', { waitUntil: 'domcontentloaded' });
  const u = page.locator('input[name="luci_username"]');
  if (await u.count()) { await u.fill('root'); await pwd(page); }
}
async function pwd(page) {
  await page.locator('input[name="luci_password"]').fill('cfip-gate');
  await page.locator('button:has-text("Log in"), button:has-text("Login"), input[type="submit"]').first().click();
  await page.waitForTimeout(2500);
}
async function seedBackup(id) {
  sh(`printf 'mixed-port: 7892\\nallow-lan: false\\nmode: rule\\nlog-level: warning\\nproxies: []\\nproxy-groups: []\\nrules:\\n  - MATCH,DIRECT\\n' > ${cfg}.bak.${id}; chmod 600 ${cfg}.bak.${id}; rm -rf /tmp/luci-indexcache* /tmp/luci-modulecache`);
}
async function openPage(page) {
  await page.goto(base + '/cgi-bin/luci/admin/services/cf_ip/openclash', { waitUntil: 'domcontentloaded' });
  await page.waitForFunction(() => {
    const t = (document.querySelector('#maincontent') || document.body).innerText;
    return t.includes('Config Backups') && !/Loading view/.test(t);
  }, null, { timeout: 30000 });
  await page.waitForTimeout(500);
}
(async () => {
  const browser = await chromium.launch({ headless: true });
  const ctx = await browser.newContext({ viewport: { width: 1280, height: 900 } });
  const page = await ctx.newPage();
  const rows = [];
  try {
    await login(page);
    // Delete success
    seedBackup('20261104000001');
    await openPage(page);
    await page.screenshot({ path: path.join(out, 'delete-before.png') });
    const del = page.locator('button:has-text("Delete")').first();
    await del.click();
    await page.locator('.modal').waitFor();
    await page.locator('.modal button:has-text("Delete")').click();
    await page.locator('text=Backup deleted').waitFor({ timeout: 10000 });
    await page.screenshot({ path: path.join(out, 'delete-success-notice.png') });
    const fileAfter = sh(`test -f ${cfg}.bak.20261104000001 && echo present || echo missing`).trim();
    await page.waitForTimeout(1200);
    rows.push({ path: 'delete-success', notification: 'Backup deleted', fileAfter });

    // Delete failure
    seedBackup('20261104000002');
    await openPage(page);
    await page.screenshot({ path: path.join(out, 'delete-failure-before.png') });
    await page.locator('button:has-text("Delete")').first().click();
    await page.locator('.modal').waitFor();
    sh('mv /bin/rm /bin/rm.real; printf "#!/bin/sh\\nexit 1\\n" > /bin/rm; chmod +x /bin/rm');
    await page.evaluate(() => { window.__cfipPhaseDSentinel = true; });
    await page.locator('.modal button:has-text("Delete")').click();
    await page.locator('text=Unable to delete backup').waitFor({ timeout: 10000 });
    const notice = (await page.locator('.alert-message').allTextContents()).join(' | ');
    const sentinel = await page.evaluate(() => window.__cfipPhaseDSentinel === true);
    const fileFail = sh(`test -f ${cfg}.bak.20261104000002 && echo present || echo missing`).trim();
    await page.screenshot({ path: path.join(out, 'delete-failure-after.png') });
    rows.push({ path: 'delete-failure', notification: notice, noReload: sentinel, fileAfter: fileFail });
    sh('mv /bin/rm.real /bin/rm');

    // Restore failure (real backend refuses unsupported YAML because Ruby/Psych is unavailable)
    seedBackup('20261104000003');
    await openPage(page);
    const beforeConfig = sh(`sha256sum ${cfg}`).trim();
    await page.screenshot({ path: path.join(out, 'restore-failure-before.png') });
    await page.locator('button:has-text("Restore")').first().click();
    await page.locator('.modal').waitFor();
    await page.evaluate(() => { window.__cfipPhaseDSentinel = true; });
    await page.locator('.modal button:has-text("Restore")').click();
    await page.locator('text=Unable to restore backup').waitFor({ timeout: 20000 });
    const restoreNotice = (await page.locator('.alert-message').allTextContents()).join(' | ');
    const restoreSentinel = await page.evaluate(() => window.__cfipPhaseDSentinel === true);
    const afterConfig = sh(`sha256sum ${cfg}`).trim();
    await page.screenshot({ path: path.join(out, 'restore-failure-after.png') });
    rows.push({ path: 'restore-failure', notification: restoreNotice, noReload: restoreSentinel, configUnchanged: beforeConfig === afterConfig });
    fs.writeFileSync(path.join(out, 'openclash.json'), JSON.stringify({ base, container, rows }, null, 2) + '\n');
    console.log(JSON.stringify(rows, null, 2));
  } finally {
    await browser.close();
    sh('if [ -f /bin/rm.real ]; then mv /bin/rm.real /bin/rm; fi; rm -rf /tmp/luci-indexcache*');
  }
})().catch(e => { console.error(e); process.exit(1); });
