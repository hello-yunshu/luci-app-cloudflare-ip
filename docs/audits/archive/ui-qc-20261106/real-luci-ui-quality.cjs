#!/usr/bin/env node
'use strict';
/*
 * Final UI quality gate for the three gaps left by the PR #33 visual matrix:
 *   1. real zh_cn rendering (rendered text + screenshots + pixel diff),
 *   2. browser zoom 125% / 200% (layout-equivalent device metrics),
 *   3. success / failure / cancel / rollback states of key interactions.
 *
 * The 120/120 initial-view matrix in real-luci-ui-visual.cjs is intentionally
 * not duplicated here. This script runs against the same real OpenWrt rootfs
 * with uhttpd/rpcd/LuCI and the pinned Aurora theme.
 *
 * Zoom note: a 1280x900 physical window at 125% / 200% browser zoom has a
 * 1024x720 / 640x450 CSS viewport and DPR 1.25 / 2. Chromium's device-metrics
 * emulation is layout-equivalent to that; the screenshots remain 1280px wide.
 * This is not a claim about Chrome's settings-page zoom control.
 */
const fs = require('fs');
const path = require('path');
const { execFileSync, spawnSync } = require('child_process');
const { chromium } = require('playwright');
let PNG = null;
try { PNG = require('pngjs').PNG; } catch (e) { /* optional; diff disabled without pngjs */ }

const base = process.env.CFIP_UI_BASE || 'http://127.0.0.1:18080';
const container = process.env.CFIP_UI_CONTAINER || 'cfip-ui-qc';
const password = process.env.CFIP_UI_PASSWORD || 'cfip-gate';
const output = process.env.CFIP_QC_OUT || path.join(process.cwd(), 'real-luci-quality-evidence');
const mode = process.env.CFIP_QC_MODE || 'all';
const executablePath = process.env.PLAYWRIGHT_EXECUTABLE || undefined;
const pages = ['overview', 'settings', 'sources', 'intelligence', 'openclash', 'passwall', 'advanced', 'logs'];
const themes = [
  { id: 'bootstrap-light', media: 'bootstrap', mode: null },
  { id: 'aurora-light', media: 'aurora', mode: 'light' },
  { id: 'aurora-dark', media: 'aurora', mode: 'dark' }
];
const zhTabs = ['概览', '设置', '候选 IP 来源', '智能优选', '高级', '日志与记录'];
const zhHints = {
  overview: ['服务控制', '优选 IP 数量', 'IP 类型'],
  settings: ['设置', '服务', 'IP 数量'],
  sources: ['候选 IP 来源', '内置来源'],
  intelligence: ['智能优选', '自适应测量'],
  openclash: [],
  passwall: [],
  advanced: ['高级', '脚本更新'],
  logs: ['日志与记录', '清除日志']
};
const englishResidue = [
  'Service Control', 'Best IP Count', 'IP Type', 'Clear Logs', 'Save & Apply',
  'Candidate IP Sources', 'Intelligence', 'Logs & Records', 'Refresh',
  'Service Stopped', 'Service Running'
];
const forbiddenLoaded = /Loading view|加载视图/;

fs.mkdirSync(output, { recursive: true });
const report = {
  schemaVersion: 1,
  sha: process.env.GITHUB_SHA || process.env.CFIP_QC_SHA || 'local',
  environment: 'real OpenWrt 24.10.8 rootfs (uhttpd/rpcd/LuCI, Aurora 1.4.0) + Chromium',
  method: {
    zh: 'LuCI uci main.lang=zh_cn with po2lmo-compiled cloudflare-ip.zh-cn.lmo; page text, tab labels, screenshots, EN/ZH pixel diff',
    zoom: 'device metrics: physical 1280x900 window => 1024x720 @DPR1.25 (125%) and 640x450 @DPR2 (200%); layout-equivalent to browser zoom, not chrome://settings zoom',
    states: 'real LuCI CBI + rpcd; failure states use transport fault injection on the cf_ip RPC endpoint',
    preferences: 'Chromium prefers-reduced-motion=reduce; computed animation-name probe against the shared CSS'
  },
  limitations: [
    'zoom uses device-metrics emulation, not Chrome settings-page zoom',
    'failure state is transport/RPC fault injection, not a broken backend package',
    'physical router, 24h soak, PassWall/OpenClash real networks are out of scope',
    'OCR not run (tesseract absent locally); zh evidence uses rendered DOM text + screenshots + EN/ZH pixel diff'
  ],
  zh: [], zoom: [], states: [], preferences: [], errors: []
};
const commandLog = [];

