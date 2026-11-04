'use strict';

/*
 * Phase F: real browser page zoom (Chrome settings, not CDP emulation)
 * and real zh_cn LuCI rendering.
 */

const fs = require('fs');
const path = require('path');
const { execFileSync } = require('child_process');
const { chromium } = require('playwright-core');

const BASE = process.env.CFIP_UI_BASE || 'http://127.0.0.1:18080';
const CONTAINER = process.env.CFIP_UI_CONTAINER || 'cfip-ui-phasef';
const PASSWORD = process.env.CFIP_UI_PASSWORD || 'cfip-gate';
const OUT = process.env.CFIP_PHASE_F_OUT || path.resolve(__dirname, '../zoom-zh');
const PROFILE = '/tmp/cfip-chrome-zoom-profile';
const PAGES = ['overview', 'settings', 'sources', 'intelligence', 'openclash', 'passwall', 'advanced', 'logs'];
const ZOOMS = [1.25, 1.5, 2];

fs.mkdirSync(OUT, { recursive: true });
function sh(command) {
  return execFileSync('docker', ['exec', CONTAINER, 'sh', '-c', command], { encoding: 'utf8' }).trim();
}
function sleep(ms) { return new Promise(resolve => setTimeout(resolve, ms)); }

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

async function setChromeZoom(page, factor) {
  await page.goto('chrome://settings/appearance', { waitUntil: 'domcontentloaded' });
  await page.waitForTimeout(1800);
  const pct = Math.round(factor * 100) + '%';
  await page.locator('option').filter({ hasText: pct }).first().evaluate(el => {
    const select = el.closest('select');
    select.value = el.value;
    select.dispatchEvent(new Event('change', { bubbles: true }));
  });
  await page.waitForTimeout(800);
}

async function pageMetrics(page) {
  return page.evaluate(() => {
    const focusables = [...document.querySelectorAll('a[href], button, input:not([type=hidden]), select, textarea, [tabindex]:not([tabindex="-1"])')]
      .filter(el => {
        const r = el.getBoundingClientRect();
        const s = getComputedStyle(el);
        return r.width > 0 && r.height > 0 && s.display !== 'none' && s.visibility !== 'hidden' && !el.disabled;
      });
    const clipped = [...document.querySelectorAll('#maincontent *')]
      .filter(el => el.scrollWidth > el.clientWidth + 1 && el.clientWidth > 0)
      .slice(0, 20)
      .map(el => ({
        tag: el.tagName,
        cls: String(el.className).slice(0, 50),
        text: (el.innerText || '').trim().slice(0, 40),
        html: el.outerHTML.slice(0, 160),
        overflowX: getComputedStyle(el).overflowX,
        scrollable: /auto|scroll/.test(getComputedStyle(el).overflowX),
        nowrap: getComputedStyle(el).whiteSpace === 'nowrap',
        inDropdown: !!el.closest('.cbi-dropdown'),
        inTabs: !!el.closest('#maincontent .tabs, #maincontent ul.tabs, #maincontent .cbi-tabmenu')
      }));
    const trunc = [...document.querySelectorAll('#maincontent *')]
      .filter(el => {
        const s = getComputedStyle(el);
        return s.whiteSpace === 'nowrap' && el.scrollWidth > el.clientWidth + 1 && el.clientWidth > 0;
      })
      .slice(0, 20)
      .map(el => ({
        tag: el.tagName,
        cls: String(el.className).slice(0, 50),
        text: (el.innerText || '').trim().slice(0, 40),
        inDropdown: !!el.closest('.cbi-dropdown'),
        overflowX: getComputedStyle(el).overflowX
      }));
    const main = document.querySelector('#maincontent');
    const title = document.querySelector('.cbi-map-title');
    return {
      innerWidth,
      innerHeight,
      dpr: devicePixelRatio,
      scrollWidth: document.documentElement.scrollWidth,
      overflowX: document.documentElement.scrollWidth > innerWidth,
      clipped,
      trunc,
      focusables: focusables.length,
      mainVisible: !!main && main.getBoundingClientRect().height > 0,
      titleVisible: !!title && title.getBoundingClientRect().height > 0
    };
  });
}

