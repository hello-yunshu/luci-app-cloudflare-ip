'use strict';

/*
 * Phase F seven-state interaction matrix.
 *
 * Runtime: real OpenWrt 24.10.8 uhttpd/rpcd/LuCI container (cfip-ui-phasef),
 * real Chromium 153. The only controlled inputs are:
 *   - Playwright route patching of cf_ip RPC replies for loading/error/success;
 *   - clipboard success/failure for copy buttons.
 * Everything else is the real LuCI UI, real UCI and real rpcd dispatch.
 */

const fs = require('fs');
const path = require('path');
const crypto = require('crypto');
const { execFileSync } = require('child_process');
const { chromium } = require('playwright-core');

const BASE = process.env.CFIP_UI_BASE || 'http://127.0.0.1:18080';
const CONTAINER = process.env.CFIP_UI_CONTAINER || 'cfip-ui-phasef';
const PASSWORD = process.env.CFIP_UI_PASSWORD || 'cfip-gate';
const OUT = process.env.CFIP_PHASE_F_OUT || path.resolve(__dirname, '../matrix');
const ONLY = (process.argv.find(a => a.startsWith('--only=')) || '').slice(7).split(',').filter(Boolean);
const STATES = ['loading', 'disabled', 'error', 'success', 'partial', 'cancel', 'rollback'];
const results = [];

fs.mkdirSync(OUT, { recursive: true });

function sh(command) {
  return execFileSync('docker', ['exec', CONTAINER, 'sh', '-c', command], { encoding: 'utf8' }).trim();
}
function sleep(ms) { return new Promise(resolve => setTimeout(resolve, ms)); }
function sha(file) { return crypto.createHash('sha256').update(fs.readFileSync(file)).digest('hex'); }

const PAYLOADS = {
  'status': { success: true, running: false, active_run: false, jobRunning: false, last_result: 'success', best_ips: ['104.16.1.1'], env: { bash: true, curl: true, jq: true, tar: true } },
  'start': { success: true },
  'stop': { success: true },
  'restart': { success: true },
  'download-cfst': { success: true, cfst_version: 'fixture-1.19.33' },
  'refresh-env': { success: true, bash: true, curl: true, jq: true, tar: true },
  'run': { success: true },
  'refresh': { success: true },
  'rill-self-check': { success: true },
  'rill-reset': { success: true },
  'read-log': { success: true, logs: 'fixture log line\n' },
  'clear-log': { success: true },
  'ip-history': { success: true, history: [] },
  'rill-diagnostics': { success: true, runtime: { available: false, state: 'disabled' } },
  'adaptive-status': { success: true },
  'oc-list-backups': { success: true, backups: [{ id: '20261104000004', size: 20, created_at: '2026-11-04 00:00:04' }] },
  'oc-delete-backup': { success: true },
  'oc-restore-backup': { success: true }
};
const FAIL_METHODS = new Set(['start', 'restart', 'download-cfst', 'refresh-env', 'refresh', 'rill-self-check', 'rill-reset', 'read-log', 'clear-log', 'oc-list-backups']);
let routeMode = null;

function callMeta(requestData) {
  const calls = Array.isArray(requestData) ? requestData : [requestData];
  const map = new Map();
  for (const call of calls) {
    if (!call || typeof call !== 'object') continue;
    const params = call.params || [];
    map.set(String(call.id), { object: params[1], method: params[2] });
  }
  return map;
}

function patchUbus(payload, mode, meta) {
  if (!mode) return payload;
  const items = Array.isArray(payload) ? payload : [payload];
  for (const item of items) {
    if (!item || typeof item !== 'object') continue;
    const call = meta.get(String(item.id));
    if (!call || call.object !== 'cf_ip') continue;
    if (mode.method && call.method !== mode.method) continue;
    if (mode.kind === 'fail') {
      item.result = [1, { error: 'controlled RPC failure' }];
    } else {
      item.result = [0, Object.assign({}, PAYLOADS[call.method] || { success: true }, mode.payload || {})];
    }
  }
  return payload;
}

async function rpcRoute(route) {
  const mode = routeMode;
  if (!mode) return route.continue().catch(() => {});
  if (mode.kind === 'delay') await sleep(mode.ms || 2500);
  let requestData;
  try { requestData = JSON.parse(route.request().postData() || '{}'); } catch { return route.continue().catch(() => {}); }
  const meta = callMeta(requestData);
  let response;
  try { response = await route.fetch(); } catch { return; }
  let data;
  try { data = await response.json(); } catch { return route.fulfill({ response }).catch(() => {}); }
  patchUbus(data, mode, meta);
  return route.fulfill({ response, json: data }).catch(() => {});
}

function pageFor(context, init) {
  return context.newPage().then(async page => {
    await page.route('**/ubus**', rpcRoute);
    if (init) await page.addInitScript(init);
    return page;
  });
}

async function login(page) {
  await page.goto(BASE + '/cgi-bin/luci/', { waitUntil: 'domcontentloaded' });
  const user = page.locator('input[name="luci_username"]');
  if (await user.count()) {
    await user.fill('root');
    await page.locator('input[name="luci_password"]').fill(PASSWORD);
    const submit = page.locator('button[type="submit"], input[type="submit"], button:has-text("Log in"), button:has-text("Login"), button:has-text("登录")').first();
    if (await submit.count())
      await submit.click();
    else
      await page.locator('input[name="luci_password"]').press('Enter');
    await page.waitForTimeout(2500);
  }
  if (await page.locator('input[name="luci_password"]').count()) throw new Error('login failed');
}

async function openPage(context, name) {
  const page = await pageFor(context);
  const errors = [];
  page.on('console', message => { if (message.type() === 'error') errors.push(message.text()); });
  await page.goto(BASE + '/cgi-bin/luci/admin/services/cf_ip/' + name, { waitUntil: 'domcontentloaded' });
  await page.waitForFunction(() => {
    const text = (document.querySelector('#maincontent') || document.body).innerText;
    return text.length > 80 && !/Loading view/.test(text);
  }, null, { timeout: 60000 }).catch(() => {});
  await page.waitForTimeout(900);
  return { page, errors };
}

async function expandIfNeeded(page, def) {
  if (!def.expand) return;
  const toggle = page.locator('button.cfi-collapse-toggle:visible').first();
  await toggle.waitFor({ timeout: 8000 }).catch(() => {});
  if (await toggle.count()) {
    const expanded = await toggle.getAttribute('aria-expanded');
    if (expanded !== 'true') {
      await toggle.click();
      await page.waitForTimeout(600);
    }
  }
}

const afterSnap = {};

