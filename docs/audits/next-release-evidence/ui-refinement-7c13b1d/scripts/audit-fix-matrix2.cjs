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
  const user = page.locator('input[name="luci_username"]');
  if (await user.count()) {
    await user.fill('root');
    await page.locator('input[name="luci_password"]').fill('cfip-gate');
    await page.locator('button:has-text("Log in"), button:has-text("Login"), input[type="submit"]').first().click();
    await page.waitForTimeout(2500);
  }
}

(async () => {
  sh(`cp /usr/bin/cf-ip-auto /usr/bin/cf-ip-auto.real
cat > /usr/bin/cf-ip-auto <<'EOF'
#!/bin/sh
if [ "$1" = "--oc-list-backups" ] && [ ! -f /tmp/oc-backup-allow ]; then
  touch /tmp/oc-backup-allow
  echo '{"success":false,"error":"fixture: backup listing unavailable"}'
  exit 0
fi
exec /usr/bin/cf-ip-auto.real "$@"
EOF
chmod +x /usr/bin/cf-ip-auto
rm -f /tmp/oc-backup-allow
rm -rf /tmp/luci-indexcache* /tmp/luci-modulecache`);
  const browser = await chromium.launch({ headless: true });
  const ctx = await browser.newContext({ viewport: { width: 1280, height: 900 } });
  const page = await ctx.newPage();
  const requests = [];
  page.on('request', r => { if (r.method() === 'POST' && r.postData() && r.postData().includes('oc-list-backups')) requests.push(r.postData().slice(0, 160)); });
  try {
    await login(page);
    await page.goto(base + '/cgi-bin/luci/admin/services/cf_ip/openclash', { waitUntil: 'domcontentloaded' });
    await page.locator('.alert-message.error').waitFor({ timeout: 20000 });
    const alertBefore = await page.locator('.alert-message.error').allTextContents();
    await page.screenshot({ path: path.join(out, 'oc-backup-retry-before.png') });
    requests.length = 0;
    const retry = page.locator('button', { hasText: 'Retry' }).first();
    await retry.click();
    await page.waitForTimeout(300);
    await page.screenshot({ path: path.join(out, 'oc-backup-retry-busy.png') });
    await page.waitForTimeout(2500);
    const alertAfter = await page.locator('.alert-message.error').allTextContents();
    const tableRows = await page.locator('#oc-backups-section tbody tr').count();
    await page.screenshot({ path: path.join(out, 'oc-backup-retry-after.png') });
    console.log('oc-backup-retry', JSON.stringify({ alertBefore, alertAfter, tableRows, requests }));

    // log refresh second button
    await page.goto(base + '/cgi-bin/luci/admin/services/cf_ip/logs', { waitUntil: 'domcontentloaded' });
    await page.waitForTimeout(1500);
    const refreshes = page.locator('button', { hasText: 'Refresh' });
    const refreshCount = await refreshes.count();
    await page.screenshot({ path: path.join(out, 'log-refresh2-before.png') });
    const beforeText = await page.locator('.cfi-log-area').first().inputValue().catch(async () => await page.locator('.cfi-log-area').first().innerText());
    await refreshes.nth(1).click();
    await page.waitForTimeout(500);
    const busyText = await page.locator('button', { hasText: 'Loading' }).count();
    await page.waitForTimeout(1800);
    const afterText = await page.locator('.cfi-log-area').first().inputValue().catch(async () => await page.locator('.cfi-log-area').first().innerText());
    await page.screenshot({ path: path.join(out, 'log-refresh2-after.png') });
    console.log('log-refresh2', JSON.stringify({ refreshCount, busyText, beforeText: beforeText.slice(0, 60), afterText: afterText.slice(0, 60) }));
  } finally {
    await browser.close();
    sh(`if [ -f /usr/bin/cf-ip-auto.real ]; then mv /usr/bin/cf-ip-auto.real /usr/bin/cf-ip-auto; fi
rm -f /tmp/oc-backup-allow
rm -rf /tmp/luci-indexcache* /tmp/luci-modulecache`);
  }
})().catch(e => { console.error(e); process.exit(1); });