function write() {
  fs.writeFileSync(path.join(output, 'report.json'), JSON.stringify(report, null, 2) + '\n');
  fs.writeFileSync(path.join(output, 'commands.log'), commandLog.join('\n') + '\n');
}
function shell(script, check = true) {
  commandLog.push('docker exec ' + container + ' sh -c ' + JSON.stringify(script));
  try {
    return execFileSync('docker', ['exec', container, 'sh', '-c', script], { encoding: 'utf8', stdio: ['ignore', 'pipe', 'pipe'] }).trim();
  } catch (error) {
    if (check) throw new Error('container command failed: ' + script + '\n' + (error.stderr || error.message));
    return null;
  }
}
function logPath() { return '/tmp/cf_ip/cf-ip-auto.log'; }
function setTheme(theme) {
  shell("uci set luci.main.mediaurlbase='/luci-static/" + theme.media + "'; uci commit luci; rm -rf /tmp/luci-indexcache* /tmp/luci-modulecache*; /etc/init.d/uhttpd restart >/dev/null 2>&1");
}
function setLang(lang) {
  shell("uci set luci.main.lang='" + lang + "'; uci commit luci; rm -rf /tmp/luci-indexcache* /tmp/luci-modulecache*; /etc/init.d/uhttpd restart >/dev/null 2>&1");
}
async function sleep(ms) { await new Promise(r => setTimeout(r, ms)); }
async function makeContext(browser, theme, width, height, dsf, lang) {
  const context = await browser.newContext({ viewport: { width, height }, deviceScaleFactor: dsf, colorScheme: theme.mode === 'dark' ? 'dark' : 'light' });
  if (theme.mode) await context.addInitScript(m => localStorage.setItem('aurora.theme', m), theme.mode);
  if (lang) await context.addCookies([{ name: 'luci_lang', value: lang, url: base }]);
  return context;
}
async function login(page, lang) {
  const prefix = '/cgi-bin/luci/' + (lang ? '?lang=' + lang : '');
  await page.goto(base + prefix, { waitUntil: 'domcontentloaded', timeout: 30000 });
  const user = page.locator('input[name="luci_username"]');
  if (await user.count()) {
    await user.fill('root');
    await page.locator('input[name="luci_password"]').fill(password);
    const submit = page.locator('button[type="submit"], input[type="submit"], button:has-text("Log in"), button:has-text("登录")').first();
    if (await submit.count()) await submit.click();
    else await page.locator('input[name="luci_password"]').press('Enter');
    await page.waitForFunction(() => !document.querySelector('input[name="luci_password"]'), null, { timeout: 20000 });
  }
  await page.goto(base + prefix, { waitUntil: 'domcontentloaded', timeout: 30000 });
  await page.waitForTimeout(300);
  if (await page.locator('input[name="luci_password"]').count()) throw new Error('LuCI login failed');
}
async function gotoPage(page, name) {
  await page.goto(base + '/cgi-bin/luci/admin/services/cf_ip/' + name, { waitUntil: 'domcontentloaded', timeout: 30000 });
  await page.waitForFunction(() => {
    const m = document.querySelector('#maincontent');
    return m && m.innerText.trim().length > 20 && !/Loading view|加载视图/.test(m.innerText);
  }, null, { timeout: 25000 });
  await page.waitForTimeout(500);
}
async function measure(page, theme) {
  return page.evaluate(media => {
    const root = document.documentElement;
    const main = document.querySelector('#maincontent');
    const text = main ? (main.innerText || '').trim() : '';
    /* UI chrome text without raw JSON/log payloads: a diagnostics dump can
     * contain English identifiers that are not user-visible labels. */
    const uiTextOf = rootEl => {
      if (!rootEl) return '';
      const skip = new Set(rootEl.querySelectorAll('pre, textarea, script, style'));
      let out = '';
      const walker = document.createTreeWalker(rootEl, NodeFilter.SHOW_TEXT);
      let node;
      while ((node = walker.nextNode())) {
        let p = node.parentElement, skipped = false;
        while (p) { if (skip.has(p)) { skipped = true; break; } p = p.parentElement; }
        if (!skipped) out += node.nodeValue + ' ';
      }
      return out;
    };
    const links = Array.from(document.querySelectorAll('link[href],script[src]'));
    const themeLoaded = links.some(el => ((el.href || el.src || '')).includes('/luci-static/' + media + '/'));
    const truncated = Array.from((main || document).querySelectorAll('*'))
      .filter(el => {
        if (el.tagName === 'INPUT' || el.tagName === 'TEXTAREA') return false;
        const css = getComputedStyle(el);
        return css.whiteSpace === 'nowrap' && el.clientWidth > 0 && el.scrollWidth > el.clientWidth + 2 &&
          !el.closest('.cbi-dropdown') && !el.closest('#tabmenu');
      })
      .slice(0, 8).map(el => ({ tag: el.tagName, className: String(el.className).slice(0, 90), text: (el.innerText || '').trim().slice(0, 90) }));
    return {
      width: innerWidth, height: innerHeight, dpr: devicePixelRatio,
      scrollWidth: root.scrollWidth, overflow: root.scrollWidth > innerWidth + 1,
      mainLength: text.length, loading: /Loading view|加载视图/.test(text),
      hasMain: !!main, themeLoaded, darkMode: root.getAttribute('data-darkmode'),
      truncated, tabText: (document.querySelector('#tabmenu') || {}).innerText || '',
      mainText: text.slice(0, 1200), uiText: uiTextOf(main), lang: document.documentElement.lang,
      cjkFont: /[\u4e00-\u9fff]/.test(text) && document.fonts ? document.fonts.check('16px sans-serif', '服务控制') : false,
      mq640: matchMedia('(max-width: 640px)').matches, mq768: matchMedia('(max-width: 768px)').matches
    };
  }, theme.media);
}
function pngInfo(file) {
  if (!PNG) return { width: null, height: null, inkRatio: null };
  const png = PNG.sync.read(fs.readFileSync(file));
  const counts = new Map();
  for (let i = 0; i < png.data.length; i += 4) {
    const key = (png.data[i] << 16) | (png.data[i + 1] << 8) | png.data[i + 2];
    counts.set(key, (counts.get(key) || 0) + 1);
  }
  let bg = 0, bgCount = 0;
  for (const [key, count] of counts) if (count > bgCount) { bg = key; bgCount = count; }
  const br = (bg >> 16) & 255, bgc = (bg >> 8) & 255, bb = bg & 255;
  let ink = 0;
  for (let i = 0; i < png.data.length; i += 4) {
    const d = Math.abs(png.data[i] - br) + Math.abs(png.data[i + 1] - bgc) + Math.abs(png.data[i + 2] - bb);
    if (d > 30) ink++;
  }
  return { width: png.width, height: png.height, inkRatio: ink / (png.width * png.height) };
}
function pngDiff(a, b) {
  if (!PNG || !fs.existsSync(a) || !fs.existsSync(b)) return { ratio: null, reason: 'pngjs or file missing' };
  const x = PNG.sync.read(fs.readFileSync(a));
  const y = PNG.sync.read(fs.readFileSync(b));
  if (x.width !== y.width) return { ratio: null, reason: 'width mismatch ' + x.width + ' vs ' + y.width };
  const h = Math.min(x.height, y.height);
  let changed = 0;
  for (let row = 0; row < h; row++) {
    for (let col = 0; col < x.width; col++) {
      const i = (row * x.width + col) * 4;
      if (Math.abs(x.data[i] - y.data[i]) + Math.abs(x.data[i + 1] - y.data[i + 1]) + Math.abs(x.data[i + 2] - y.data[i + 2]) > 16) changed++;
    }
  }
  return { ratio: changed / (x.width * h), heightDelta: y.height - x.height, comparedHeight: h };
}
function ocr(file) {
  const which = spawnSync('tesseract', ['--version'], { encoding: 'utf8' });
  if (which.error) return null;
  const out = spawnSync('tesseract', [file, 'stdout', '-l', 'chi_sim+eng', '--psm', '6'], { encoding: 'utf8', timeout: 60000 });
  return out.error ? null : out.stdout.replace(/\s+/g, '');
}
function rowFailures(metrics, theme, basename) {
  const failures = [];
  if (!metrics.hasMain || metrics.mainLength < 20 || metrics.loading) failures.push('blank-or-loading-view');
  if (!metrics.themeLoaded) failures.push('theme-assets-not-loaded');
  if (metrics.overflow) failures.push('horizontal-overflow');
  if (metrics.truncated.length) failures.push('truncated-non-dropdown-text');
  if (theme.mode === 'dark' && metrics.darkMode !== 'true') failures.push('aurora-dark-mode-not-applied');
  if (theme.mode === 'light' && metrics.darkMode === 'true') failures.push('aurora-light-mode-not-applied');
  return failures;
}