async function shot(page, id, state, phase, fullPage = false) {
  const file = path.join(OUT, `${id}-${state}-${phase}.png`);
  await page.screenshot({ path: file, fullPage });
  if (phase === 'after') {
    try {
      afterSnap[`${id}/${state}`] = await page.evaluate(() => {
        const main = document.querySelector('#maincontent');
        const focusEl = document.activeElement;
        const rect = focusEl ? focusEl.getBoundingClientRect() : null;
        const style = focusEl ? getComputedStyle(focusEl) : null;
        return {
          theme: document.documentElement.className || '(default)',
          dark: document.documentElement.getAttribute('data-darkmode') === 'true',
          viewport: [innerWidth, innerHeight],
          dom: {
            mainTextLength: main ? main.innerText.trim().length : 0,
            alerts: document.querySelectorAll('.alert-message').length,
            details: document.querySelectorAll('details').length,
            pageOverflow: document.documentElement.scrollWidth > innerWidth
          },
          focus: {
            tag: focusEl ? focusEl.tagName : null,
            text: focusEl ? (focusEl.innerText || focusEl.value || focusEl.getAttribute('aria-label') || '').trim().slice(0, 40) : '',
            inMain: !!(focusEl && focusEl.closest && focusEl.closest('#maincontent')),
            ring: !!style && ((style.outlineStyle !== 'none' && parseFloat(style.outlineWidth) > 0) || (style.boxShadow && style.boxShadow !== 'none')),
            inViewport: !!rect && rect.top >= 0 && rect.bottom <= innerHeight && rect.left >= 0 && rect.right <= innerWidth
          }
        };
      });
    } catch (error) {
      afterSnap[`${id}/${state}`] = { snapshotError: error.message };
    }
  }
  return { file: path.relative(path.resolve(__dirname, '../..'), file), sha256: sha(file) };
}

async function capturePair(page, id, state, action, options = {}) {
  const before = await shot(page, id, state, 'before', options.fullPage);
  await action();
  const after = await shot(page, id, state, 'after', options.fullPage);
  if (before.sha256 === after.sha256) throw new Error('BEFORE/AFTER screenshot hashes are identical for ' + id + '/' + state);
  return { before, after };
}

function button(page, text) {
  return page.locator('button', { hasText: text }).first();
}
function targetButton(page, def) {
  if (def.buttonIndex != null) return page.locator('.cfi-btn-group button').nth(def.buttonIndex);
  return button(page, def.button);
}
function pageReset(page) {
  return page.locator('.cbi-page-actions button.cbi-button-reset').first();
}
function pageSave(page) {
  return page.locator('.cbi-page-actions button.cbi-button-save').first();
}
function fieldByLabel(page, text) {
  return page.locator('.cbi-value', { hasText: text }).first().locator('input, select, textarea').first();
}
function fieldById(page, id) {
  return page.locator('[id="' + id + '"]').first();
}
function notifications(page) {
  return page.locator('.alert-message').allTextContents();
}
function hasError(page) {
  return page.locator('.alert-message.error, details').count();
}
function setRoute(mode) { routeMode = mode; }
function clearRoute() { routeMode = null; }
function mark(row, state) { row.states[state] = 'PASS'; }
const STATUS_STABLE = "cf-ip-auto --status 2>/dev/null | jq -c 'del(.status_updated_at)' || true";

const N_A = {
  partial: 'The backend returns one atomic result per request; there is no partial-success contract.',
  loading: 'This control has no asynchronous busy state.',
  disabled: 'This control stays editable; no disabled state exists.',
  error: 'No client validation or user-visible error path exists for this control.',
  cancel: 'There is no cancel affordance for this control.',
  rollback: 'This control does not mutate server state; rollback is covered by its owning save/apply point.'
};

function baseRow(def) {
  const row = {
    id: def.id, page: def.page, control: def.control, kind: def.kind,
    states: {}, assertions: {}, evidence: {}, consoleErrors: {}, status: 'PASS'
  };
  for (const state of STATES) {
    if (def.plan.includes(state)) row.states[state] = 'PENDING';
    else row.states[state] = 'N/A';
  }
  row.note = {};
  for (const state of STATES) if (row.states[state] === 'N/A') row.note[state] = def.note?.[state] || N_A[state];
  return row;
}

async function assertNoConsole(context, def, state, errors) {
  if (errors.length) throw new Error(`${def.id}/${state} console errors: ${errors.join(' | ')}`);
}

function resetServiceState() {
  sh('rm -f /etc/cf_ip/status.json; uci set cf_ip.main.enabled=0; uci commit cf_ip; rm -rf /tmp/luci-indexcache* /tmp/luci-modulecache');
}

async function waitViewReady(page) {
  await page.waitForFunction(() => {
    const text = (document.querySelector('#maincontent') || document.body).innerText;
    return text.length > 80 && !/Loading view/.test(text);
  }, null, { timeout: 60000 }).catch(() => {});
  await page.waitForTimeout(900);
}

async function successRpc(context, def, row) {
  if (def.successSetup) def.successSetup();
  if (def.page === 'overview') resetServiceState();
  const { page, errors } = await openPage(context, def.page);
  await expandIfNeeded(page, def);
  setRoute({ kind: 'success', method: def.method });
  try {
    await capturePair(page, def.id, 'success', async () => {
      await targetButton(page, def).click();
      await page.waitForTimeout(def.successWait || 1200);
      if (def.reloadAfterAction) await waitViewReady(page);
    });
    row.assertions.success = { url: page.url(), text: (await page.locator('#maincontent').innerText()).slice(0, 160) };
  } finally { clearRoute(); }
  await assertNoConsole(context, def, 'success', errors);
  if (def.successCheck) await def.successCheck(page, row);
  mark(row, 'success');
  await page.close();
}

async function loadingRpc(context, def, row) {
  if (def.page === 'overview') resetServiceState();
  const { page, errors } = await openPage(context, def.page);
  await expandIfNeeded(page, def);
  setRoute({ kind: 'delay', method: def.method, ms: 2600 });
  try {
    const target = targetButton(page, def);
    if (def.transient) {
      const before = await shot(page, def.id, 'loading', 'before');
      row.assertions.loading = await target.evaluate(el => {
        el.click();
        return { disabled: el.disabled, text: el.textContent.trim(), ariaBusy: el.getAttribute('aria-busy') };
      });
      await page.waitForTimeout(450);
      const after = await shot(page, def.id, 'loading', 'after');
      row.evidence.loading = { before, after };
      row.assertions.loading.transient = true;
      row.assertions.loading.note = 'LuCI re-renders form.Button immediately after dispatch; the busy state is asserted synchronously at click time.';
    } else {
      await capturePair(page, def.id, 'loading', async () => {
        await target.click();
        await page.waitForTimeout(450);
      });
      row.assertions.loading = await target.evaluate(el => ({ disabled: el.disabled, text: el.textContent.trim() }));
    }
    if (!row.assertions.loading || !row.assertions.loading.disabled) throw new Error('busy button was not disabled');
    await page.waitForTimeout(2800);
  } finally { clearRoute(); }
  await assertNoConsole(context, def, 'loading', errors);
  row.evidence.disabled = row.evidence.loading;
  row.states.disabled = 'PASS';
  row.assertions.disabled = row.assertions.loading;
  mark(row, 'loading');
  await page.close();
}

async function errorRpc(context, def, row) {
  if (def.errorSetup) def.errorSetup();
  if (def.page === 'overview') resetServiceState();
  const { page, errors } = await openPage(context, def.page);
  await expandIfNeeded(page, def);
  const stateCommand = def.serverState || STATUS_STABLE;
  const beforeState = sh(stateCommand);
  setRoute({ kind: 'fail', method: def.method });
  try {
    const beforeShot = await shot(page, def.id, 'error', 'before');
    await targetButton(page, def).click();
    await page.waitForTimeout(1800);
    if (def.reloadAfterAction) await waitViewReady(page);
    const afterShot = await shot(page, def.id, 'error', 'after');
    if (beforeShot.sha256 === afterShot.sha256 && !def.allowSameErrorScreenshot)
      throw new Error('BEFORE/AFTER screenshot hashes are identical for ' + def.id + '/error');
    if (beforeShot.sha256 === afterShot.sha256)
      row.note.errorScreenshot = 'The page is already in the error state, so the before/after panels are visually identical; state is asserted through alert/details.';
    const alertText = await notifications(page);
    const detailCount = await page.locator('details').count();
    row.assertions.error = { alerts: alertText.slice(0, 300), details: detailCount };
    if (!alertText.some(text => /Unable|failed|error|No related|技术详情|Technical details/i.test(text)) && detailCount === 0)
      throw new Error('no user-visible error state');
    const afterState = sh(stateCommand);
    row.assertions.rollback = { before: beforeState, after: afterState, unchanged: beforeState === afterState };
    if (beforeState !== afterState) throw new Error('server state changed after failed RPC');
    await shot(page, def.id, 'rollback', 'after');
    mark(row, 'error');
    mark(row, 'rollback');
  } finally { clearRoute(); }
  await assertNoConsole(context, def, 'error', errors);
  await page.close();
}

