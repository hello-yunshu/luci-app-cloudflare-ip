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
const language = process.env.CFIP_UI_LANG || 'en';
const allPages = ['overview', 'settings', 'sources', 'intelligence', 'openclash', 'passwall', 'advanced', 'logs'];
const requestedPages = (process.env.CFIP_VISUAL_PAGES || '').split(',').map(name => name.trim()).filter(Boolean);
const pages = requestedPages.length ? allPages.filter(name => requestedPages.includes(name)) : allPages;
const scenario = process.env.CFIP_VISUAL_SCENARIO || 'default-installed-packages';
if (pages.length !== (requestedPages.length || allPages.length))
  throw new Error('CFIP_VISUAL_PAGES contains an unknown page: ' + requestedPages.join(','));
const optionalPages = new Set(['openclash', 'passwall']);
const expectedTitlesByLanguage = {
en: {
  overview: 'Overview', settings: 'Settings', sources: 'Candidate Sources',
  intelligence: 'Rill Intelligence', openclash: 'OpenClash', passwall: 'PassWall',
  advanced: 'Advanced', logs: 'Logs & Records'
},
zh_cn: {
  overview: '概览', settings: '设置', sources: '候选来源',
  intelligence: 'Rill 智能', openclash: 'OpenClash', passwall: 'PassWall',
  advanced: '高级', logs: '日志与记录'
}
};
const expectedTitles = expectedTitlesByLanguage[language];
if (!expectedTitles) throw new Error('Unsupported CFIP_UI_LANG: ' + language);
const commonWidths = [320, 360, 375, 390, 430, 640, 768, 1024, 1280, 1440, 1920];
const responsiveBreakpoints = [420, 600, 700, 768, 900, 1048, 1100, 1280, 1319];
const widths = [...new Set([
  ...commonWidths,
  ...responsiveBreakpoints.flatMap(width => [width - 1, width, width + 1])
])].sort((a, b) => a - b);
const shortViewports = [{ width: 320, height: 568 }, { width: 568, height: 320 }];
const themes = [
  { id: 'bootstrap-default-light', media: 'bootstrap', theme: 'bootstrap', colorScheme: 'light', darkMode: 'false' },
  { id: 'bootstrap-default-dark', media: 'bootstrap', theme: 'bootstrap', colorScheme: 'dark', darkMode: 'true' },
  { id: 'bootstrap-light', media: 'bootstrap', theme: 'bootstrap-light', colorScheme: 'light', darkMode: 'false' },
  { id: 'bootstrap-dark', media: 'bootstrap', theme: 'bootstrap-dark', colorScheme: 'dark', darkMode: 'true' },
  { id: 'aurora-light', media: 'aurora', theme: 'aurora', colorScheme: 'light', darkMode: 'false', auroraMode: 'light' },
  { id: 'aurora-dark', media: 'aurora', theme: 'aurora', colorScheme: 'dark', darkMode: 'true', auroraMode: 'dark' }
];
const report = {
  schemaVersion: 1,
  sha: process.env.GITHUB_SHA || process.env.CFIP_UI_SHA || 'unknown',
  environment: 'real OpenWrt 24.10.8 rootfs with uhttpd/rpcd/LuCI; Chromium Playwright',
  method: `initial views, common widths and adjacent values for CSS breakpoints, short portrait and landscape viewports, ${language} locale, Bootstrap default with system light/dark, explicit Bootstrap light/dark, and Aurora light/dark`,
  scenario,
  language,
  notCovered: ['real 200% browser zoom', 'complete 51-point interaction matrix', 'physical router', 'Material theme',
    ...(scenario === 'disposable-init-script-fixtures-installed-route-forms-only' ? [] : ['installed OpenClash and PassWall integration forms'])],
  pages, routeAliases: ['admin/services/cf_ip -> overview'], widths, shortViewports, rows: [], errors: []
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
    const overviewLabels = Array.from(document.querySelectorAll('.cfi-dashboard th.cfi-overview-label'));
    const envBadgesIntact = Array.from((main && main.querySelectorAll('.cfi-env-table .label')) || []).every(badge => {
      const range = document.createRange();
      range.selectNodeContents(badge);
      return range.getClientRects().length <= 1;
    });
    const tabMenu = document.querySelector('#tabmenu');
    const activeTab = tabMenu && tabMenu.querySelector('.active a, a.active, a[aria-current="page"]');
    const activeTabRect = activeTab && activeTab.getBoundingClientRect();
    const tabLinkMetrics = Array.from((tabMenu && tabMenu.querySelectorAll('a')) || []).map(a => {
      const rect = a.getBoundingClientRect();
      return { text: a.textContent.trim(), visible: rect.width > 0 && rect.height > 0 && rect.left >= -1 && rect.right <= innerWidth + 1 };
    });
    const links = Array.from(document.querySelectorAll('link[href],script[src]'));
    const themeLoaded = links.some(el => ((el.href || el.src || '')).includes('/luci-static/' + media + '/'));
    const truncated = Array.from((main || document).querySelectorAll('*'))
      .filter(el => {
        // Native input/textarea scrollWidth includes their internal editing area.
        // It is not a visible text-node truncation signal; assess input hitbox separately.
        if (el.tagName === 'INPUT' || el.tagName === 'TEXTAREA') return false;
        // The compact source-status table keeps its column headings in the
        // accessibility tree while visually clipping them; LuCI renders each
        // stacked mobile cell with its own data-title label.
        if (el.closest('.cfi-source-status-table > thead')) return false;
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
      height: innerHeight,
      scrollWidth: root.scrollWidth,
      overflow: root.scrollWidth > innerWidth + 1,
      mainLength: text.length,
      loading: /Loading view|加载视图/.test(text),
      hasMain: !!main,
      themeLoaded,
      darkMode: root.getAttribute('data-darkmode'),
      overviewLabelCount: overviewLabels.length,
      envBadgesIntact,
      overviewLabelSeparator: overviewLabels.length ? getComputedStyle(overviewLabels[0], '::after').content : null,
      overviewLabelGap: overviewLabels.length ? parseFloat(getComputedStyle(overviewLabels[0], '::after').marginRight) : null,
      overviewDuplicatedMobileLabels: overviewLabels.reduce((count, label) => count + (label.nextElementSibling && label.nextElementSibling.hasAttribute('data-title') ? 1 : 0), 0),
      activeTabText: activeTab ? activeTab.textContent.trim() : null,
      activeTabVisible: activeTab ? activeTabRect.left >= -1 && activeTabRect.right <= innerWidth + 1 : false,
      truncated,
      tabLinks: tabLinkMetrics.length,
      visibleTabLinks: tabLinkMetrics.filter(link => link.visible).length,
      tabLinkMetrics
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
      shell("uci set luci.main.mediaurlbase='/luci-static/" + theme.media + "'; uci set luci.main.theme='" + theme.theme + "'; uci commit luci; rm -rf /tmp/luci-indexcache* /tmp/luci-modulecache*; /etc/init.d/uhttpd restart >/dev/null 2>&1");
      await new Promise(resolve => setTimeout(resolve, 1200));
      const context = await browser.newContext({ viewport: { width: 1280, height: 900 }, colorScheme: theme.colorScheme });
      if (theme.auroraMode) await context.addInitScript(mode => localStorage.setItem('aurora.theme', mode), theme.auroraMode);
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
            const integrationInstalled = optionalPages.has(name)
              ? shell("if [ -x /etc/init.d/" + name + " ]; then printf yes; else printf no; fi") === 'yes'
              : null;
            let metrics = null;
            let navigationError = null;
            let routeIdentity = null;
            let screenshotFile = path.join(output, theme.id + '-' + width + '-' + name + '.png');
            try {
              await page.goto(base + '/cgi-bin/luci/admin/services/cf_ip/' + name, { waitUntil: 'domcontentloaded', timeout: 30000 });
              await page.waitForFunction(() => {
                const m = document.querySelector('#maincontent');
                return m && m.innerText.trim().length > 20 && !/Loading view|加载视图/.test(m.innerText);
              }, null, { timeout: 20000 });
              await page.waitForTimeout(550);
              routeIdentity = await page.evaluate(() => {
                const main = document.querySelector('#maincontent');
                const links = Array.from((main || document).querySelectorAll('a[href]'));
                const path = location.pathname.replace(/\/+$/, '');
                const registered = links.some(link => {
                  try { return new URL(link.href, location.href).pathname.replace(/\/+$/, '') === path; }
                  catch (_) { return false; }
                });
                const heading = main && main.querySelector('.view h2, h2[name="content"], h2');
                return { registered, heading: heading ? heading.textContent.trim() : '', url: path };
              });
              metrics = await measure(page, theme);
              const absentOptionalRoute = optionalPages.has(name) && integrationInstalled === false &&
                !routeIdentity.registered && routeIdentity.heading === expectedTitles.overview;
              if (absentOptionalRoute)
                screenshotFile = path.join(output, theme.id + '-' + width + '-' + name + '-route-unavailable.png');
              await page.screenshot({ path: screenshotFile, fullPage: true, animations: 'disabled' });
            } catch (error) {
              navigationError = error.message;
            } finally {
              page.off('console', listener);
              page.off('pageerror', exception);
            }
            const failures = [];
            if (navigationError) failures.push('navigation-or-render: ' + navigationError);
            const absentOptionalRoute = routeIdentity && optionalPages.has(name) && integrationInstalled === false &&
              !routeIdentity.registered && routeIdentity.heading === expectedTitles.overview;
            if (routeIdentity && !absentOptionalRoute) {
              if (!routeIdentity.registered) failures.push('route-not-registered');
              if (routeIdentity.heading !== expectedTitles[name]) failures.push('wrong-view-heading: ' + routeIdentity.heading);
            }
            if (metrics) {
              if (!metrics.hasMain || metrics.mainLength < 20 || metrics.loading) failures.push('blank-or-loading-view');
              if (!metrics.themeLoaded) failures.push('theme-assets-not-loaded');
              if (metrics.overflow) failures.push('horizontal-overflow');
              if (metrics.truncated.length) failures.push('truncated-non-dropdown-text');
              if (!metrics.activeTabVisible) failures.push('active-tab-outside-visible-strip');
              if (metrics.visibleTabLinks !== metrics.tabLinks) failures.push('route-tabs-clipped-or-hidden');
              if (name === 'overview' && !metrics.envBadgesIntact) failures.push('environment-badge-wrapped');
              if (metrics.darkMode !== theme.darkMode)
                failures.push('theme-dark-mode-mismatch: expected ' + theme.darkMode + ', got ' + metrics.darkMode);
              if (name === 'overview' && width <= 600) {
                if (metrics.overviewLabelSeparator !== '":"') failures.push('overview-mobile-label-separator-missing');
                if (!(metrics.overviewLabelGap >= 2)) failures.push('overview-mobile-label-gap-missing');
                if (metrics.overviewDuplicatedMobileLabels) failures.push('overview-mobile-duplicate-labels');
              }
            }
            if (consoleErrors.length) failures.push('console-errors');
            const result = failures.length ? 'FAIL' : (absentOptionalRoute ? 'N/A' : 'PASS');
            const row = {
              theme: theme.id, language, width, page: name, result, failures, metrics, routeIdentity,
              integrationInstalled,
              screenshot: path.basename(screenshotFile),
              nAReason: absentOptionalRoute ? 'Optional LuCI route is not registered because its proxy integration is not installed; the direct URL falls back to Overview.' : undefined,
              consoleErrors: consoleErrors.slice(0, 6)
            };
            report.rows.push(row);
            if (failures.length) report.errors.push({ theme: theme.id, width, page: name, failures, navigationError, consoleErrors: consoleErrors.slice(0, 6) });
            console.log(row.result + ' ' + theme.id + ' ' + width + ' ' + name + (failures.length ? ' -- ' + failures.join(', ') : (absentOptionalRoute ? ' -- optional route not registered' : '')));
            write();
          }
        }
        for (const viewport of shortViewports) {
          await page.setViewportSize(viewport);
          for (const name of pages) {
            const consoleErrors = [];
            const listener = message => { if (message.type() === 'error') consoleErrors.push(message.text()); };
            const exception = error => consoleErrors.push('PAGE_ERROR ' + error.message);
            page.on('console', listener);
            page.on('pageerror', exception);
            const integrationInstalled = optionalPages.has(name)
              ? shell("if [ -x /etc/init.d/" + name + " ]; then printf yes; else printf no; fi") === 'yes'
              : null;
            let metrics = null;
            let navigationError = null;
            let routeIdentity = null;
            let screenshotFile = path.join(output, theme.id + '-' + viewport.width + 'x' + viewport.height + '-' + name + '.png');
            try {
              await page.goto(base + '/cgi-bin/luci/admin/services/cf_ip/' + name, { waitUntil: 'domcontentloaded', timeout: 30000 });
              await page.waitForFunction(() => {
                const m = document.querySelector('#maincontent');
                return m && m.innerText.trim().length > 20 && !/Loading view|加载视图/.test(m.innerText);
              }, null, { timeout: 20000 });
              await page.waitForTimeout(550);
              routeIdentity = await page.evaluate(() => {
                const main = document.querySelector('#maincontent');
                const links = Array.from((main || document).querySelectorAll('a[href]'));
                const path = location.pathname.replace(/\/+$/, '');
                const registered = links.some(link => {
                  try { return new URL(link.href, location.href).pathname.replace(/\/+$/, '') === path; }
                  catch (_) { return false; }
                });
                const heading = main && main.querySelector('.view h2, h2[name="content"], h2');
                return { registered, heading: heading ? heading.textContent.trim() : '', url: path };
              });
              metrics = await measure(page, theme);
              const absentOptionalRoute = optionalPages.has(name) && integrationInstalled === false &&
                !routeIdentity.registered && routeIdentity.heading === expectedTitles.overview;
              if (absentOptionalRoute)
                screenshotFile = path.join(output, theme.id + '-' + viewport.width + 'x' + viewport.height + '-' + name + '-route-unavailable.png');
              await page.screenshot({ path: screenshotFile, fullPage: true, animations: 'disabled' });
            } catch (error) {
              navigationError = error.message;
            } finally {
              page.off('console', listener);
              page.off('pageerror', exception);
            }
            const failures = [];
            if (navigationError) failures.push('navigation-or-render: ' + navigationError);
            const absentOptionalRoute = routeIdentity && optionalPages.has(name) && integrationInstalled === false &&
              !routeIdentity.registered && routeIdentity.heading === expectedTitles.overview;
            if (routeIdentity && !absentOptionalRoute) {
              if (!routeIdentity.registered) failures.push('route-not-registered');
              if (routeIdentity.heading !== expectedTitles[name]) failures.push('wrong-view-heading: ' + routeIdentity.heading);
            }
            if (metrics) {
              if (!metrics.hasMain || metrics.mainLength < 20 || metrics.loading) failures.push('blank-or-loading-view');
              if (!metrics.themeLoaded) failures.push('theme-assets-not-loaded');
              if (metrics.overflow) failures.push('horizontal-overflow');
              if (metrics.truncated.length) failures.push('truncated-non-dropdown-text');
              if (!metrics.activeTabVisible) failures.push('active-tab-outside-visible-strip');
              if (name === 'overview' && !metrics.envBadgesIntact) failures.push('environment-badge-wrapped');
              if (metrics.darkMode !== theme.darkMode)
                failures.push('theme-dark-mode-mismatch: expected ' + theme.darkMode + ', got ' + metrics.darkMode);
            }
            if (consoleErrors.length) failures.push('console-errors');
            const result = failures.length ? 'FAIL' : (absentOptionalRoute ? 'N/A' : 'PASS');
            const row = {
              theme: theme.id, language, width: viewport.width, height: viewport.height, page: name,
              result, failures, metrics, routeIdentity, integrationInstalled,
              screenshot: path.basename(screenshotFile),
              nAReason: absentOptionalRoute ? 'Optional LuCI route is not registered because its proxy integration is not installed; the direct URL falls back to Overview.' : undefined,
              consoleErrors: consoleErrors.slice(0, 6)
            };
            report.rows.push(row);
            if (failures.length) report.errors.push({ theme: theme.id, width: viewport.width, height: viewport.height, page: name, failures, navigationError, consoleErrors: consoleErrors.slice(0, 6) });
            console.log(row.result + ' ' + theme.id + ' ' + viewport.width + 'x' + viewport.height + ' ' + name + (failures.length ? ' -- ' + failures.join(', ') : (absentOptionalRoute ? ' -- optional route not registered' : '')));
            write();
          }
        }
        const aliasWidth = 1280;
        await page.setViewportSize({ width: aliasWidth, height: 900 });
        let aliasError = null;
        let aliasHeading = '';
        let aliasMetrics = null;
        const aliasScreenshot = path.join(output, theme.id + '-' + aliasWidth + '-root-alias.png');
        try {
          await page.goto(base + '/cgi-bin/luci/admin/services/cf_ip', { waitUntil: 'domcontentloaded', timeout: 30000 });
          await page.waitForFunction(() => {
            const m = document.querySelector('#maincontent');
            return m && m.innerText.trim().length > 20 && !/Loading view|加载视图/.test(m.innerText);
          }, null, { timeout: 20000 });
          await page.waitForTimeout(550);
          aliasHeading = await page.locator('#maincontent h2').first().textContent().then(value => value.trim());
          aliasMetrics = await measure(page, theme);
          await page.screenshot({ path: aliasScreenshot, fullPage: true, animations: 'disabled' });
        } catch (error) {
          aliasError = error.message;
        }
        const aliasFailures = [];
        if (aliasError) aliasFailures.push('navigation-or-render: ' + aliasError);
        if (aliasHeading !== expectedTitles.overview) aliasFailures.push('root-alias-not-overview: ' + aliasHeading);
        if (!aliasMetrics || !aliasMetrics.hasMain || aliasMetrics.overflow || !aliasMetrics.activeTabVisible)
          aliasFailures.push('root-alias-layout-check-failed');
        if (aliasMetrics && aliasMetrics.darkMode !== theme.darkMode)
          aliasFailures.push('theme-dark-mode-mismatch: expected ' + theme.darkMode + ', got ' + aliasMetrics.darkMode);
        const aliasRow = {
          theme: theme.id, language, width: aliasWidth, page: 'root-alias',
          route: 'admin/services/cf_ip', expectedView: 'overview', heading: aliasHeading,
          result: aliasFailures.length ? 'FAIL' : 'PASS', failures: aliasFailures,
          metrics: aliasMetrics, screenshot: path.basename(aliasScreenshot), navigationError: aliasError
        };
        report.rows.push(aliasRow);
        if (aliasFailures.length) report.errors.push({ theme: theme.id, width: aliasWidth, page: 'root-alias', failures: aliasFailures, navigationError: aliasError });
        console.log(aliasRow.result + ' ' + theme.id + ' ' + aliasWidth + ' root-alias' + (aliasFailures.length ? ' -- ' + aliasFailures.join(', ') : ''));
        write();
      } finally {
        await context.close();
      }
    }
  } finally {
    await browser.close();
    write();
  }
  console.log('VISUAL_MATRIX ' + JSON.stringify({ total: report.rows.length, passed: report.rows.filter(r => r.result === 'PASS').length, notApplicable: report.rows.filter(r => r.result === 'N/A').length, failed: report.errors.length }));
if (report.rows.length !== themes.length * ((widths.length + shortViewports.length) * pages.length + 1) || report.errors.length) process.exitCode = 1;
})().catch(error => {
  report.errors.push({ fatal: error.stack || error.message });
  write();
  console.error('VISUAL_MATRIX_FATAL ' + (error.stack || error.message));
  process.exitCode = 1;
});
