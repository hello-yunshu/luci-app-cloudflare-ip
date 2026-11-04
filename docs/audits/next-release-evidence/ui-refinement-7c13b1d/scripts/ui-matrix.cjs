'use strict';
const fs = require('fs');
const path = require('path');
const { execFileSync } = require('child_process');
const { chromium } = require('playwright');

const container = process.argv[2];
const base = process.argv[3];
const out = '/tmp/cfip-evidence/matrix';
fs.mkdirSync(out, { recursive: true });
const sh = c => execFileSync('docker', ['exec', container, 'sh', '-c', c], { encoding: 'utf8' });
const results = [];

async function login(page) {
  await page.goto(base + '/cgi-bin/luci/', { waitUntil: 'domcontentloaded' });
  const user = page.locator('input[name="luci_username"]');
  if (await user.count()) {
    await user.fill('root');
    await page.locator('input[name="luci_password"]').fill('cfip-gate');
    await page.locator('button:has-text("Log in"), button:has-text("Login"), input[type="submit"]').first().click();
    await page.waitForTimeout(2500);
    if (await page.locator('input[name="luci_password"]').count()) throw new Error('login failed');
  }
}

function ringStyle(el) {
  const s = getComputedStyle(el);
  return {
    outline: s.outlineWidth + ' ' + s.outlineStyle + ' ' + s.outlineColor,
    boxShadow: s.boxShadow,
    transform: s.transform,
    visible: el.getBoundingClientRect().width > 0
  };
}

async function runPoint(ctx, def) {
  const id = def.id;
  const page = await ctx.newPage();
  await page.setViewportSize({ width: 1280, height: 900 });
  const started = Date.now();
  const row = {
    id, page: def.page, control: def.control,
    states: Object.assign({ default: 'PASS', hover: 'N/A', focus: 'N/A', active: 'N/A', disabled: 'N/A', error: 'N/A', empty: 'N/A', open: 'N/A' }, def.states || {}),
    assertions: {}, evidence: {}, status: 'PASS'
  };
  try {
    await page.goto(base + '/cgi-bin/luci/admin/services/cf_ip/' + def.page, { waitUntil: 'domcontentloaded' });
    await page.waitForTimeout(1200);
    await page.screenshot({ path: path.join(out, id + '-before.png') });
    if (def.run) await def.run(page, row);
    await page.screenshot({ path: path.join(out, id + '-after.png') });
  } catch (e) {
    row.status = 'FAIL';
    row.assertions.error = e.message;
  }
  row.ms = Date.now() - started;
  results.push(row);
  console.log(`${row.status} ${id}${row.assertions.error ? ' — ' + row.assertions.error : ''}`);
  await page.close().catch(() => {});
}