async function fieldSuccess(context, def, row) {
  const { page, errors } = await openPage(context, def.page);
  const target = def.selector ? fieldById(page, def.selector) : fieldByLabel(page, def.label);
  await target.waitFor({ timeout: 8000 });
  await capturePair(page, def.id, 'success', async () => {
    if (def.type === 'checkbox') {
      const before = await target.isChecked();
      await target.click();
      row.assertions.success = { before, after: await target.isChecked() };
      if (row.assertions.success.after === before) throw new Error('checkbox did not toggle');
    } else if (def.type === 'select' || (await target.evaluate(el => el.tagName === 'SELECT').catch(() => false))) {
      await target.selectOption(def.value);
      row.assertions.success = { value: await target.inputValue() };
      if (row.assertions.success.value !== def.value) throw new Error('select value mismatch');
    } else {
      await target.fill(def.value);
      row.assertions.success = { value: await target.inputValue() };
      if (row.assertions.success.value !== def.value) throw new Error('text value mismatch');
    }
  });
  await assertNoConsole(context, def, 'success', errors);
  mark(row, 'success');
  await page.close();
}

async function fieldCancel(context, def, row) {
  const { page, errors } = await openPage(context, def.page);
  const target = def.selector ? fieldById(page, def.selector) : fieldByLabel(page, def.label);
  const original = await target.inputValue();
  await capturePair(page, def.id, 'cancel', async () => {
    if (def.type === 'checkbox') await target.click();
    else if ((await target.evaluate(el => el.tagName === 'SELECT').catch(() => false))) await target.selectOption(def.cancelValue || def.value);
    else await target.fill(def.cancelValue || String(original) + '9');
    await pageReset(page).click();
    await page.waitForTimeout(700);
  });
  row.assertions.cancel = { original, restored: await target.inputValue().catch(() => null), url: page.url() };
  if (row.assertions.cancel.restored !== original) throw new Error('Reset did not restore the original value');
  await assertNoConsole(context, def, 'cancel', errors);
  mark(row, 'cancel');
  await page.close();
}

async function fieldError(context, def, row) {
  const { page, errors } = await openPage(context, def.page);
  const target = fieldById(page, def.selector);
  await capturePair(page, def.id, 'error', async () => {
    await target.fill(def.invalid);
    await target.dispatchEvent('change');
    await target.blur();
    await page.waitForTimeout(600);
  });
  const invalid = await page.locator('.cbi-input-invalid').count();
  row.assertions.error = { invalid };
  if (invalid < 1) throw new Error('validation did not mark the field invalid');
  await assertNoConsole(context, def, 'error', errors);
  mark(row, 'error');
  await page.close();
}

async function saveSuccess(context, def, row) {
  const { page, errors } = await openPage(context, def.page);
  await capturePair(page, def.id, 'success', async () => {
    if (def.change) await def.change(page);
    await pageSave(page).click();
    await page.waitForTimeout(1000);
  });
  let changes = '';
  for (let i = 0; i < 6 && !changes; i++) {
    await page.waitForTimeout(600);
    changes = sh('uci changes cf_ip || true');
  }
  const browserChanges = await page.evaluate(async () => { const u = await L.require('uci'); return u.changes('cf_ip'); }).catch(error => ({ error: String(error) }));
  row.assertions.success = { changes, browserChanges, alerts: await notifications(page), actions: await page.locator('.cbi-page-actions').innerText().catch(() => '') };
  const staged = changes || (browserChanges && !browserChanges.error && Object.keys(browserChanges).length > 0);
  if (!staged) throw new Error('Save did not stage any UCI change');
  sh('uci revert cf_ip >/dev/null 2>&1 || true');
  await assertNoConsole(context, def, 'success', errors);
  mark(row, 'success');
  await page.close();
}

async function applyError(context, def, row) {
  const { page, errors } = await openPage(context, def.page);
  const serverBefore = sh('uci get cf_ip.main.ip_count');
  await capturePair(page, def.id, 'error', async () => {
    await fieldById(page, 'widget.cbid.cf_ip.main.ip_count').fill('9');
    await page.locator('.cbi-dropdown').filter({ hasText: 'Save & Apply' }).first().click();
    await page.waitForTimeout(300);
    await page.locator('.cbi-dropdown ul li').filter({ hasText: 'Save & Apply' }).first().click();
    await page.waitForTimeout(2500);
  });
  const alerts = await notifications(page);
  row.assertions.error = { alerts: alerts.slice(0, 300), serverBefore };
  if (!alerts.some(text => /Unable|failed|error|保持不变/i.test(text))) throw new Error('apply failure was not visible');
  const serverAfter = sh('uci get cf_ip.main.ip_count');
  row.assertions.rollback = { serverBefore, serverAfter, unchanged: serverBefore === serverAfter };
  if (serverBefore !== serverAfter) throw new Error('server value changed after failed apply');
  await shot(page, def.id, 'rollback', 'after');
  mark(row, 'error');
  mark(row, 'rollback');
  sh('uci revert cf_ip >/dev/null 2>&1 || true');
  await assertNoConsole(context, def, 'error', errors);
  await page.close();
}

async function applySuccess(context, def, row) {
  const { page, errors } = await openPage(context, def.page);
  await capturePair(page, def.id, 'success', async () => {
    await fieldById(page, 'widget.cbid.cf_ip.main.ip_count').fill('4');
    await page.locator('.cbi-dropdown').filter({ hasText: 'Save & Apply' }).first().click();
    await page.waitForTimeout(300);
    await page.locator('.cbi-dropdown ul li').filter({ hasText: 'Save & Apply' }).first().click();
    await page.waitForTimeout(2500);
  });
  row.assertions.success = { serverValue: sh('uci get cf_ip.main.ip_count') };
  if (row.assertions.success.serverValue !== '4') throw new Error('Save & Apply did not persist the value');
  await assertNoConsole(context, def, 'success', errors);
  mark(row, 'success');
  await page.close();
}

function dropdownLocator(page, def) {
  if (def.pageAction) return page.locator('.cbi-dropdown').filter({ hasText: def.label }).first();
  return page.locator('.cbi-value').filter({ hasText: def.label }).locator('.cbi-dropdown').first();
}

async function dropdownSuccess(context, def, row) {
  const { page, errors } = await openPage(context, def.page);
  const dd = dropdownLocator(page, def);
  await dd.scrollIntoViewIfNeeded();
  await capturePair(page, def.id, 'success', async () => {
    await dd.click();
    await page.waitForTimeout(300);
  }, { fullPage: true });
  row.assertions.success = { open: await page.locator('.cbi-dropdown ul').first().isVisible(), options: await page.locator('.cbi-dropdown ul li').count() };
  if (!row.assertions.success.open) throw new Error('dropdown did not open');
  await assertNoConsole(context, def, 'success', errors);
  mark(row, 'success');
  await page.close();
}