async function runZh(browser) {
  for (const theme of themes) {
    setTheme(theme);
    await sleep(1200);
    for (const width of [375, 1280]) {
      // English baseline for pixel diff. Reset language for every width.
      setLang('en');
      await sleep(1200);
      const enContext = await makeContext(browser, theme, width, 900, 1, null);
      const enPage = await enContext.newPage();
      await login(enPage);
      for (const name of pages) {
        await gotoPage(enPage, name);
        await enPage.screenshot({ path: path.join(output, 'en', theme.id, String(width), name + '.png'), fullPage: true, animations: 'disabled' });
      }
      await enContext.close();

      setLang('zh_cn');
      await sleep(1200);
      const zhContext = await makeContext(browser, theme, width, 900, 1, 'zh_cn');
      const zhPage = await zhContext.newPage();
      await login(zhPage, 'zh_cn');
      for (const name of pages) {
        const consoleErrors = [];
        const listener = m => { if (m.type() === 'error') consoleErrors.push(m.text()); };
        const exception = e => consoleErrors.push('PAGE_ERROR ' + e.message);
        zhPage.on('console', listener); zhPage.on('pageerror', exception);
        let metrics = null, error = null;
        try {
          await gotoPage(zhPage, name);
          metrics = await measure(zhPage, theme);
          await zhPage.screenshot({ path: path.join(output, 'zh', theme.id, String(width), name + '.png'), fullPage: true, animations: 'disabled' });
        } catch (e) { error = e.message; }
        finally { zhPage.off('console', listener); zhPage.off('pageerror', exception); }
        const failures = error ? ['navigation-or-render: ' + error] : metrics ? rowFailures(metrics, theme, name) : ['no-metrics'];
        if (metrics) {
          /* Check all user-visible chrome text (not just the first 1200 chars)
           * while ignoring raw JSON/log payload dumps. */
          if (!/[\u4e00-\u9fff]/.test(metrics.uiText)) failures.push('main-content-not-chinese');
          for (const tab of zhTabs) if (!metrics.tabText.includes(tab)) failures.push('missing-tab:' + tab);
          for (const hint of (zhHints[name] || [])) if (!metrics.uiText.includes(hint)) failures.push('missing-zh:' + hint);
          for (const en of englishResidue) if (metrics.uiText.includes(en)) failures.push('english-residue:' + en);
          if (metrics.lang && !/zh/i.test(metrics.lang)) failures.push('html-lang-not-zh:' + metrics.lang);
          if (!metrics.cjkFont) failures.push('cjk-font-unavailable');
        }
        if (consoleErrors.length) failures.push('console-errors');
        const shot = path.join(output, 'zh', theme.id, String(width), name + '.png');
        const enShot = path.join(output, 'en', theme.id, String(width), name + '.png');
        const pixel = fs.existsSync(shot) ? pngInfo(shot) : null;
        const diff = fs.existsSync(shot) ? pngDiff(enShot, shot) : null;
        if (pixel && pixel.inkRatio !== null && pixel.inkRatio < 0.002) failures.push('screenshot-blank:' + pixel.inkRatio);
        if (diff && diff.ratio !== null && diff.ratio < 0.005) failures.push('pixel-diff-too-small:' + diff.ratio);
        const ocrText = (name === 'overview' || name === 'settings') && width === 1280 ? ocr(shot) : null;
        if (ocrText !== null) {
          const found = (zhHints[name] || []).some(h => ocrText.includes(h));
          if (!found) failures.push('ocr-did-not-find-zh');
        }
        report.zh.push({ theme: theme.id, width, page: name, result: failures.length ? 'FAIL' : 'PASS', failures, pixel, pixelDiff: diff, ocr: ocrText === null ? 'unavailable' : (ocrText.includes('服务') || ocrText.includes('设置') ? 'found-zh' : 'no-zh-token'), consoleErrors: consoleErrors.slice(0, 6) });
        if (failures.length) report.errors.push({ area: 'zh', theme: theme.id, width, page: name, failures });
        console.log((failures.length ? 'FAIL' : 'PASS') + ' zh ' + theme.id + ' ' + width + ' ' + name + (failures.length ? ' -- ' + failures.join(', ') : ''));
        write();
      }
      await zhContext.close();
    }
  }
}

