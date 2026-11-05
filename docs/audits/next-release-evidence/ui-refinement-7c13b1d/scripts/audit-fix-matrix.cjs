'use strict';
const fs = require('fs');
const path = require('path');
const { chromium } = require('playwright');
const base = 'http://127.0.0.1:18080';
const out = '/tmp/cfip-audit/matrix';
fs.mkdirSync(out, { recursive: true });

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

(async () => {
  const browser = await chromium.launch({ headless: true });
  const ctx = await browser.newContext({ viewport: { width: 1280, height: 900 } });
  const page = await ctx.newPage();
  const requests = [];
  page.on('request', r => { if (r.method() === 'POST' && r.postData()) { if (/download-cfst|oc-list-backups/.test(r.postData())) requests.push({ url: r.url(), body: r.postData().slice(0, 200) }); } });
  try {
    await login(page);

    // ov-cfst
    await page.goto(base + '/cgi-bin/luci/admin/services/cf_ip/overview', { waitUntil: 'domcontentloaded' });
    await page.waitForTimeout(1200);
    await page.screenshot({ path: path.join(out, 'ov-cfst-before.png') });
    requests.length = 0;
    const cfst = page.locator('button', { hasText: 'Download CFST' }).first();
    await cfst.click();
    await page.waitForTimeout(350);
    const busy = await page.evaluate(() => {
      const b = [...document.querySelectorAll('button')].find(x => /Downloading|Download|Preparing/i.test(x.textContent) && x.disabled);
      return b ? { text: b.textContent.trim(), disabled: b.disabled } : null;
    });
    await page.screenshot({ path: path.join(out, 'ov-cfst-busy.png') });
    let notice = '';
    for (let i = 0; i < 30; i++) {
      const msgs = await page.locator('.alert-message').allTextContents();
      if (msgs.length) { notice = msgs.join(' | '); break; }
      await page.waitForTimeout(500);
    }
    await page.screenshot({ path: path.join(out, 'ov-cfst-after.png') });
    const beforeHash = fs.readFileSync(path.join(out, 'ov-cfst-before.png')).length;
    const afterHash = fs.readFileSync(path.join(out, 'ov-cfst-after.png')).length;
    console.log('ov-cfst', JSON.stringify({ busy, notice, requests, beforeBytes: beforeHash, afterBytes: afterHash }));

    // oc-backup-retry
    await page.goto(base + '/cgi-bin/luci/admin/services/cf_ip/openclash', { waitUntil: 'domcontentloaded' });
    await page.waitForTimeout(2000);
    const alertBefore = await page.locator('.alert-message').allTextContents();
    await page.screenshot({ path: path.join(out, 'oc-backup-retry-before.png') });
    requests.length = 0;
    const retry = page.locator('button', { hasText: 'Retry' }).first();
    await retry.click();
    await page.waitForTimeout(300);
    const retryBusy = await page.locator('button', { hasText: 'Retry' }).first().evaluate(b => ({ disabled: b.disabled, text: b.textContent.trim() }));
    await page.screenshot({ path: path.join(out, 'oc-backup-retry-busy.png') });
    await page.waitForTimeout(2500);
    const alertAfter = await page.locator('.alert-message').allTextContents();
    await page.screenshot({ path: path.join(out, 'oc-backup-retry-after.png') });
    console.log('oc-backup-retry', JSON.stringify({ alertBefore, alertAfter, retryBusy, requests }));

    // log-refresh-diagnostics (second Refresh button)
    await page.goto(base + '/cgi-bin/luci/admin/services/cf_ip/logs', { waitUntil: 'domcontentloaded' });
    await page.waitForTimeout(1500);
    const refreshes = page.locator('button', { hasText: 'Refresh' });
    console.log('refresh count', await refreshes.count());
    await page.screenshot({ path: path.join(out, 'log-refresh2-before.png') });
    await refreshes.nth(1).click();
    await page.waitForTimeout(500);
    const logText1 = await page.locator('.cfi-log-area').first().inputValue().catch(async () => await page.locator('.cfi-log-area').first().innerText());
    await page.waitForTimeout(1500);
    const logText2 = await page.locator('.cfi-log-area').first().inputValue().catch(async () => await page.locator('.cfi-log-area').first().innerText());
    await page.screenshot({ path: path.join(out, 'log-refresh2-after.png') });
    console.log('log-refresh2', JSON.stringify({ logText1: logText1.slice(0, 80), logText2: logText2.slice(0, 80) }));
  } finally {
    await browser.close();
  }
})().catch(e => { console.error(e); process.exit(1); });