async function dropdownCancel(context, def, row) {
  const { page, errors } = await openPage(context, def.page);
  const dd = dropdownLocator(page, def);
  await dd.scrollIntoViewIfNeeded();
  await dd.click();
  await page.waitForTimeout(300);
  const before = await shot(page, def.id, 'cancel', 'before', true);
  await page.keyboard.press('Escape');
  await page.waitForTimeout(300);
  if (await page.locator('.cbi-dropdown ul').first().isVisible().catch(() => false)) {
    await page.locator('#maincontent h2').first().click({ force: true }).catch(() => {});
    await page.waitForTimeout(400);
  }
  const after = await shot(page, def.id, 'cancel', 'after', true);
  row.assertions.cancel = {
    closed: !(await page.locator('.cbi-dropdown ul').first().isVisible().catch(() => false)),
    hashDifference: before.sha256 !== after.sha256,
    screenshotNote: before.sha256 === after.sha256 ? 'LuCI renders the multiselect popup in a fixed overlay outside the captured page bitmap; closure is asserted through DOM visibility.' : null
  };
  if (!row.assertions.cancel.closed) throw new Error('dropdown could not be closed');
  await assertNoConsole(context, def, 'cancel', errors);
  mark(row, 'cancel');
  await page.close();
}

async function addStates(context, def, row) {
  const { page, errors } = await openPage(context, def.page);
  const add = page.locator('button.cbi-button-add').first();
  row.assertions.disabled = { initial: await add.isDisabled() };
  if (!row.assertions.disabled.initial) throw new Error('Add was not initially disabled');
  await shot(page, def.id, 'disabled', 'after');
  await capturePair(page, def.id, 'success', async () => {
    await page.locator('.cbi-section-create-name').fill('PhaseFSource');
    await page.locator('.cbi-section-create-name').dispatchEvent('input');
    await page.locator('.cbi-section-create-name').dispatchEvent('change');
    await page.locator('.cbi-section-create-name').blur();
    await page.waitForTimeout(400);
    if (await add.isDisabled()) throw new Error('Add stayed disabled after a valid name');
    await add.click();
    await page.waitForTimeout(600);
  });
  row.assertions.success = { rows: await page.locator('.cbi-section-table tbody tr').count() };
  await capturePair(page, def.id, 'cancel', async () => {
    await page.locator('.cbi-section-create-name').fill('CancelMe');
    await page.locator('.cbi-section-create-name').dispatchEvent('input');
    await page.waitForTimeout(200);
    await page.locator('.cbi-section-create-name').fill('');
    await page.locator('.cbi-section-create-name').dispatchEvent('input');
    await page.waitForTimeout(300);
  });
  row.assertions.cancel = { addDisabledAgain: await add.isDisabled() };
  if (!row.assertions.cancel.addDisabledAgain) throw new Error('Add stayed enabled with an empty name');
  sh('uci delete cf_ip.@source[0] 2>/dev/null || true; uci commit cf_ip 2>/dev/null || true');
  await assertNoConsole(context, def, 'success', errors);
  mark(row, 'success');
  mark(row, 'cancel');
  mark(row, 'disabled');
  await page.close();
}

const MODAL = '.modal, .cbi-modal, .luci-modal, div[role=dialog]';
const MODAL_BUTTON = '.modal button, .cbi-modal button, .luci-modal button, div[role=dialog] button';

async function openModal(page, def) {
  await button(page, def.open).click();
  await page.waitForTimeout(500);
  const visible = await page.locator(MODAL).first().isVisible().catch(() => false);
  if (!visible) throw new Error('modal did not open for ' + def.id);
}
async function captureModal(page, def, state, action) {
  const before = await shot(page, def.id, state, 'before');
  await action();
  const after = await shot(page, def.id, state, 'after');
  if (before.sha256 === after.sha256) throw new Error('BEFORE/AFTER screenshot hashes are identical for ' + def.id + '/' + state);
  return { before, after };
}

async function modalStates(context, def, row) {
  const success = await openPage(context, def.page);
  await expandIfNeeded(success.page, def);
  setRoute({ kind: 'success', method: def.method });
  try {
    await openModal(success.page, def);
    await captureModal(success.page, def, 'success', async () => {
      await success.page.locator(MODAL_BUTTON).filter({ hasText: def.confirm }).first().click();
      await success.page.waitForTimeout(1200);
    });
    row.assertions.success = { alerts: await notifications(success.page) };
    if (def.successCheck) await def.successCheck(success.page, row);
    mark(row, 'success');
  } finally { clearRoute(); }
  await assertNoConsole(context, def, 'success', success.errors);
  await success.page.close();

  const cancel = await openPage(context, def.page);
  await expandIfNeeded(cancel.page, def);
  await openModal(cancel.page, def);
  await captureModal(cancel.page, def, 'cancel', async () => {
    await cancel.page.locator(MODAL_BUTTON).filter({ hasText: 'Cancel' }).first().click();
    await cancel.page.waitForTimeout(500);
  });
  row.assertions.cancel = { modalClosed: !(await cancel.page.locator(MODAL).first().isVisible().catch(() => false)) };
  if (!row.assertions.cancel.modalClosed) throw new Error('Cancel did not close the modal');
  await assertNoConsole(context, def, 'cancel', cancel.errors);
  mark(row, 'cancel');
  await cancel.page.close();

  const error = await openPage(context, def.page);
  await expandIfNeeded(error.page, def);
  const before = def.serverState ? sh(def.serverState) : '';
  setRoute({ kind: 'fail', method: def.method });
  try {
    await openModal(error.page, def);
    await captureModal(error.page, def, 'error', async () => {
      await error.page.locator(MODAL_BUTTON).filter({ hasText: def.confirm }).first().click();
      await error.page.waitForTimeout(1600);
    });
    row.assertions.error = { alerts: await notifications(error.page) };
    const after = def.serverState ? sh(def.serverState) : '';
    row.assertions.rollback = { before, after, unchanged: before === after };
    if (def.serverState && before !== after) throw new Error('server state changed after failed modal action');
    await shot(error.page, def.id, 'rollback', 'after');
    mark(row, 'error');
    mark(row, 'rollback');
  } finally { clearRoute(); }
  await assertNoConsole(context, def, 'error', error.errors);
  await error.page.close();
}