async function runZoom(browser) {
  setLang('en');
  await sleep(1200);
  const zooms = [
    { factor: 1.25, css: [1024, 720], physical: 1280 },
    { factor: 2, css: [640, 450], physical: 1280 }
  ];
  for (const theme of themes) {
    setTheme(theme);
    await sleep(1200);
    for (const z of zooms) {
      const context = await makeContext(browser, theme, z.css[0], z.css[1], z.factor, null);
      const page = await context.newPage();
      await login(page);
      for (const name of pages) {
        const consoleErrors = [];
        const listener = m => { if (m.type() === 'error') consoleErrors.push(m.text()); };
        const exception = e => consoleErrors.push('PAGE_ERROR ' + e.message);
        page.on('console', listener); page.on('pageerror', exception);
        let metrics = null, error = null;
        try {
          await gotoPage(page, name);
          metrics = await measure(page, theme);
          await page.screenshot({ path: path.join(output, 'zoom', String(z.factor), theme.id, name + '.png'), fullPage: true, animations: 'disabled' });
        } catch (e) { error = e.message; }
        finally { page.off('console', listener); page.off('pageerror', exception); }
        const failures = error ? ['navigation-or-render: ' + error] : metrics ? rowFailures(metrics, theme, name) : ['no-metrics'];
        if (metrics) {
          if (metrics.width !== z.css[0]) failures.push('css-width:' + metrics.width + '!=' + z.css[0]);
          if (metrics.dpr !== z.factor) failures.push('dpr:' + metrics.dpr + '!=' + z.factor);
          if (metrics.mq640 !== (z.css[0] <= 640)) failures.push('mq640-mismatch');
          if (z.css[0] === 1024 && metrics.mq768) failures.push('mq768-unexpected');
        }
        if (consoleErrors.length) failures.push('console-errors');
        const shot = path.join(output, 'zoom', String(z.factor), theme.id, name + '.png');
        const pixel = fs.existsSync(shot) ? pngInfo(shot) : null;
        if (pixel && pixel.width !== z.physical) failures.push('physical-width:' + pixel.width + '!=' + z.physical);
        if (pixel && pixel.height < 900) failures.push('physical-height-below-viewport:' + pixel.height);
        report.zoom.push({ factor: z.factor, css: z.css, physical: [z.physical, 900], theme: theme.id, page: name, result: failures.length ? 'FAIL' : 'PASS', failures, pixel, consoleErrors: consoleErrors.slice(0, 6) });
        if (failures.length) report.errors.push({ area: 'zoom', factor: z.factor, theme: theme.id, page: name, failures });
        console.log((failures.length ? 'FAIL' : 'PASS') + ' zoom ' + z.factor + ' ' + theme.id + ' ' + name + (failures.length ? ' -- ' + failures.join(', ') : ''));
        write();
      }
      await context.close();
    }
  }
}

