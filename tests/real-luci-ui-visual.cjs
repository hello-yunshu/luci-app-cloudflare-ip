#!/usr/bin/env node
'use strict';
/*
 * Disposable visual regression gate. Uses an actual OpenWrt/uhttpd/rpcd/LuCI
 * container, and the pinned installed Aurora theme (not a CSS imitation).
 * This covers layout and initial view states; it is NOT a 51-point interaction
 * or physical-device test. Viewport 640 is not claimed as real 200% zoom.
 */
const fs = require('fs');
const path = require('path');
const { execFileSync } = require('child_process');
const { chromium } = require('playwright');

const base = process.env.CFIP_UI_BASE || 'http://127.0.0.1:18080';
const container = process.env.CFIP_UI_CONTAINER || 'cfip-ui-gate';
const password = process.env.CFIP_UI_PASSWORD || 'cfip-gate';
const output = process.env.CFIP_VISUAL_OUT || path.join(process.cwd(), 'real-luci-visual-evidence');
const pages = ['overview', 'settings', 'sources', 'intelligence', 'openclash', 'passwall', 'advanced', 'logs'];
const widths = [320, 375, 640, 768, 1280];
const themes = [
  { id: 'bootstrap-light', media: 'bootstrap', mode: null },
  { id: 'aurora-light', media: 'aurora', mode: 'light' },
  { id: 'aurora-dark', media: 'aurora', mode: 'dark' }
];
const report = {
  schemaVersion: 1,
  sha: process.env.GITHUB_SHA || process.env.CFIP_UI_SHA || 'unknown',
  environment: 'real OpenWrt 24.10.8 rootfs with uhttpd/rpcd/LuCI; Chromium Playwright',
  method: 'initial views, five CSS viewport widths, installed Bootstrap and Aurora 1.4.0 themes',
  notCovered: ['real 200% browser zoom', 'complete 51-point interaction matrix', 'physical router', 'Material theme', 'zh_cn rendering'],
  pages, widths, rows: [], errors: []
};
fs.mkdirSync(output, { recursive: true });