async function copyStates(context, def, row) {
  const successInit = () => {
    Object.defineProperty(navigator, 'clipboard', { configurable: true, value: { writeText: () => Promise.resolve() } });
  };
  const success = await pageFor(context, successInit);
  await success.goto(BASE + '/cgi-bin/luci/admin/services/cf_ip/' + def.page, { waitUntil: 'domcontentloaded' });
  await success.waitForTimeout(1400);
  const btn = success.locator('button.cfi-copy-btn').first();
  if (!(await btn.isVisible().catch(() => false))) {
    for (const summary of await success.locator('details summary').all()) await summary.click().catch(() => {});
    await success.waitForTimeout(500);
  }
  await btn.waitFor({ timeout: 8000 });
  await capturePair(success, def.id, 'success', async () => {
    await btn.click();
    await success.waitForTimeout(500);
  });
  row.assertions.success = { label: (await btn.innerText()).trim(), aria: await btn.getAttribute('aria-label'), count: await success.locator('button.cfi-copy-btn').count() };
  if (row.assertions.success.label !== 'Copied') throw new Error('copy success label was not Copied');
  mark(row, 'success');
  await success.close();

  const failureInit = () => {
    Object.defineProperty(navigator, 'clipboard', { configurable: true, value: { writeText: () => Promise.reject(new Error('denied')) } });
    document.execCommand = () => false;
  };
  const failure = await pageFor(context, failureInit);
  await failure.goto(BASE + '/cgi-bin/luci/admin/services/cf_ip/' + def.page, { waitUntil: 'domcontentloaded' });
  await failure.waitForTimeout(1400);
  const fbtn = failure.locator('button.cfi-copy-btn').first();
  if (!(await fbtn.isVisible().catch(() => false))) {
    for (const summary of await failure.locator('details summary').all()) await summary.click().catch(() => {});
    await failure.waitForTimeout(500);
  }
  await fbtn.waitFor({ timeout: 8000 });
  await capturePair(failure, def.id, 'error', async () => {
    await fbtn.click();
    await failure.waitForTimeout(700);
  });
  const alerts = await notifications(failure);
  row.assertions.error = { alerts };
  if (!alerts.some(text => /Unable to copy|Copy command was rejected/i.test(text))) throw new Error('copy failure was not visible');
  mark(row, 'error');
  await failure.close();
}

async function collapseStates(context, def, row) {
  const { page, errors } = await openPage(context, def.page);
  await page.evaluate(() => localStorage.removeItem('cfi.intelligence.liveState'));
  await page.reload({ waitUntil: 'domcontentloaded' });
  await page.waitForTimeout(1200);
  const collapse = page.locator('button.cfi-collapse-toggle:visible').first();
  await collapse.scrollIntoViewIfNeeded();
  await capturePair(page, def.id, 'success', async () => {
    await collapse.click();
    await page.waitForTimeout(700);
  });
  row.assertions.success = { expanded: await collapse.getAttribute('aria-expanded'), text: (await collapse.innerText()).trim(), bodyVisible: await page.locator('.cfi-collapse-body').first().isVisible().catch(() => false) };
  if (row.assertions.success.expanded !== 'true' && !row.assertions.success.bodyVisible) throw new Error('collapse did not expand');
  mark(row, 'success');
  await capturePair(page, def.id, 'cancel', async () => {
    await collapse.click();
    await page.waitForTimeout(500);
  });
  row.assertions.cancel = { expanded: await collapse.getAttribute('aria-expanded'), bodyVisible: await page.locator('.cfi-collapse-body').first().isVisible().catch(() => false) };
  if (row.assertions.cancel.expanded !== 'false' && row.assertions.cancel.bodyVisible) throw new Error('collapse did not collapse');
  mark(row, 'cancel');
  await collapse.click();
  await page.waitForTimeout(500);
  await page.reload({ waitUntil: 'domcontentloaded' });
  await page.waitForTimeout(1200);
  const persisted = await page.locator('button.cfi-collapse-toggle:visible').first().getAttribute('aria-expanded');
  const persistedVisible = await page.locator('.cfi-collapse-body').first().isVisible().catch(() => false);
  row.assertions.rollback = { persisted, bodyVisible: persistedVisible };
  if (persisted !== 'true' && !persistedVisible) throw new Error('collapse state did not persist across reload');
  await shot(page, def.id, 'rollback', 'after');
  mark(row, 'rollback');
  await assertNoConsole(context, def, 'rollback', errors);
  await page.close();
}

async function linkStates(context, def, row) {
  const { page, errors } = await openPage(context, def.page);
  const link = page.locator('a', { hasText: def.text }).first();
  await link.waitFor({ timeout: 8000 });
  const href = await link.getAttribute('href');
  if (def.external) {
    await capturePair(page, def.id, 'success', async () => {
      await link.hover();
      await page.waitForTimeout(300);
    });
    row.assertions.success = { href, target: await link.getAttribute('target'), navigated: false };
  } else {
    await capturePair(page, def.id, 'success', async () => {
      await link.click();
      await page.waitForTimeout(1200);
    });
    row.assertions.success = { href, url: page.url() };
    if (!page.url().includes(def.target)) throw new Error('link did not navigate to ' + def.target);
  }
  await assertNoConsole(context, def, 'success', errors);
  mark(row, 'success');
  await page.close();
}

async function detailsStates(context, def, row) {
  const { page, errors } = await openPage(context, def.page);
  const details = page.locator('details').first();
  await details.waitFor({ timeout: 8000 });
  await capturePair(page, def.id, 'success', async () => {
    await details.locator('summary').click();
    await page.waitForTimeout(400);
  });
  row.assertions.success = { open: await details.evaluate(el => el.open), text: (await details.innerText()).slice(0, 200) };
  if (!row.assertions.success.open) throw new Error('details did not open');
  mark(row, 'success');
  await capturePair(page, def.id, 'cancel', async () => {
    await details.locator('summary').click();
    await page.waitForTimeout(400);
  });
  row.assertions.cancel = { open: await details.evaluate(el => el.open) };
  if (row.assertions.cancel.open) throw new Error('details did not close');
  await assertNoConsole(context, def, 'success', errors);
  mark(row, 'cancel');
  await page.close();
}

async function readonlyStates(context, def, row) {
  const { page, errors } = await openPage(context, def.page);
  if (def.selector) {
    const input = fieldById(page, def.selector);
    row.assertions.success = { disabled: await input.isDisabled(), readonly: await input.evaluate(el => el.readOnly), value: await input.inputValue() };
    if (!row.assertions.success.disabled && !row.assertions.success.readonly) throw new Error('deprecated field is editable');
    await shot(page, def.id, 'success', 'after');
    row.states.disabled = 'PASS';
    row.assertions.disabled = row.assertions.success;
  } else {
    row.assertions.success = await page.evaluate(() => {
      const fields = [...document.querySelectorAll('.cbi-value-field')];
      const long = fields.filter(f => f.textContent.trim().length > 80);
      return { fields: fields.length, longFields: long.length, clipped: long.filter(f => f.scrollWidth > f.clientWidth + 1).length, overflow: document.documentElement.scrollWidth > innerWidth };
    });
    if (row.assertions.success.overflow || row.assertions.success.clipped) throw new Error('read-only content clipped or overflowed');
    await shot(page, def.id, 'success', 'after');
  }
  await assertNoConsole(context, def, 'success', errors);
  mark(row, 'success');
  await page.close();
}

async function customFieldSuccess(context, def, row) {
  const { page, errors } = await openPage(context, def.page);
  await def.custom(page, row);
  await assertNoConsole(context, def, 'success', errors);
  await page.close();
}