async function keyboardProbe(page) {
  const out = [];
  let reachedMainAfter = null;
  for (let i = 0; i < 80; i++) {
    await page.keyboard.press('Tab');
    await page.waitForTimeout(100);
    const tab = await page.evaluate(() => {
      const el = document.activeElement;
      const r = el.getBoundingClientRect();
      const s = getComputedStyle(el);
      const ring = (s.outlineStyle !== 'none' && parseFloat(s.outlineWidth) > 0) || (s.boxShadow && s.boxShadow !== 'none');
      return {
        tag: el.tagName,
        text: (el.innerText || el.value || el.getAttribute('aria-label') || '').trim().slice(0, 30),
        ring,
        inMain: !!(el.closest && el.closest('#maincontent')),
        inViewport: r.top >= 0 && r.bottom <= innerHeight && r.left >= 0 && r.right <= innerWidth
      };
    });
    if (!tab.inViewport) {
      await page.evaluate(() => document.activeElement.scrollIntoView({ block: 'center', inline: 'nearest' }));
      await page.waitForTimeout(100);
      tab.inViewport = await page.evaluate(() => {
        const r = document.activeElement.getBoundingClientRect();
        return r.top >= 0 && r.bottom <= innerHeight && r.left >= 0 && r.right <= innerWidth;
      });
    }
    out.push(tab);
    if (tab.inMain && reachedMainAfter === null) reachedMainAfter = i + 1;
    if (reachedMainAfter !== null && out.filter(t => t.inMain).length >= 12) break;
  }
  const mainTabs = out.filter(t => t.inMain);
  return {
    tabs: out,
    pressed: out.length,
    reachedMainAfter,
    mainTabs: mainTabs.length,
    ringMissing: mainTabs.filter(t => !t.ring).length,
    offscreenMain: mainTabs.filter(t => !t.inViewport).length,
    offscreenSidebar: out.filter(t => !t.inMain && !t.inViewport).length
  };
}

const ZH_MENU = ['概览', '设置', '候选 IP 来源', '智能优选', '高级', '日志与记录'];
const EN_RESIDUE = ['Service Control', 'Service Information', 'Environment Detection', 'Save & Apply', 'Candidate Sources', 'Runtime Path', 'Technical details', 'Reset learning state', 'Source Strategy', 'Run self-check', 'Clear Logs', 'Backup Count', 'Rill Intelligence', 'Measurement Policy', 'Adaptive Measurement', 'Live State'];
const ZH_EXPECT = {
  overview: ['概览', '服务控制', '服务信息'],
  settings: ['设置', '服务', '测速'],
  sources: ['候选来源', '候选数量预算', '自定义来源'],
  intelligence: ['Rill 智能', '测量策略', '自适应测量'],
  openclash: ['OpenClash', '配置备份'],
  passwall: ['PassWall'],
  advanced: ['高级', '脚本更新'],
  logs: ['日志与记录', '诊断', '最近日志']
};