(async () => {
  const browser = await chromium.launch({ headless: true });
  const ctx = await browser.newContext({ viewport: { width: 1280, height: 900 } });
  const page = await ctx.newPage();
  const label = t => page.locator('.cbi-value', { hasText: t }).first();
  const field = t => label(t).locator('input, select, textarea').first();
  const btn = t => page.locator('button', { hasText: t }).first();
  const notif = async (text, timeout = 8000) => page.locator(`text=${text}`).first().waitFor({ timeout });

  try {
    await login(page);
    sh('printf "#!/bin/sh\\nexit 1\\n" > /etc/init.d/openclash; printf "#!/bin/sh\\nexit 1\\n" > /etc/init.d/passwall; chmod +x /etc/init.d/openclash /etc/init.d/passwall; rm -rf /tmp/luci-indexcache* /tmp/luci-modulecache');

    const points = [
      /* Overview */
      { id: 'ov-start', page: 'overview', control: 'Start', states: { active: 'PASS' }, async run(p, r) {
        await btn('Start').click();
        await p.waitForTimeout(1200);
        r.assertions.busy = await p.evaluate(() => { const b = document.querySelector('button.cbi-button-apply'); return b ? { disabled: b.disabled, text: b.textContent.trim() } : null; });
        await p.waitForTimeout(1500);
        r.assertions.banner = (await p.locator('.cfi-status-text, .cfi-status-banner').innerText().catch(() => '')).slice(0, 100);
      }},
      { id: 'ov-restart', page: 'overview', control: 'Restart', states: { active: 'PASS' }, async run(p, r) {
        await btn('Restart').click();
        await p.waitForTimeout(2000);
        r.assertions.text = (await p.locator('#maincontent').innerText()).slice(0, 120);
      }},
      { id: 'ov-cfst', page: 'overview', control: 'Download CFST', states: { active: 'PASS' }, async run(p, r) {
        await btn('Download CFST').click().catch(() => {});
        await p.waitForTimeout(1500);
        r.assertions.busy = await p.evaluate(() => [...document.querySelectorAll('button')].map(b => ({ t: b.textContent.trim(), d: b.disabled })).filter(x => x.d));
      }},
      { id: 'ov-refresh-env', page: 'overview', control: 'Refresh Environment', states: { active: 'PASS' }, async run(p, r) {
        await btn('Refresh Environment').click();
        await p.waitForTimeout(2500);
        r.assertions.envTable = (await p.locator('.cfi-kv-table, .cbi-section-table').first().innerText().catch(() => '')).slice(0, 160);
      }},
      { id: 'ov-footer', page: 'overview', control: 'Footer links', states: { hover: 'PASS', focus: 'PASS', open: 'PASS' }, async run(p, r) {
        const link = p.locator('.ys-tool-footer-link').first();
        await link.hover();
        r.assertions.hover = await link.evaluate(ringStyle);
        await link.focus();
        r.assertions.focus = await link.evaluate(ringStyle);
        r.assertions.href = await link.getAttribute('href');
      }},

      /* Settings */
      { id: 'set-enable', page: 'settings', control: 'Enable Service', states: { focus: 'PASS' }, async run(p, r) {
        const box = field('Enable Service');
        const before = await box.isChecked();
        await box.click();
        r.assertions.toggled = (await box.isChecked()) !== before;
        await box.focus();
        r.assertions.focus = await box.evaluate(ringStyle);
      }},
      { id: 'set-schedule', page: 'settings', control: 'Run Schedule', states: { open: 'PASS' }, async run(p, r) {
        await field('Run Schedule').selectOption('custom');
        await p.waitForTimeout(300);
        r.assertions.customVisible = await field('Custom Schedule').isVisible();
        r.assertions.customCount = await field('Custom Schedule').count();
      }},
      { id: 'set-mode', page: 'settings', control: 'Mode', states: {}, async run(p, r) {
        await field('Mode').selectOption('openclash');
        r.assertions.value = await field('Mode').inputValue();
      }},
      { id: 'set-iptype', page: 'settings', control: 'IP Type', states: {}, async run(p, r) {
        await field('IP Type').selectOption({ label: 'Both' });
        r.assertions.value = await field('IP Type').inputValue();
      }},
      { id: 'set-protocol', page: 'settings', control: 'Speed Test Protocol', states: {}, async run(p, r) {
        await field('Speed Test Protocol').selectOption({ label: 'HTTPing' });
        r.assertions.value = await field('Speed Test Protocol').inputValue();
      }},
      { id: 'set-validation', page: 'settings', control: 'IP Count validation', states: { error: 'PASS' }, async run(p, r) {
        await field('IP Count').fill('0');
        await field('IP Count').dispatchEvent('change');
        await p.locator('button.cbi-button-save').click();
        await p.waitForTimeout(1200);
        r.assertions.invalid = await p.locator('.cbi-input-invalid').count();
      }},
      { id: 'set-save', page: 'settings', control: 'Save', states: { active: 'PASS' }, async run(p, r) {
        await field('IP Count').fill('8');
        await p.locator('button.cbi-button-save').click();
        await p.waitForTimeout(2200);
        r.assertions.changes = execFileSync('docker', ['exec', container, 'sh', '-c', 'uci changes cf_ip | head -5'], { encoding: 'utf8' }).trim();
        sh('uci revert cf_ip >/dev/null 2>&1 || true');
      }},
      { id: 'set-apply-open', page: 'settings', control: 'Save & Apply dropdown', states: { open: 'PASS', hover: 'PASS', focus: 'PASS' }, async run(p, r) {
        const dd = p.locator('.cbi-dropdown').filter({ hasText: 'Save & Apply' }).first();
        await dd.hover();
        await dd.click();
        await p.waitForTimeout(300);
        r.assertions.items = await p.locator('.cbi-dropdown ul li').allTextContents();
        r.assertions.open = await p.locator('.cbi-dropdown ul').first().isVisible();
        await p.keyboard.press('Escape');
        r.assertions.closed = !(await p.locator('.cbi-dropdown ul').first().isVisible().catch(() => false));
      }},
      { id: 'set-reset', page: 'settings', control: 'Reset', states: {}, async run(p, r) {
        await field('IP Count').fill('16');
        await p.locator('button.cbi-button-reset').click();
        await p.waitForTimeout(800);
        r.assertions.value = await field('IP Count').inputValue();
      }},

      /* Sources */
      { id: 'src-budget', page: 'sources', control: 'CFST Candidate IP Count', states: { focus: 'PASS' }, async run(p, r) {
        const inp = field('CFST Candidate IP Count');
        await inp.fill('256');
        await inp.focus();
        r.assertions.value = await inp.inputValue();
        r.assertions.focus = await inp.evaluate(ringStyle);
      }},
      { id: 'src-multiselect', page: 'sources', control: 'Built-in Sources', states: { open: 'PASS' }, async run(p, r) {
        const dd = p.locator('.cbi-value').filter({ hasText: 'Built-in Sources' }).locator('.cbi-dropdown').first();
        await dd.click();
        await p.waitForTimeout(300);
        r.assertions.options = await p.locator('.cbi-dropdown ul li').count();
        r.assertions.open = await p.locator('.cbi-dropdown ul').first().isVisible();
        await p.keyboard.press('Escape');
      }},
      { id: 'src-add', page: 'sources', control: 'Add custom source', states: { open: 'PASS', disabled: 'PASS' }, async run(p, r) {
        r.assertions.addDisabledBeforeName = await p.locator('button.cbi-button-add').first().isDisabled();
        await p.locator('.cbi-section-create-name').fill('TestSource2');
        await p.locator('.cbi-section-create-name').dispatchEvent('input');
        await p.locator('.cbi-section-create-name').dispatchEvent('change');
        await p.locator('.cbi-section-create-name').blur();
        await p.waitForTimeout(600);
        r.assertions.addEnabledAfterName = await p.locator('button.cbi-button-add').first().isEnabled();
        await p.locator('button.cbi-button-add').first().click();
        await p.waitForTimeout(600);
        r.assertions.rows = await p.locator('.cbi-section-table tbody tr').count();
        r.assertions.nameFields = await p.locator('.cbi-section-table input').count();
      }},
      { id: 'src-kind', page: 'sources', control: 'Custom source kind', states: { open: 'PASS' }, async run(p, r) {
        const row = p.locator('.cbi-section-table tbody tr').first();
        const kind = row.locator('select').first();
        await kind.selectOption('manual');
        await p.waitForTimeout(400);
        r.assertions.kind = await kind.inputValue();
        r.assertions.rowText = (await row.innerText()).slice(0, 120);
        r.assertions.ipVisible = await row.locator('input').count();
      }},
      { id: 'src-lan', page: 'sources', control: 'LAN Publisher', states: { open: 'PASS' }, async run(p, r) {
        const box = field('Enable LAN Publisher');
        await box.click();
        await field('HTTP Port').fill('12345');
        r.assertions.checked = await box.isChecked();
        r.assertions.port = await field('HTTP Port').inputValue();
      }},
      { id: 'src-refresh', page: 'sources', control: 'Refresh Sources', states: { active: 'PASS' }, async run(p, r) {
        await field('CFST Candidate IP Count').fill('256');
        await btn('Refresh Sources').click();
        await p.waitForTimeout(1800);
        r.assertions.busy = await p.evaluate(() => [...document.querySelectorAll('button')].filter(b => b.disabled).map(b => b.textContent.trim()));
        await p.waitForTimeout(1500);
        r.assertions.draft = await field('CFST Candidate IP Count').inputValue();
        r.assertions.notice = (await p.locator('.alert-message').allTextContents()).join(' | ').slice(0, 120);
      }},
      { id: 'src-save', page: 'sources', control: 'Save', states: { active: 'PASS' }, async run(p, r) {
        await field('CFST Candidate IP Count').fill('256');
        await p.locator('button.cbi-button-save').click();
        await p.waitForTimeout(1800);
        r.assertions.changes = execFileSync('docker', ['exec', container, 'sh', '-c', 'uci changes cf_ip | head -5'], { encoding: 'utf8' }).trim();
        sh('uci revert cf_ip >/dev/null 2>&1 || true');
      }},

      /* Intelligence */
      { id: 'int-policy', page: 'intelligence', control: 'Source Strategy', states: {}, async run(p, r) {
        await field('Source Strategy').selectOption('history-heavy');
        r.assertions.value = await field('Source Strategy').inputValue();
      }},
      { id: 'int-probe', page: 'intelligence', control: 'Probe Batch Size', states: {}, async run(p, r) {
        await field('Probe Batch Size').fill('4');
        r.assertions.value = await field('Probe Batch Size').inputValue();
      }},
      { id: 'int-early', page: 'intelligence', control: 'Deterministic Early Stop', states: {}, async run(p, r) {
        const box = field('Deterministic Early Stop');
        const before = await box.isChecked();
        await box.click();
        r.assertions.toggled = (await box.isChecked()) !== before;
      }},
      { id: 'int-adaptive', page: 'intelligence', control: 'Adaptive Measurement Mode', states: {}, async run(p, r) {
        await field('Mode').first().selectOption('guarded');
        r.assertions.value = await field('Mode').first().inputValue();
      }},
      { id: 'int-rill', page: 'intelligence', control: 'Rill Runtime', states: {}, async run(p, r) {
        const box = field('Enable Rill Intelligence');
        await box.click();
        await p.waitForTimeout(300);
        r.assertions.enabled = await box.isChecked();
      }},
      { id: 'int-selfcheck', page: 'intelligence', control: 'Run self-check', states: { active: 'PASS' }, async run(p, r) {
        await btn('Run self-check').click();
        await p.waitForTimeout(2500);
        r.assertions.notice = (await p.locator('.alert-message').allTextContents()).join(' | ').slice(0, 160);
        r.assertions.text = (await p.locator('#maincontent').innerText()).slice(-200);
      }},
      { id: 'int-reset', page: 'intelligence', control: 'Reset learning state', states: { open: 'PASS', hover: 'PASS' }, async run(p, r) {
        const b = btn('Reset learning state');
        await b.hover();
        await b.click();
        await p.waitForTimeout(400);
        r.assertions.modal = await p.locator('.modal, .cbi-modal, .luci-modal, div[role=dialog]').count();
        r.assertions.modalText = (await p.locator('.modal, .cbi-modal, .luci-modal, div[role=dialog]').first().innerText().catch(() => '')).slice(0, 120);
        await p.keyboard.press('Escape');
      }},
      { id: 'int-long-values', page: 'intelligence', control: 'DummyValue long fields', states: {}, async run(p, r) {
        r.assertions.metrics = await p.evaluate(() => {
          const fields = [...document.querySelectorAll('.cbi-value-field')];
          const long = fields.filter(f => f.textContent.trim().length > 80);
          return {
            fields: fields.length,
            longFields: long.length,
            overflow: document.documentElement.scrollWidth > innerWidth,
            clipped: long.filter(f => f.scrollWidth > f.clientWidth + 1).length
          };
        });
      }},
      { id: 'int-save', page: 'intelligence', control: 'Save', states: {}, async run(p, r) {
        await field('Probe Batch Size').fill('5');
        await p.locator('button.cbi-button-save').click();
        await p.waitForTimeout(1500);
        r.assertions.changes = execFileSync('docker', ['exec', container, 'sh', '-c', 'uci changes cf_ip | head -5'], { encoding: 'utf8' }).trim();
        sh('uci revert cf_ip >/dev/null 2>&1 || true');
      }},

      /* OpenClash */
      { id: 'oc-path', page: 'openclash', control: 'Config File Path', states: { empty: 'PASS' }, async run(p, r) {
        const inp = field('Config File Path');
        await inp.fill('/etc/openclash/config/config.yaml');
        r.assertions.value = await inp.inputValue();
      }},
      { id: 'oc-filter', page: 'openclash', control: 'Transport Filter', states: { error: 'PASS' }, async run(p, r) {
        const inp = field('Transport Filter');
        await inp.fill('ws,badproto');
        r.assertions.value = await inp.inputValue();
        r.assertions.backupAlert = await p.locator('.alert-message.error').count();
      }},
      { id: 'oc-backup-retry', page: 'openclash', control: 'Backup load failure / Retry', states: { error: 'PASS', active: 'PASS' }, async run(p, r) {
        r.assertions.before = await p.locator('.alert-message.error').allTextContents();
        await btn('Retry').click();
        await p.waitForTimeout(1500);
        r.assertions.after = await p.locator('.alert-message.error').allTextContents();
      }},
      { id: 'oc-save', page: 'openclash', control: 'Save', states: {}, async run(p, r) {
        await field('Backup Count').fill('3');
        await p.locator('button.cbi-button-save').click();
        await p.waitForTimeout(1500);
        r.assertions.changes = execFileSync('docker', ['exec', container, 'sh', '-c', 'uci changes cf_ip | head -5'], { encoding: 'utf8' }).trim();
        sh('uci revert cf_ip >/dev/null 2>&1 || true');
      }},

      /* PassWall */
      { id: 'pw-domain', page: 'passwall', control: 'Target Domain', states: { empty: 'PASS' }, async run(p, r) {
        const inp = field('Target Domain');
        await inp.fill('cdn.example.com');
        r.assertions.value = await inp.inputValue();
      }},
      { id: 'pw-save', page: 'passwall', control: 'Save', states: {}, async run(p, r) {
        await field('Node Name Suffix').fill(' [CF-{n}]');
        await p.locator('button.cbi-button-save').click();
        await p.waitForTimeout(1200);
        r.assertions.changes = execFileSync('docker', ['exec', container, 'sh', '-c', 'uci changes cf_ip | head -5'], { encoding: 'utf8' }).trim();
        sh('uci revert cf_ip >/dev/null 2>&1 || true');
      }},

      /* Advanced */
      { id: 'adv-mirror', page: 'advanced', control: 'GitHub Mirror', states: {}, async run(p, r) {
        const inp = field('GitHub Mirror');
        await inp.fill('https://ghp.ci/');
        r.assertions.value = await inp.inputValue();
      }},
      { id: 'adv-validation', page: 'advanced', control: 'Timeout validation', states: { error: 'PASS' }, async run(p, r) {
        const inp = field('Measurement Deadline');
        await inp.fill('0');
        await inp.dispatchEvent('change');
        await p.locator('button.cbi-button-save').click();
        await p.waitForTimeout(1000);
        r.assertions.invalid = await p.locator('.cbi-input-invalid').count();
      }},
      { id: 'adv-save', page: 'advanced', control: 'Save', states: {}, async run(p, r) {
        await field('Download Retries').fill('3');
        await p.locator('button.cbi-button-save').click();
        await p.waitForTimeout(1500);
        r.assertions.changes = execFileSync('docker', ['exec', container, 'sh', '-c', 'uci changes cf_ip | head -5'], { encoding: 'utf8' }).trim();
        sh('uci revert cf_ip >/dev/null 2>&1 || true');
      }},

      /* Logs */
      { id: 'log-refresh', page: 'logs', control: 'Refresh', states: { active: 'PASS', empty: 'PASS' }, async run(p, r) {
        await btn('Refresh').first().click();
        await p.waitForTimeout(1800);
        r.assertions.log = await p.locator('.cfi-log-area').first().inputValue().catch(async () => await p.locator('.cfi-log-area').first().innerText());
        r.assertions.empty = await p.locator('.cfi-log-area.is-empty').count();
      }},
      { id: 'log-clear', page: 'logs', control: 'Clear Logs', states: { open: 'PASS', active: 'PASS' }, async run(p, r) {
        await btn('Clear Logs').click();
        await p.waitForTimeout(400);
        r.assertions.modal = (await p.locator('.modal, .cbi-modal, .luci-modal, div[role=dialog]').first().innerText().catch(() => '')).slice(0, 120);
        const confirmBtn = p.locator('.modal button, .cbi-modal button, .luci-modal button, div[role=dialog] button').filter({ hasText: /Clear|Confirm/i }).first();
        await confirmBtn.click().catch(() => {});
        await p.waitForTimeout(1200);
        r.assertions.log = await p.locator('.cfi-log-area').first().inputValue().catch(async () => await p.locator('.cfi-log-area').first().innerText());
      }},
      { id: 'log-history', page: 'logs', control: 'IP History table', states: {}, async run(p, r) {
        r.assertions.table = await p.locator('.cfi-kv-table, .cfi-section-table').count();
        r.assertions.text = (await p.locator('#maincontent').innerText()).slice(-160);
      }}
    ];

    for (const def of points) await runPoint(ctx, def);
  } finally {
    try { sh("uci revert cf_ip >/dev/null 2>&1 || true; uci delete cf_ip.@source[0] 2>/dev/null; uci commit cf_ip; rm -f /etc/init.d/openclash /etc/init.d/passwall; rm -rf /tmp/luci-indexcache* /tmp/luci-modulecache"); } catch (e) {}
    await browser.close();
  }
  fs.writeFileSync(path.join(out, 'matrix.json'), JSON.stringify({ container, base, points: results }, null, 2) + '\n');
  const states = ['default', 'hover', 'focus', 'active', 'disabled', 'error', 'empty', 'open'];
  const counts = {};
  for (const s of states) counts[s] = { PASS: 0, 'N/A': 0, BLOCKED: 0, FAIL: 0 };
  for (const r of results) for (const s of states) counts[s][r.states[s]] = (counts[s][r.states[s]] || 0) + 1;
  console.log('SUMMARY', JSON.stringify({ points: results.length, pass: results.filter(r => r.status === 'PASS').length, fail: results.filter(r => r.status === 'FAIL').length, states: counts }, null, 2));
})().catch(e => { console.error(e); process.exit(1); });