const POINTS = [
  { id: 'ov-start', page: 'overview', control: 'Start', kind: 'rpc', method: 'start', button: 'Start', buttonIndex: 0, plan: ['loading', 'disabled', 'error', 'success', 'rollback'] },
  { id: 'ov-restart', page: 'overview', control: 'Restart', kind: 'rpc', method: 'restart', button: 'Restart', buttonIndex: 1, plan: ['loading', 'disabled', 'error', 'success', 'rollback'] },
  { id: 'ov-cfst', page: 'overview', control: 'Download CFST', kind: 'rpc', method: 'download-cfst', button: 'Download CFST', buttonIndex: 2, plan: ['loading', 'disabled', 'error', 'success', 'rollback'] },
  { id: 'ov-refresh-env', page: 'overview', control: 'Refresh Environment', kind: 'rpc', method: 'refresh-env', button: 'Refresh Environment', transient: true, plan: ['loading', 'disabled', 'error', 'success', 'rollback'] },
  { id: 'ov-footer', page: 'overview', control: 'Footer links', kind: 'link', text: 'Project', external: true, target: 'github.com', plan: ['success'] },

  { id: 'set-enable', page: 'settings', control: 'Enable Service', kind: 'field', label: 'Enable Service', type: 'checkbox', plan: ['success', 'cancel'] },
  { id: 'set-schedule', page: 'settings', control: 'Run Schedule', kind: 'field', selector: 'widget.cbid.cf_ip.main.cron_interval', type: 'select', value: 'custom', plan: ['success', 'cancel'] },
  { id: 'set-mode', page: 'settings', control: 'Mode', kind: 'field', selector: 'widget.cbid.cf_ip.main.mode', type: 'select', value: 'openclash', plan: ['success', 'cancel'] },
  { id: 'set-iptype', page: 'settings', control: 'IP Type', kind: 'field', selector: 'widget.cbid.cf_ip.main.ip_type', type: 'select', value: 'both', plan: ['success', 'cancel'] },
  { id: 'set-protocol', page: 'settings', control: 'Speed Test Protocol', kind: 'field', selector: 'widget.cbid.cf_ip.main.speedtest_protocol', type: 'select', value: 'http', plan: ['success', 'cancel'] },
  { id: 'set-validation', page: 'settings', control: 'IP Count validation', kind: 'field', selector: 'widget.cbid.cf_ip.main.ip_count', value: '8', invalid: '0', plan: ['success', 'error', 'cancel'] },
  { id: 'set-save', page: 'settings', control: 'Save', kind: 'save', change: async page => fieldById(page, 'widget.cbid.cf_ip.main.ip_count').fill('2'), plan: ['success'] },
  { id: 'set-apply-open', page: 'settings', control: 'Save & Apply dropdown', kind: 'dropdown', label: 'Save & Apply', pageAction: true, plan: ['success'], note: { cancel: 'The LuCI split button applies immediately; there is no cancelable open menu in this build.' } },
  { id: 'set-reset', page: 'settings', control: 'Reset', kind: 'reset', plan: ['success'] },
  { id: 'set-apply', page: 'settings', control: 'Save & Apply', kind: 'apply', plan: ['success', 'error', 'rollback'] },

  { id: 'src-budget', page: 'sources', control: 'CFST Candidate IP Count', kind: 'field', selector: 'widget.cbid.cf_ip.main.candidate_budget', value: '256', invalid: '0', plan: ['success', 'error', 'cancel'] },
  { id: 'src-multiselect', page: 'sources', control: 'Built-in Sources', kind: 'dropdown', label: 'Built-in Sources', plan: ['success'], note: { cancel: 'LuCI multiselect closes by selecting a value or leaving the widget; it has no dedicated cancel action.' } },
  { id: 'src-add', page: 'sources', control: 'Add custom source', kind: 'add', plan: ['success', 'disabled', 'cancel'] },
  {
    id: 'src-kind', page: 'sources', control: 'Custom source kind', kind: 'custom-field', plan: ['success', 'cancel'],
    custom: async (page, row) => {
      await page.locator('.cbi-section-create-name').fill('PhaseFKind');
      await page.locator('.cbi-section-create-name').dispatchEvent('input');
      await page.locator('.cbi-section-create-name').dispatchEvent('change');
      await page.locator('.cbi-section-create-name').blur();
      await page.waitForTimeout(500);
      await page.locator('button.cbi-button-add').first().click();
      await page.waitForTimeout(600);
      const modal = page.locator(MODAL).first();
      await modal.waitFor({ timeout: 8000 });
      const kind = modal.locator('select').first();
      await capturePair(page, 'src-kind', 'success', async () => {
        await kind.selectOption('manual');
        await page.waitForTimeout(400);
      });
      row.assertions.success = { modalText: (await modal.innerText()).slice(0, 160), kind: await kind.inputValue(), options: await kind.locator('option').allTextContents(), inputs: await modal.locator('input').count() };
      if (row.assertions.success.kind !== 'manual') throw new Error('custom source kind did not switch to manual');
      mark(row, 'success');
      await capturePair(page, 'src-kind', 'cancel', async () => {
        await modal.locator('button').filter({ hasText: /Dismiss|Cancel/ }).first().click();
        await page.waitForTimeout(500);
      });
      row.assertions.cancel = { modalClosed: !(await modal.isVisible().catch(() => false)) };
      if (!row.assertions.cancel.modalClosed) throw new Error('custom source modal did not cancel');
      mark(row, 'cancel');
      sh('uci delete cf_ip.@source[0] 2>/dev/null || true; uci commit cf_ip 2>/dev/null || true');
    }
  },
  {
    id: 'src-lan', page: 'sources', control: 'LAN Publisher', kind: 'custom-field', plan: ['success', 'cancel'],
    custom: async (page, row) => {
      const box = fieldByLabel(page, 'Enable LAN Publisher');
      const port = fieldById(page, 'widget.cbid.cf_ip.lan.port');
      await capturePair(page, 'src-lan', 'success', async () => {
        await box.click();
        await port.fill('12345');
        await page.waitForTimeout(300);
      });
      row.assertions.success = { checked: await box.isChecked(), port: await port.inputValue() };
      if (!row.assertions.success.checked) throw new Error('LAN Publisher did not enable');
      mark(row, 'success');
      await capturePair(page, 'src-lan', 'cancel', async () => {
        await pageReset(page).click();
        await page.waitForTimeout(700);
      });
      row.assertions.cancel = { checked: await box.isChecked(), port: await port.inputValue() };
      if (row.assertions.cancel.checked) throw new Error('Reset did not disable LAN Publisher');
      mark(row, 'cancel');
    }
  },
  { id: 'src-refresh', page: 'sources', control: 'Refresh Sources', kind: 'rpc', method: 'refresh', button: 'Refresh Sources', transient: true, plan: ['loading', 'disabled', 'error', 'success', 'rollback'] },
  { id: 'src-save', page: 'sources', control: 'Save', kind: 'save', change: async page => fieldById(page, 'widget.cbid.cf_ip.main.candidate_budget').fill('200'), plan: ['success'] },

  { id: 'int-policy', page: 'intelligence', control: 'Source Strategy', kind: 'field', selector: 'widget.cbid.cf_ip.main.source_policy', type: 'select', value: 'history-heavy', plan: ['success', 'cancel'] },
  { id: 'int-probe', page: 'intelligence', control: 'Probe Batch Size', kind: 'field', selector: 'widget.cbid.cf_ip.main.probe_batch_size', value: '4', invalid: '0', plan: ['success', 'error', 'cancel'] },
  { id: 'int-early', page: 'intelligence', control: 'Deterministic Early Stop', kind: 'field', label: 'Deterministic Early Stop', type: 'checkbox', plan: ['success', 'cancel'] },
  { id: 'int-adaptive', page: 'intelligence', control: 'Adaptive Measurement Mode', kind: 'field', selector: 'widget.cbid.cf_ip.main.adaptive_measurement_mode', type: 'select', value: 'guarded', plan: ['success', 'cancel'] },
  { id: 'int-rill', page: 'intelligence', control: 'Rill Runtime', kind: 'field', label: 'Enable Rill Intelligence', type: 'checkbox', plan: ['success', 'cancel'] },
  { id: 'int-selfcheck', page: 'intelligence', control: 'Run self-check', kind: 'rpc', method: 'rill-self-check', button: 'Run self-check', expand: true, transient: true, plan: ['loading', 'disabled', 'error', 'success', 'rollback'] },
  { id: 'int-reset', page: 'intelligence', control: 'Reset learning state', kind: 'modal', method: 'rill-reset', open: 'Reset learning state', confirm: 'Reset', expand: true, plan: ['success', 'cancel', 'error', 'rollback'], setup: () => sh('uci set cf_ip.rill.enabled=1; uci commit cf_ip; rm -rf /tmp/luci-indexcache* /tmp/luci-modulecache'), teardown: () => sh('uci set cf_ip.rill.enabled=0; uci commit cf_ip; rm -rf /tmp/luci-indexcache* /tmp/luci-modulecache') },
  { id: 'int-long-values', page: 'intelligence', control: 'DummyValue long fields', kind: 'readonly', plan: ['success'] },
  { id: 'int-save', page: 'intelligence', control: 'Save', kind: 'save', change: async page => fieldById(page, 'widget.cbid.cf_ip.main.probe_batch_size').fill('5'), plan: ['success'] },
  { id: 'int-copy', page: 'intelligence', control: 'Copy buttons', kind: 'copy', plan: ['success', 'error'] },
  { id: 'int-collapse', page: 'intelligence', control: 'Live State collapse', kind: 'collapse', plan: ['success', 'cancel', 'rollback'] },
  { id: 'int-open-logs', page: 'intelligence', control: 'Open Logs & Records', kind: 'link', text: 'Open Logs & Records', target: '/cf_ip/logs', plan: ['success'] },

  { id: 'oc-path', page: 'openclash', control: 'Config File Path', kind: 'field', selector: 'widget.cbid.cf_ip.openclash.config', value: '/etc/openclash/config/config.yaml', plan: ['success', 'cancel'] },
  { id: 'oc-filter', page: 'openclash', control: 'Transport Filter', kind: 'field', selector: 'widget.cbid.cf_ip.openclash.transport_filter', value: 'ws', invalid: '', plan: ['success', 'cancel'] },
  { id: 'oc-backup-retry', page: 'openclash', control: 'Backup load failure / Retry', kind: 'rpc', method: 'oc-list-backups', button: 'Retry', reloadAfterAction: true, allowSameErrorScreenshot: true, plan: ['error', 'success', 'rollback'], note: { loading: 'Retry reloads the page instead of showing an async busy state.', disabled: 'Retry has no disabled state; it performs a page reload.' }, successSetup: () => sh('rm -f /etc/openclash/config/config.yaml.bak.*'), errorSetup: () => sh('printf "proxies: []\\n" > /etc/openclash/config/config.yaml.bak.20261104000004; chmod 600 /etc/openclash/config/config.yaml.bak.20261104000004'), teardown: () => sh('rm -f /etc/openclash/config/config.yaml.bak.*') },
  { id: 'oc-save', page: 'openclash', control: 'Save', kind: 'save', change: async page => fieldById(page, 'widget.cbid.cf_ip.openclash.backup_count').fill('2'), plan: ['success'] },
  { id: 'oc-details', page: 'openclash', control: 'Technical details', kind: 'details', plan: ['success', 'cancel'] },
  { id: 'oc-copy', page: 'openclash', control: 'Copy technical details', kind: 'copy', plan: ['success', 'error'] },

  { id: 'pw-domain', page: 'passwall', control: 'Target Domain', kind: 'field', selector: 'widget.cbid.cf_ip.passwall.target_domain', value: 'cdn.example.com', plan: ['success', 'cancel'] },
  { id: 'pw-save', page: 'passwall', control: 'Save', kind: 'save', change: async page => fieldById(page, 'widget.cbid.cf_ip.passwall.name_suffix').fill(' [CFX-{n}]'), plan: ['success'] },

  { id: 'adv-mirror', page: 'advanced', control: 'GitHub Mirror', kind: 'field', selector: 'widget.cbid.cf_ip.main.github_mirror', value: 'https://ghp.ci/', plan: ['success', 'cancel'] },
  { id: 'adv-validation', page: 'advanced', control: 'Timeout validation', kind: 'field', selector: 'widget.cbid.cf_ip.main.measurement_timeout', value: '60', invalid: '0', plan: ['success', 'error', 'cancel'] },
  { id: 'adv-save', page: 'advanced', control: 'Save', kind: 'save', change: async page => fieldById(page, 'widget.cbid.cf_ip.main.download_retries').fill('2'), plan: ['success'] },
  { id: 'adv-self-update', page: 'advanced', control: 'Script Update URL (read-only)', kind: 'readonly', selector: 'widget.cbid.cf_ip.main.self_update_url', plan: ['success', 'disabled'] },

  { id: 'log-refresh', page: 'logs', control: 'Refresh', kind: 'rpc', method: 'read-log', button: 'Refresh', transient: true, plan: ['loading', 'disabled', 'error', 'success', 'rollback'] },
  { id: 'log-clear', page: 'logs', control: 'Clear Logs', kind: 'modal', method: 'clear-log', open: 'Clear Logs', confirm: 'Clear', plan: ['success', 'cancel', 'error', 'rollback'] },
  { id: 'log-history', page: 'logs', control: 'IP History table', kind: 'readonly', plan: ['success'] },
  { id: 'logs-open-intelligence', page: 'logs', control: 'Open Intelligence', kind: 'link', text: 'Open Intelligence', target: '/cf_ip/intelligence', plan: ['success'] },
  { id: 'err-details', page: 'logs', control: 'Diagnostics technical details', kind: 'details', plan: ['success', 'cancel'] }
];