async function saveUiCount(page, value) {
  const input = page.locator('input[id="widget.cbid.cf_ip.main.ip_count"]');
  if (!await input.count()) throw new Error('ip_count input not found');
  await input.fill(String(value));
  await input.dispatchEvent('change');
}
async function clickSaveApply(page) {
  /* luci.js renders Save & Apply as a ui.ComboButton: the clickable node is the
   * div.cbi-dropdown wrapper; button.cbi-button-save only calls handleSave. */
  const button = page.locator('div.cbi-dropdown.cbi-button-apply').first();
  if (!await button.count()) throw new Error('Save & Apply button not found');
  await button.scrollIntoViewIfNeeded();
  await button.click();
}
async function waitNotice(page, text, timeout = 20000) {
  /* ui.addNotification() creates div.alert-message nodes. */
  await page.waitForFunction(t => Array.from(document.querySelectorAll('.alert-message'))
    .some(n => (n.innerText || '').includes(t)), text, { timeout });
}
async function reloginAfterReload(page, theme) {
  await page.waitForTimeout(1200);
  if (await page.locator('input[name="luci_username"]').count()) await login(page);
  await page.goto(base + '/cgi-bin/luci/admin/services/cf_ip/settings', { waitUntil: 'domcontentloaded' });
  await page.waitForTimeout(1500);
}

