'use strict';
const fs = require('fs');
const path = require('path');
const { execFileSync } = require('child_process');
const { chromium } = require('playwright');
const base = 'http://127.0.0.1:18080';
const container = 'cfip-ui-gate';
const out = '/tmp/phase-d/speedtest';
fs.mkdirSync(out, { recursive: true });
const sh = c => execFileSync('docker', ['exec', container, 'sh', '-c', c], { encoding: 'utf8' });

function writeState(result, log) {
  const running = result === 'running';
  const status = {
    running, last_run: '2026-11-04 04:40:00', last_result: result,
    mode: 'passwall', ip_type: 'ipv4', ip_count: 8, speedtest_protocol: 'tcping',
    best_ips: [], cfst_version: '1.0.0', script_version: '2.6.0', error: result === 'error' ? 'synthetic CFST failure' : '',
    active_run: running, jobRunning: running
  };
  sh(`mkdir -p /etc/cf_ip /tmp/cf_ip; chmod 700 /etc/cf_ip; cat > /etc/cf_ip/status.json <<'EOF'
${JSON.stringify(status)}
EOF
printf '%s\\n' '${log.replace(/'/g, "'\\''")}' > /tmp/cf_ip/cf-ip-auto.log`);
}
async function login(page) {
  await page.goto(base + '/cgi-bin/luci/', { waitUntil: 'domcontentloaded' });
  const u = page.locator('input[name="luci_username"]');
  if (await u.count()) { await u.fill('root'); await page.locator('input[name="luci_password"]').fill('cfip-gate'); await page.locator('button:has-text("Log in"), button:has-text("Login"), input[type="submit"]').first().click(); await page.waitForTimeout(2500); }
}
async function openOverview(page) {
  await page.goto(base + '/cgi-bin/luci/admin/services/cf_ip/overview', { waitUntil: 'domcontentloaded' });
  await page.waitForFunction(() => {
    const t = (document.querySelector('#maincontent') || document.body).innerText;
    return t.includes('Service Information') && !/Loading view/.test(t);
  }, null, { timeout: 30000 });
  await page.waitForTimeout(400);
}
(async () => {
  writeState('running', 'Running CFST speedtest; measuring 8 candidates...');
  const browser = await chromium.launch({ headless: true });
  const ctx = await browser.newContext({ viewport: { width: 1280, height: 900 } });
  const page = await ctx.newPage();
  const rows = [];
  try {
    await login(page);
    await openOverview(page);
    const runningButton = page.locator('button.cfi-badge', { hasText: 'Running' }).first();
    await runningButton.waitFor({ timeout: 15000 });
    await page.screenshot({ path: path.join(out, 'overview-running.png') });
    await runningButton.click();
    await page.locator('.modal').waitFor();
    await page.waitForFunction(() => {
      const t = document.querySelector('.modal .cfi-log-area');
      return t && t.value && t.value !== 'Loading...';
    }, null, { timeout: 15000 }).catch(() => {});
    const modalTitle = await page.locator('.modal h4, .modal .modal-title').first().innerText().catch(() => '');
    const runningBadge = await page.locator('.modal .cfi-badge').first().innerText();
    const runningLog = await page.locator('.modal .cfi-log-area').first().inputValue().catch(async () => await page.locator('.modal .cfi-log-area').first().innerText());
    await page.screenshot({ path: path.join(out, 'modal-running.png') });
    rows.push({ state: 'running', modalTitle, badge: runningBadge, log: runningLog, status: JSON.parse(sh('cat /etc/cf_ip/status.json')).last_result });

    writeState('success', 'Speedtest completed; selected 8 IPs; best=104.16.1.1');
    await page.locator('.modal button:has-text("Refresh")').click();
    await page.waitForTimeout(800);
    const successBadge = await page.locator('.modal .cfi-badge').first().innerText();
    const successLog = await page.locator('.modal .cfi-log-area').first().inputValue().catch(async () => await page.locator('.modal .cfi-log-area').first().innerText());
    await page.screenshot({ path: path.join(out, 'modal-success.png') });
    rows.push({ state: 'success', badge: successBadge, log: successLog, status: JSON.parse(sh('cat /etc/cf_ip/status.json')).last_result });

    writeState('error', 'ERROR: CFST run failed: synthetic failure');
    await page.locator('.modal button:has-text("Refresh")').click();
    await page.waitForTimeout(800);
    const errorBadge = await page.locator('.modal .cfi-badge').first().innerText();
    const errorLog = await page.locator('.modal .cfi-log-area').first().inputValue().catch(async () => await page.locator('.modal .cfi-log-area').first().innerText());
    await page.screenshot({ path: path.join(out, 'modal-error.png') });
    rows.push({ state: 'error', badge: errorBadge, log: errorLog, status: JSON.parse(sh('cat /etc/cf_ip/status.json')).last_result });
    fs.writeFileSync(path.join(out, 'speedtest.json'), JSON.stringify({ base, container, rows }, null, 2) + '\n');
    console.log(JSON.stringify(rows, null, 2));
  } finally {
    await browser.close();
  }
})().catch(e => { console.error(e); process.exit(1); });