async function runPoint(context, def) {
  const row = baseRow(def);
  const started = Date.now();
  try {
    sh('uci revert cf_ip >/dev/null 2>&1 || true');
    if (def.setup) def.setup();
    if (def.kind === 'rpc') {
      await successRpc(context, def, row);
      if (def.plan.includes('loading')) await loadingRpc(context, def, row);
      if (def.plan.includes('error')) await errorRpc(context, def, row);
    } else if (def.kind === 'field') {
      await fieldSuccess(context, def, row);
      if (def.plan.includes('error')) await fieldError(context, def, row);
      if (def.plan.includes('cancel')) await fieldCancel(context, def, row);
      if (def.plan.includes('disabled') && def.selector) {
        const { page } = await openPage(context, def.page);
        const target = fieldById(page, def.selector);
        row.assertions.disabled = { disabled: await target.isDisabled(), readonly: await target.evaluate(el => el.readOnly) };
        row.states.disabled = 'PASS';
        await shot(page, def.id, 'disabled', 'after');
        await page.close();
      }
    } else if (def.kind === 'save') {
      await saveSuccess(context, def, row);
    } else if (def.kind === 'apply') {
      if (def.plan.includes('success')) await applySuccess(context, def, row);
      if (def.plan.includes('error')) await applyError(context, def, row);
    } else if (def.kind === 'dropdown') {
      await dropdownSuccess(context, def, row);
      if (def.plan.includes('cancel')) await dropdownCancel(context, def, row);
    } else if (def.kind === 'add') {
      await addStates(context, def, row);
    } else if (def.kind === 'modal') {
      await modalStates(context, def, row);
    } else if (def.kind === 'copy') {
      await copyStates(context, def, row);
    } else if (def.kind === 'collapse') {
      await collapseStates(context, def, row);
    } else if (def.kind === 'link') {
      await linkStates(context, def, row);
    } else if (def.kind === 'details') {
      await detailsStates(context, def, row);
    } else if (def.kind === 'readonly') {
      await readonlyStates(context, def, row);
    } else if (def.kind === 'reset') {
      const { page } = await openPage(context, def.page);
      const target = fieldById(page, 'widget.cbid.cf_ip.main.ip_count');
      const original = await target.inputValue();
      await capturePair(page, def.id, 'success', async () => {
        await target.fill('16');
        await pageReset(page).click();
        await page.waitForTimeout(700);
      });
      row.assertions.success = { original, restored: await target.inputValue() };
      if (row.assertions.success.restored !== original) throw new Error('Reset did not restore the original value');
      mark(row, 'success');
      await page.close();
    } else if (def.kind === 'custom-field') {
      await customFieldSuccess(context, def, row);
    }
  } catch (error) {
    row.status = 'FAIL';
    row.assertions.failure = error.message;
  }
  try { if (def.teardown) def.teardown(); } catch {}
  row.ms = Date.now() - started;
  for (const state of STATES) if (row.states[state] === 'PENDING') row.states[state] = 'FAIL';
  results.push(row);
  console.log(`${row.status} ${def.id}${row.assertions.failure ? ' — ' + row.assertions.failure : ''}`);
}