function shell(script) {
  return execFileSync('docker', ['exec', container, 'sh', '-c', script], { encoding: 'utf8' }).trim();
}
async function login(page) {
  await page.goto(base + '/cgi-bin/luci/', { waitUntil: 'domcontentloaded' });
  const user = page.locator('input[name="luci_username"]');
  if (await user.count()) {
    await user.fill('root');
    await page.locator('input[name="luci_password"]').fill(password);
    const submit = page.locator('button[type="submit"], input[type="submit"], button:has-text("Log in"), button:has-text("Login")').first();
    if (await submit.count()) await submit.click();
    else await page.locator('input[name="luci_password"]').press('Enter');
  }
  await page.waitForTimeout(1300);
  if (await page.locator('input[name="luci_password"]').count()) throw new Error('LuCI login failed');
}
async function measure(page, theme) {
  return page.evaluate(media => {
    const root = document.documentElement;
    const main = document.querySelector('#maincontent');
    const text = main ? (main.innerText || '').trim() : '';
    const links = Array.from(document.querySelectorAll('link[href],script[src]'));
    const themeLoaded = links.some(el => ((el.href || el.src || '')).includes('/luci-static/' + media + '/'));
    const truncated = Array.from((main || document).querySelectorAll('*'))
      .filter(el => {
        const css = getComputedStyle(el);
        return css.whiteSpace === 'nowrap' &&
          el.clientWidth > 0 && el.scrollWidth > el.clientWidth + 2 &&
          !el.closest('.cbi-dropdown') && !el.closest('#tabmenu');
      })
      .slice(0, 8).map(el => ({
        tag: el.tagName,
        className: String(el.className).slice(0, 90),
        text: (el.innerText || '').trim().slice(0, 90)
      }));
    return {
      width: innerWidth,
      scrollWidth: root.scrollWidth,
      overflow: root.scrollWidth > innerWidth + 1,
      mainLength: text.length,
      loading: /Loading view|加载视图/.test(text),
      hasMain: !!main,
      themeLoaded,
      darkMode: root.getAttribute('data-darkmode'),
      truncated,
      tabLinks: document.querySelectorAll('#tabmenu a').length
    };
  }, theme.media);
}
function write() {
  fs.writeFileSync(path.join(output, 'report.json'), JSON.stringify(report, null, 2) + '\n');
}
(async () => {
  const browser = await chromium.launch({ headless: true, executablePath: process.env.PLAYWRIGHT_EXECUTABLE || undefined });
  try {
    for (const theme of themes) {
      shell("uci set luci.main.mediaurlbase='/luci-static/" + theme.media + "'; uci commit luci; rm -rf /tmp/luci-indexcache* /tmp/luci-modulecache*; /etc/init.d/uhttpd restart >/dev/null 2>&1");
      await new Promise(resolve => setTimeout(resolve, 1200));
      const context = await browser.newContext({ viewport: { width: 1280, height: 900 }, colorScheme: theme.mode === 'dark' ? 'dark' : 'light' });
      if (theme.mode) await context.addInitScript(mode => localStorage.setItem('aurora.theme', mode), theme.mode);
      const page = await context.newPage();
      try {
        await login(page);
        for (const width of widths) {
          await page.setViewportSize({ width, height: 900 });
          for (const name of pages) {
            const consoleErrors = [];
            const listener = message => { if (message.type() === 'error') consoleErrors.push(message.text()); };
            const exception = error => consoleErrors.push('PAGE_ERROR ' + error.message);
            page.on('console', listener);
            page.on('pageerror', exception);
            let metrics = null;
            let navigationError = null;
            try {
              await page.goto(base + '/cgi-bin/luci/admin/services/cf_ip/' + name, { waitUntil: 'domcontentloaded', timeout: 30000 });
              await page.waitForFunction(() => {
                const m = document.querySelector('#maincontent');
                return m && m.innerText.trim().length > 20 && !/Loading view|加载视图/.test(m.innerText);
              }, null, { timeout: 20000 });
              await page.waitForTimeout(550);
              metrics = await measure(page, theme);
              await page.screenshot({ path: path.join(output, theme.id + '-' + width + '-' + name + '.png'), fullPage: true, animations: 'disabled' });
            } catch (error) {
              navigationError = error.message;
            } finally {
              page.off('console', listener);
              page.off('pageerror', exception);
            }
            const failures = [];
            if (navigationError) failures.push('navigation-or-render: ' + navigationError);
            if (metrics) {
              if (!metrics.hasMain || metrics.mainLength < 20 || metrics.loading) failures.push('blank-or-loading-view');
              if (!metrics.themeLoaded) failures.push('theme-assets-not-loaded');
              if (metrics.overflow) failures.push('horizontal-overflow');
              if (metrics.truncated.length) failures.push('truncated-non-dropdown-text');
              if (theme.mode === 'dark' && metrics.darkMode !== 'true') failures.push('aurora-dark-mode-not-applied');
              if (theme.mode === 'light' && metrics.darkMode === 'true') failures.push('aurora-light-mode-not-applied');
            }
            if (consoleErrors.length) failures.push('console-errors');
            const row = { theme: theme.id, width, page: name, result: failures.length ? 'FAIL' : 'PASS', failures, metrics, consoleErrors: consoleErrors.slice(0, 6) };
            report.rows.push(row);
            if (failures.length) report.errors.push({ theme: theme.id, width, page: name, failures, navigationError, consoleErrors: consoleErrors.slice(0, 6) });
            console.log(row.result + ' ' + theme.id + ' ' + width + ' ' + name + (failures.length ? ' -- ' + failures.join(', ') : ''));
            write();
          }
        }
      } finally {
        await context.close();
      }
    }
  } finally {
    await browser.close();
    write();
  }
  console.log('VISUAL_MATRIX ' + JSON.stringify({ total: report.rows.length, passed: report.rows.filter(r => r.result === 'PASS').length, failed: report.errors.length }));
  if (report.rows.length !== themes.length * widths.length * pages.length || report.errors.length) process.exitCode = 1;
})().catch(error => {
  report.errors.push({ fatal: error.stack || error.message });
  write();
  console.error('VISUAL_MATRIX_FATAL ' + (error.stack || error.message));
  process.exitCode = 1;
});