async function runStates(browser) {
  const theme = themes[0];
  setTheme(theme); setLang('en');
  await sleep(1200);
  const context = await makeContext(browser, theme, 1280, 900, 1, null);
  const page = await context.newPage();
  await login(page);

  async function uciValue() { return shell("uci get cf_ip.main.ip_count 2>/dev/null || echo MISSING"); }
  /* uci get merges pending deltas; the applied value must be read from disk. */
  async function appliedCount() {
    const line = await shell("grep ip_count /etc/config/cf_ip 2>/dev/null || true");
    const m = line.match(/ip_count '([^']*)'/);
    return m ? m[1] : 'MISSING';
  }
  async function resetUci(v) { shell("uci revert cf_ip >/dev/null 2>&1 || true; uci set cf_ip.main.ip_count='" + v + "'; uci commit cf_ip"); }
  /* LuCI JS rpc posts JSON-RPC batches to /ubus/. Abort only the matching call
   * so the surrounding save/readback path stays real. */
  async function abortRpcCall(page, object, method) {
    let count = 0;
    const route = async r => {
      const body = r.request().postData() || '';
      if (body.includes('"' + object + '","' + method + '"')) { count++; return r.abort('failed'); }
      return r.continue();
    };
    await page.route('**/ubus/**', route);
    return { route, hits: () => count };
  }

  // Settings success: applied baseline 4 -> save/apply 5.
  await resetUci('4');
  await gotoPage(page, 'settings');
  const before = await appliedCount();
  await saveUiCount(page, 5);
  await clickSaveApply(page);
  await waitNotice(page, 'Configuration saved and applied.');
  await page.screenshot({ path: path.join(output, 'states', 'settings-success.png'), fullPage: true });
  const afterSuccess = await appliedCount();
  const successPass = before === '4' && afterSuccess === '5';
  report.states.push({ interaction: 'settings-save', state: 'success', result: successPass ? 'PASS' : 'FAIL', detail: 'applied ' + before + ' -> ' + afterSuccess, evidence: 'states/settings-success.png' });
  if (!successPass) report.errors.push({ area: 'states', interaction: 'settings-save', state: 'success', detail: before + '->' + afterSuccess });

  // Cancel: unsaved draft is discarded by Reset, applied config untouched.
  await page.waitForTimeout(1500);
  await reloginAfterReload(page, theme);
  await saveUiCount(page, 7);
  const reset = page.locator('button.cbi-button-reset').first();
  if (await reset.count()) await reset.click();
  await page.waitForTimeout(800);
  const inputValue = await page.locator('input[id="widget.cbid.cf_ip.main.ip_count"]').inputValue();
  await page.screenshot({ path: path.join(output, 'states', 'settings-cancel.png'), fullPage: true });
  const cancelPass = inputValue === '5' && (await appliedCount()) === '5';
  report.states.push({ interaction: 'settings-save', state: 'cancel', result: cancelPass ? 'PASS' : 'FAIL', detail: 'draft_reverted_to=' + inputValue + ' applied=' + await appliedCount(), evidence: 'states/settings-cancel.png' });
  if (!cancelPass) report.errors.push({ area: 'states', interaction: 'settings-save', state: 'cancel', detail: 'input=' + inputValue });

  // Failure: abort validate-config; applied config must stay at 5.
  await saveUiCount(page, 6);
  const failRpc = await abortRpcCall(page, 'cf_ip', 'validate-config');
  await clickSaveApply(page);
  await waitNotice(page, 'Unable to apply configuration.');
  await page.screenshot({ path: path.join(output, 'states', 'settings-failure.png'), fullPage: true });
  await page.unroute('**/ubus/**', failRpc.route);
  const aborted = failRpc.hits();
  const afterFailure = await appliedCount();
  const failurePass = afterFailure === '5' && aborted > 0;
  report.states.push({ interaction: 'settings-save', state: 'failure', result: failurePass ? 'PASS' : 'FAIL', detail: 'aborted_rpc=' + aborted + ' applied_preserved=' + afterFailure, evidence: 'states/settings-failure.png' });
  if (!failurePass) report.errors.push({ area: 'states', interaction: 'settings-save', state: 'failure', detail: 'aborted=' + aborted + ' applied=' + afterFailure });

  // Rollback: a failed apply must leave the previous applied config; a freshly
  // opened LuCI session shows the restored value.
  const changesAfterFailure = shell("uci changes cf_ip | tr '\\n' ' '");
  /* Revert through ubus: the CLI-only revert leaves rpcd's cached config stale. */
  shell("ubus call uci revert '{\"config\":\"cf_ip\"}' >/dev/null 2>&1 || uci revert cf_ip");
  const changesAfterRevert = shell("uci changes cf_ip | tr '\\n' ' '");
  /* A brand-new context avoids Chromium restoring the failed draft DOM value. */
  const rollbackContext = await makeContext(browser, theme, 1280, 900, 1, null);
  const rollbackPage = await rollbackContext.newPage();
  await login(rollbackPage);
  await rollbackPage.goto(base + '/cgi-bin/luci/admin/services/cf_ip/settings?qc=rollback', { waitUntil: 'domcontentloaded' });
  await rollbackPage.waitForTimeout(1500);
  const rolled = await rollbackPage.locator('input[id="widget.cbid.cf_ip.main.ip_count"]').inputValue();
  await rollbackPage.screenshot({ path: path.join(output, 'states', 'settings-rollback.png'), fullPage: true });
  await rollbackContext.close();
  const rollbackPass = rolled === '5' && (await appliedCount()) === '5';
  report.states.push({ interaction: 'settings-save', state: 'rollback', result: rollbackPass ? 'PASS' : 'FAIL', detail: 'fresh_session_value=' + rolled + ' applied=' + await appliedCount() + ' pending_before_revert=[' + changesAfterFailure + '] pending_after_revert=[' + changesAfterRevert + ']', evidence: 'states/settings-rollback.png' });
  if (!rollbackPass) report.errors.push({ area: 'states', interaction: 'settings-save', state: 'rollback', detail: rolled });
  await resetUci(before);

  // Clear Logs: success / failure / cancel.
  const seed = "mkdir -p /tmp/cf_ip; printf 'qc-log-line\\n' > " + logPath();
  async function logContent() { return shell("cat " + logPath() + " 2>/dev/null || true", false); }
  async function clickClear(page) {
    const btn = page.locator('button:has-text("Clear Logs")').first();
    await btn.click();
    await page.waitForTimeout(400);
  }
  async function confirmClear(page) {
    const modal = page.locator('.modal, .modal-overlay, .ui-modal').last();
    const confirm = modal.locator('button:has-text("Clear")').last();
    if (await confirm.count()) await confirm.click();
    else await page.locator('button:has-text("Clear")').last().click();
    await page.waitForTimeout(400);
  }
  shell(seed);
  await gotoPage(page, 'logs');
  await clickClear(page);
  await page.locator('button:has-text("Cancel")').last().click();
  await page.waitForTimeout(600);
  await page.screenshot({ path: path.join(output, 'states', 'logs-cancel.png'), fullPage: true });
  const cancelLog = await logContent();
  const logsCancelPass = cancelLog.includes('qc-log-line');
  report.states.push({ interaction: 'logs-clear', state: 'cancel', result: logsCancelPass ? 'PASS' : 'FAIL', detail: 'log_preserved=' + logsCancelPass, evidence: 'states/logs-cancel.png' });
  if (!logsCancelPass) report.errors.push({ area: 'states', interaction: 'logs-clear', state: 'cancel' });

  shell(seed);
  await gotoPage(page, 'logs');
  await clickClear(page);
  await confirmClear(page);
  /* Success is rendered inside the log textarea, not as a notification. */
  await page.waitForFunction(() => {
    const area = document.querySelector('#log-area');
    return area && /Log file cleared\./.test(area.value || '');
  }, null, { timeout: 20000 });
  await page.screenshot({ path: path.join(output, 'states', 'logs-success.png'), fullPage: true });
  const cleared = await logContent();
  const logsSuccessPass = cleared.trim() === '';
  report.states.push({ interaction: 'logs-clear', state: 'success', result: logsSuccessPass ? 'PASS' : 'FAIL', detail: 'log_bytes=' + cleared.length, evidence: 'states/logs-success.png' });
  if (!logsSuccessPass) report.errors.push({ area: 'states', interaction: 'logs-clear', state: 'success', detail: cleared.slice(0, 80) });

  shell(seed);
  await gotoPage(page, 'logs');
  const clearRpc = await abortRpcCall(page, 'cf_ip', 'clear-log');
  await clickClear(page);
  await confirmClear(page);
  await waitNotice(page, 'Unable to clear logs.');
  await page.screenshot({ path: path.join(output, 'states', 'logs-failure.png'), fullPage: true });
  await page.unroute('**/ubus/**', clearRpc.route);
  const clearAborted = clearRpc.hits();
  const preserved = await logContent();
  const logsFailurePass = preserved.includes('qc-log-line') && clearAborted > 0;
  report.states.push({ interaction: 'logs-clear', state: 'failure', result: logsFailurePass ? 'PASS' : 'FAIL', detail: 'aborted_rpc=' + clearAborted + ' log_preserved=' + logsFailurePass, evidence: 'states/logs-failure.png' });
  if (!logsFailurePass) report.errors.push({ area: 'states', interaction: 'logs-clear', state: 'failure', detail: 'aborted=' + clearAborted });
  report.states.push({ interaction: 'logs-clear', state: 'rollback', result: 'NOT_APPLICABLE', detail: 'log clearing is destructive with no undo; failure/cancel preserve the file', evidence: 'states/logs-cancel.png' });

  /* prefers-reduced-motion: real media emulation + computed style probe. */
  const rmContext = await browser.newContext({ viewport: { width: 1280, height: 900 }, colorScheme: 'light', reducedMotion: 'reduce' });
  const rmPage = await rmContext.newPage();
  await login(rmPage);
  await rmPage.goto(base + '/cgi-bin/luci/admin/services/cf_ip/overview', { waitUntil: 'domcontentloaded' });
  await rmPage.waitForTimeout(1500);
  const rmAnimation = await rmPage.evaluate(() => {
    const host = document.querySelector('.cfi-dashboard') || document.body;
    const probe = document.createElement('span');
    probe.className = 'cfi-status-icon running-test';
    probe.style.cssText = 'position:fixed;left:-9999px;top:0';
    host.appendChild(probe);
    const name = getComputedStyle(probe).animationName;
    probe.remove();
    return name;
  });
  await rmContext.close();
  const rmPass = rmAnimation === 'none';
  report.preferences.push({ preference: 'prefers-reduced-motion', result: rmPass ? 'PASS' : 'FAIL', detail: 'animation-name=' + rmAnimation });
  if (!rmPass) report.errors.push({ area: 'preferences', preference: 'prefers-reduced-motion', detail: rmAnimation });

  await context.close();
}

(async () => {
  const browser = await chromium.launch({ headless: true, executablePath: executablePath || undefined });
  try {
    if (mode === 'zh' || mode === 'all') await runZh(browser);
    if (mode === 'zoom' || mode === 'all') await runZoom(browser);
    if (mode === 'states' || mode === 'all') await runStates(browser);
  } finally {
    await browser.close();
    write();
  }
  const summary = {
    zh: { total: report.zh.length, pass: report.zh.filter(r => r.result === 'PASS').length },
    zoom: { total: report.zoom.length, pass: report.zoom.filter(r => r.result === 'PASS').length },
    states: { total: report.states.length, pass: report.states.filter(r => r.result === 'PASS').length },
    preferences: { total: report.preferences.length, pass: report.preferences.filter(r => r.result === 'PASS').length },
    errors: report.errors.length
  };
  console.log('QUALITY ' + JSON.stringify(summary));
  if (report.errors.length) process.exitCode = 1;
})().catch(error => {
  report.errors.push({ fatal: error.stack || error.message });
  write();
  console.error('QUALITY_FATAL ' + (error.stack || error.message));
  process.exitCode = 1;
});