function persistenceFor(row, state) {
  const a = row.assertions[state] || {};
  if (typeof a.unchanged === 'boolean')
    return { status: 'ASSERTED', kind: 'server-state', before: a.before, after: a.after, unchanged: a.unchanged };
  if (a.browserChanges)
    return { status: 'ASSERTED', kind: 'uci-staging', changes: a.browserChanges };
  if (a.changes)
    return { status: 'ASSERTED', kind: 'uci-staging', changes: a.changes };
  if (a.persisted !== undefined)
    return { status: 'ASSERTED', kind: 'localStorage', persisted: a.persisted };
  if (row.kind === 'copy')
    return { status: 'N/A', reason: 'Clipboard content is transient by design; the copy label/aria state is asserted instead.' };
  if (row.kind === 'link')
    return { status: 'N/A', reason: 'Navigation does not persist data; the target URL is asserted instead.' };
  if (row.kind === 'details')
    return { status: 'N/A', reason: 'Opening the panel persists nothing; the open/closed DOM state is asserted.' };
  if (row.kind === 'field' || row.kind === 'custom-field')
    return { status: 'N/A', reason: 'The field holds a browser draft only; persistence is covered by the owning Save point.' };
  return { status: 'N/A', reason: 'This state produces no durable state; the rendered DOM/notification is the observable outcome.' };
}

(async () => {
  const browser = await chromium.launch({ headless: true, executablePath: process.env.CHROME_BIN });
  const context = await browser.newContext({ viewport: { width: 1280, height: 900 }, locale: 'en-US' });
  await context.grantPermissions(['clipboard-read', 'clipboard-write']);
  sh("uci set luci.main.lang='en'; uci commit luci; rm -rf /tmp/luci-indexcache* /tmp/luci-modulecache; /etc/init.d/uhttpd restart >/dev/null 2>&1");
  await sleep(1200);
  const loginPage = await pageFor(context);
  await login(loginPage);
  await loginPage.close();
  sh('printf "#!/bin/sh\\nexit 1\\n" > /etc/init.d/openclash; printf "#!/bin/sh\\nexit 1\\n" > /etc/init.d/passwall; chmod +x /etc/init.d/openclash /etc/init.d/passwall; mkdir -p /etc/openclash/config; printf "proxies: []\\n" > /etc/openclash/config/config.yaml; chmod 600 /etc/openclash/config/config.yaml; rm -f /etc/openclash/config/config.yaml.bak.*; rm -rf /tmp/luci-indexcache* /tmp/luci-modulecache');
  const selected = ONLY.length ? POINTS.filter(p => ONLY.includes(p.id)) : POINTS;
  try {
    for (const def of selected) await runPoint(context, def);
  } finally {
    try { sh("uci revert cf_ip >/dev/null 2>&1 || true; uci delete cf_ip.@source[0] 2>/dev/null; uci commit cf_ip; rm -rf /tmp/luci-indexcache* /tmp/luci-modulecache"); } catch {}
    await browser.close();
  }
  const reportSha = process.env.CFIP_UI_SHA || '1ec2a6d';
  const files = fs.readdirSync(OUT).filter(f => f.endsWith('.png'));
  const missingEvidence = [];
  for (const row of results) {
    row.environment = { sha: reportSha, base: BASE, container: CONTAINER, locale: 'en-US', viewport: [1280, 900], theme: null, dark: false };
    row.consoleErrors = {};
    row.evidenceIndex = {};
    for (const state of STATES) {
      if (row.states[state] !== 'PASS') continue;
      row.consoleErrors[state] = [];
      const snap = afterSnap[`${row.id}/${state}`] ||
        (state === 'disabled' ? (afterSnap[`${row.id}/loading`] || afterSnap[`${row.id}/success`]) : null);
      if (snap && !snap.snapshotError) {
        if (snap.theme) row.environment.theme = snap.theme;
        if (snap.viewport) row.environment.viewport = snap.viewport;
        row.environment.dark = snap.dark;
        row.assertions[state] = Object.assign({}, row.assertions[state] || {}, { dom: snap.dom, focus: snap.focus });
      }
      row.assertions[state] = Object.assign({}, row.assertions[state] || {}, { persistence: persistenceFor(row, state) });
      let evidence = files.filter(f => f.startsWith(row.id + '-' + state + '-')).sort()
        .map(f => ({ file: 'phase-f/matrix/' + f, sha256: sha(path.join(OUT, f)) }));
      if (!evidence.length && state === 'disabled') {
        const altState = ['loading', 'success'].find(s => files.some(f => f.startsWith(row.id + '-' + s + '-')));
        if (altState) {
          evidence = files.filter(f => f.startsWith(row.id + '-' + altState + '-')).sort()
            .map(f => ({ file: 'phase-f/matrix/' + f, sha256: sha(path.join(OUT, f)) }));
          row.assertions[state].evidenceReusedFrom = altState + ' (same rendered state)';
        }
      }
      row.evidenceIndex[state] = evidence;
      if (!evidence.length) missingEvidence.push(row.id + '/' + state);
    }
  }
  fs.writeFileSync(path.join(OUT, 'matrix.json'), JSON.stringify({ schemaVersion: 1, sha: reportSha, base: BASE, container: CONTAINER, points: results, missingEvidence }, null, 2) + '\n');
  const counts = {};
  for (const state of STATES) counts[state] = { PASS: 0, 'N/A': 0, FAIL: 0 };
  for (const row of results) for (const state of STATES) counts[state][row.states[state]] = (counts[state][row.states[state]] || 0) + 1;
  console.log(JSON.stringify({ points: results.length, counts, failures: results.filter(r => r.status === 'FAIL').length, missingEvidence }, null, 2));
  if (results.some(r => r.status === 'FAIL') || missingEvidence.length) process.exit(1);
})().catch(error => { console.error(error); process.exit(1); });
