'use strict';
const fs = require('fs');
const path = require('path');
const { chromium } = require('playwright');
const base = 'http://127.0.0.1:18080';
const out = '/tmp/phase-d/intelligence';
fs.mkdirSync(out, { recursive: true });
async function login(page) {
  await page.goto(base + '/cgi-bin/luci/', { waitUntil: 'domcontentloaded' });
  const u = page.locator('input[name="luci_username"]');
  if (await u.count()) { await u.fill('root'); await page.locator('input[name="luci_password"]').fill('cfip-gate'); await page.locator('button:has-text("Log in"), button:has-text("Login"), input[type="submit"]').first().click(); await page.waitForTimeout(2500); }
}
async function openIntelligence(page) {
  await page.goto(base + '/cgi-bin/luci/admin/services/cf_ip/intelligence', { waitUntil: 'domcontentloaded' });
  await page.waitForFunction(() => {
    const t = (document.querySelector('#maincontent') || document.body).innerText;
    return t.includes('Measurement Policy') && !/Loading view/.test(t);
  }, null, { timeout: 60000 });
  await page.waitForTimeout(300);
}
(async () => {
  const browser = await chromium.launch({ headless: true });
  const ctx = await browser.newContext({ viewport: { width: 1280, height: 900 } });
  await ctx.grantPermissions(['clipboard-read', 'clipboard-write'], { origin: base });
  const page = await ctx.newPage();
  const rows = [];
  try {
    await login(page);
    await openIntelligence(page);
    await page.evaluate(() => { localStorage.removeItem('cfi.intelligence.liveState'); });
    await page.reload({ waitUntil: 'domcontentloaded' });
    await page.waitForFunction(() => { const t = (document.querySelector('#maincontent') || document.body).innerText; return t.includes('Measurement Policy') && !/Loading view/.test(t); }, null, { timeout: 60000 });
    await page.screenshot({ path: path.join(out, 'intelligence-default-collapsed.png') });

    const collapsed = await page.evaluate(() => {
      const toggle = document.querySelector('.cfi-collapse-toggle');
      const body = document.querySelector('#cfi-live-state-body');
      return {
        toggle: !!toggle, toggleText: toggle ? toggle.textContent.trim() : '', ariaExpanded: toggle ? toggle.getAttribute('aria-expanded') : null,
        bodyHidden: body ? body.hidden : null, copyButtons: document.querySelectorAll('.cfi-copy-btn').length,
        logsLinks: document.querySelectorAll('.cfi-link-button[href*="/logs"]').length
      };
    });
    rows.push({ test: 'default-collapsed', ...collapsed });

    const toggle = page.locator('.cfi-collapse-toggle');
    await toggle.focus();
    await page.keyboard.press('Enter');
    await page.waitForTimeout(300);
    const expanded = await page.evaluate(() => {
      const t = document.querySelector('.cfi-collapse-toggle');
      const body = document.querySelector('#cfi-live-state-body');
      return { ariaExpanded: t.getAttribute('aria-expanded'), text: t.textContent.trim(), bodyHidden: body.hidden, persisted: localStorage.getItem('cfi.intelligence.liveState') };
    });
    await page.screenshot({ path: path.join(out, 'intelligence-expanded.png') });
    rows.push({ test: 'toggle-enter', ...expanded });

    await page.reload({ waitUntil: 'domcontentloaded' });
    await page.waitForFunction(() => { const t = (document.querySelector('#maincontent') || document.body).innerText; return t.includes('Measurement Policy') && !/Loading view/.test(t); }, null, { timeout: 60000 });
    const persisted = await page.evaluate(() => {
      const t = document.querySelector('.cfi-collapse-toggle');
      const body = document.querySelector('#cfi-live-state-body');
      return { ariaExpanded: t.getAttribute('aria-expanded'), bodyHidden: body.hidden };
    });
    rows.push({ test: 'persisted-after-reload', ...persisted });

    // Copy success with clipboard API
    const copyBtn = page.locator('.cbi-value[id$="-_endpoint"] .cfi-copy-btn').first();
    await copyBtn.click();
    await page.waitForTimeout(300);
    const copied = await page.evaluate(async () => ({ text: await navigator.clipboard.readText(), label: document.querySelector('.cbi-value[id$="-_endpoint"] .cfi-copy-btn').textContent.trim() }));
    await page.screenshot({ path: path.join(out, 'intelligence-copy-success.png') });
    rows.push({ test: 'copy-success', ...copied });

    // Copy failure: force clipboard API absent and execCommand rejected
    await page.evaluate(() => {
      Object.defineProperty(navigator, 'clipboard', { value: undefined, configurable: true });
      document.execCommand = () => false;
    });
    await page.locator('.cbi-value[id$="-_runtime_path"] .cfi-copy-btn').first().click();
    await page.locator('text=Unable to copy').waitFor({ timeout: 5000 });
    const copyError = (await page.locator('.alert-message').allTextContents()).join(' | ');
    await page.screenshot({ path: path.join(out, 'intelligence-copy-failure.png') });
    rows.push({ test: 'copy-fallback-failure', notification: copyError });

    // Recent Runs -> Logs link and back link
    await page.evaluate(() => { Object.defineProperty(navigator, 'clipboard', { value: navigator.clipboard, configurable: true }); });
    await page.locator('.cbi-value[id$="-_run_history"] .cfi-link-button').click();
    await page.waitForURL(/\/logs/, { timeout: 10000 });
    const back = page.locator('a.cfi-link-button', { hasText: 'Open Intelligence' });
    await back.waitFor({ timeout: 30000 });
    await page.screenshot({ path: path.join(out, 'logs-open-intelligence.png') });
    await back.click();
    await page.waitForURL(/\/intelligence/, { timeout: 10000 });
    rows.push({ test: 'recent-runs-to-logs', logsUrl: base + '/cgi-bin/luci/admin/services/cf_ip/logs', backLink: 1, returnedUrl: page.url() });

    fs.writeFileSync(path.join(out, 'intelligence.json'), JSON.stringify({ base, rows }, null, 2) + '\n');
    console.log(JSON.stringify(rows, null, 2));
  } finally {
    await browser.close();
  }
})().catch(e => { console.error(e); process.exit(1); });