function textAudit(text, pageName) {
  const msgidLeak = /\b_\(|%s\b|msgid/.test(text);
  const englishResidue = EN_RESIDUE.filter(word => text.includes(word));
  const menuMissing = ZH_MENU.filter(word => !text.includes(word));
  const expectMissing = (ZH_EXPECT[pageName] || []).filter(word => !text.includes(word));
  return { msgidLeak, englishResidue, menuMissing, expectMissing };
}

(async () => {
  fs.rmSync(PROFILE, { recursive: true, force: true });
  const context = await chromium.launchPersistentContext(PROFILE, {
    headless: false,
    executablePath: process.env.CHROME_BIN,
    viewport: { width: 1280, height: 900 },
    locale: 'en-US',
    args: ['--disable-breakpad', '--disable-crash-reporter']
  });
  const page = context.pages()[0] || await context.newPage();
  let pageConsole = [];
  page.on('console', message => { if (message.type() === 'error') pageConsole.push(message.text()); });
  sh("uci set luci.main.lang='en'; uci commit luci; rm -rf /tmp/luci-indexcache* /tmp/luci-modulecache; /etc/init.d/uhttpd restart >/dev/null 2>&1");
  await sleep(1200);
  await login(page);
  const report = { schemaVersion: 1, sha: process.env.CFIP_UI_SHA || '1ec2a6d', base: BASE, zoom: [], zh: [], reflow320: [] };

  for (const factor of ZOOMS) {
    await setChromeZoom(page, factor);
    for (const name of PAGES) {
      pageConsole = [];
      await page.goto(BASE + '/cgi-bin/luci/admin/services/cf_ip/' + name, { waitUntil: 'domcontentloaded' });
      await page.waitForFunction(() => {
        const t = (document.querySelector('#maincontent') || document.body).innerText;
        return t.length > 80 && !/Loading view/.test(t);
      }, null, { timeout: 60000 }).catch(() => {});
      await page.waitForTimeout(900);
      const metrics = await pageMetrics(page);
      const keyboard = await keyboardProbe(page);
      const file = path.join(OUT, `zoom-${Math.round(factor * 100)}-${name}.png`);
      await page.screenshot({ path: file });
      report.zoom.push({
        level: Math.round(factor * 100), page: name, viewportCss: [metrics.innerWidth, metrics.innerHeight], dpr: metrics.dpr,
        scrollWidth: metrics.scrollWidth, overflowX: metrics.overflowX, clipped: metrics.clipped.length, trunc: metrics.trunc.length,
        clippedDetails: metrics.clipped, truncDetails: metrics.trunc,
        focusables: metrics.focusables, pressed: keyboard.pressed, reachedMainAfter: keyboard.reachedMainAfter,
        mainTabs: keyboard.mainTabs, ringMissing: keyboard.ringMissing,
        offscreenMain: keyboard.offscreenMain, offscreenSidebar: keyboard.offscreenSidebar,
        offscreenTabs: keyboard.tabs.filter(t => !t.inViewport).map(t => ({ tag: t.tag, text: t.text, ring: t.ring, inMain: t.inMain })),
        consoleErrors: pageConsole.slice(0, 10),
        screenshot: path.relative(path.resolve(__dirname, '../..'), file)
      });
      console.log('ZOOM', Math.round(factor * 100), name, metrics.innerWidth, metrics.overflowX, metrics.clipped.length, keyboard.ringMissing, keyboard.offscreenMain, keyboard.offscreenSidebar);
    }
  }

  // 320 CSS reflow at default zoom.
  await setChromeZoom(page, 1);
  await page.setViewportSize({ width: 320, height: 900 });
  for (const name of PAGES) {
    pageConsole = [];
    await page.goto(BASE + '/cgi-bin/luci/admin/services/cf_ip/' + name, { waitUntil: 'domcontentloaded' });
    await page.waitForFunction(() => {
      const t = (document.querySelector('#maincontent') || document.body).innerText;
      return t.length > 80 && !/Loading view/.test(t);
    }, null, { timeout: 60000 }).catch(() => {});
    await page.waitForTimeout(1200);
    const metrics = await pageMetrics(page);
    const file = path.join(OUT, `reflow-320-${name}.png`);
    await page.screenshot({ path: file });
    report.reflow320.push({ page: name, innerWidth: metrics.innerWidth, scrollWidth: metrics.scrollWidth, overflowX: metrics.overflowX, clipped: metrics.clipped.length, trunc: metrics.trunc.length, clippedDetails: metrics.clipped, truncDetails: metrics.trunc, consoleErrors: pageConsole.slice(0, 10), screenshot: path.relative(path.resolve(__dirname, '../..'), file) });
    console.log('REFLOW320', name, metrics.scrollWidth, metrics.overflowX, metrics.clipped.length);
  }

  // zh_cn real rendering.
  await page.setViewportSize({ width: 1280, height: 900 });
  sh("uci set luci.main.lang='zh_cn'; uci commit luci; rm -rf /tmp/luci-indexcache* /tmp/luci-modulecache; /etc/init.d/uhttpd restart >/dev/null 2>&1");
  await sleep(1500);
  for (const width of [375, 1280]) {
    await page.setViewportSize({ width, height: width === 375 ? 900 : 900 });
    for (const name of PAGES) {
      pageConsole = [];
      await page.goto(BASE + '/cgi-bin/luci/admin/services/cf_ip/' + name, { waitUntil: 'domcontentloaded' });
      await page.waitForFunction(() => {
        const t = (document.querySelector('#maincontent') || document.body).innerText;
        return t.length > 80 && !/Loading view|加载视图/.test(t);
      }, null, { timeout: 60000 }).catch(() => {});
      await page.waitForTimeout(1500);
      const text = await page.locator('#maincontent').innerText();
      const audit = textAudit(text, name);
      const metrics = await pageMetrics(page);
      const file = path.join(OUT, `zh-${width}-${name}.png`);
      await page.screenshot({ path: file });
      report.zh.push({ width, page: name, ...audit, overflowX: metrics.overflowX, clipped: metrics.clipped.length, trunc: metrics.trunc.length, clippedDetails: metrics.clipped, truncDetails: metrics.trunc, consoleErrors: pageConsole.slice(0, 10), screenshot: path.relative(path.resolve(__dirname, '../..'), file) });
      console.log('ZH', width, name, JSON.stringify(audit), metrics.overflowX, metrics.clipped.length);
    }
  }

  const failures = [];
  const hardClip = details => (details || []).filter(d => d.nowrap && !d.scrollable && d.overflowX !== 'visible' && !d.inDropdown);
  for (const z of report.zoom) {
    if (z.overflowX) failures.push(`zoom ${z.level} ${z.page}: page horizontal overflow (${z.scrollWidth} > ${z.viewportCss[0]})`);
    if (z.truncDetails.some(t => !t.inDropdown)) failures.push(`zoom ${z.level} ${z.page}: non-dropdown nowrap text truncated`);
    if (z.ringMissing) failures.push(`zoom ${z.level} ${z.page}: ${z.ringMissing} focused controls without a visible ring`);
    if (z.offscreenMain) failures.push(`zoom ${z.level} ${z.page}: ${z.offscreenMain} focused main-content controls stayed offscreen`);
    if (z.reachedMainAfter === null) failures.push(`zoom ${z.level} ${z.page}: Tab traversal never reached main content`);
    if (hardClip(z.clippedDetails).length) failures.push(`zoom ${z.level} ${z.page}: non-scrollable clipped element`);
    if ((z.consoleErrors || []).length) failures.push(`zoom ${z.level} ${z.page}: console errors`);
  }
  for (const r of report.reflow320) {
    if (r.overflowX) failures.push(`reflow320 ${r.page}: page horizontal overflow (${r.scrollWidth} > ${r.innerWidth})`);
    if (r.truncDetails.some(t => !t.inDropdown)) failures.push(`reflow320 ${r.page}: non-dropdown nowrap text truncated`);
    if (hardClip(r.clippedDetails).length) failures.push(`reflow320 ${r.page}: non-scrollable clipped element`);
    if ((r.consoleErrors || []).length) failures.push(`reflow320 ${r.page}: console errors`);
  }
  for (const z of report.zh) {
    if (z.msgidLeak) failures.push(`zh ${z.width} ${z.page}: msgid leak`);
    if (z.englishResidue.length) failures.push(`zh ${z.width} ${z.page}: english residue ${z.englishResidue.join(',')}`);
    if (z.menuMissing.length) failures.push(`zh ${z.width} ${z.page}: menu missing ${z.menuMissing.join(',')}`);
    if (z.expectMissing.length) failures.push(`zh ${z.width} ${z.page}: expected text missing ${z.expectMissing.join(',')}`);
    if (z.overflowX) failures.push(`zh ${z.width} ${z.page}: page horizontal overflow`);
    if (z.truncDetails.some(t => !t.inDropdown)) failures.push(`zh ${z.width} ${z.page}: non-dropdown nowrap text truncated`);
    if (hardClip(z.clippedDetails).length) failures.push(`zh ${z.width} ${z.page}: non-scrollable clipped element`);
    if ((z.consoleErrors || []).length) failures.push(`zh ${z.width} ${z.page}: console errors`);
  }
  report.assertions = { passed: failures.length === 0, failed: failures.length, failures };
  fs.writeFileSync(path.join(OUT, 'zoom-zh.json'), JSON.stringify(report, null, 2) + '\n');
  await context.close();
  if (failures.length) {
    console.error(failures.join('\n'));
    process.exit(1);
  }
})().catch(error => { console.error(error); process.exit(1); });
