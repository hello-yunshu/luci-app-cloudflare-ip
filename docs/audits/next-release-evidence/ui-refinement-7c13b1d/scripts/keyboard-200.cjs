'use strict';
const fs = require('fs');
const path = require('path');
const { execFileSync } = require('child_process');
const { chromium } = require('playwright');

const container = process.argv[2];
const base = process.argv[3];
const out = '/tmp/cfip-evidence/keyboard-200';
fs.mkdirSync(out, { recursive: true });
const sh = c => execFileSync('docker', ['exec', container, 'sh', '-c', c], { encoding: 'utf8' });
const pages = ['overview', 'settings', 'sources', 'intelligence', 'openclash', 'passwall', 'advanced', 'logs'];
const themes = {
  bootstrap: { media: '/luci-static/bootstrap', storage: null },
  'aurora-dark': { media: '/luci-static/aurora', storage: 'dark' }
};

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
  const ctx = await browser.newContext({ viewport: { width: 640, height: 900 } });
  const page = await ctx.newPage();
  const report = [];
  try {
    await login(page);
    for (const theme of Object.keys(themes)) {
      const t = themes[theme];
      sh(`uci set luci.main.mediaurlbase='${t.media}'; uci commit luci; rm -rf /tmp/luci-indexcache* /tmp/luci-modulecache; /etc/init.d/uhttpd restart >/dev/null 2>&1`);
      await page.waitForTimeout(700);
      if (t.storage) {
        await page.goto(base + '/cgi-bin/luci/', { waitUntil: 'domcontentloaded' });
        await page.evaluate(v => localStorage.setItem('aurora.theme', v), t.storage);
      }
      for (const p of pages) {
        await page.goto(base + '/cgi-bin/luci/admin/services/cf_ip/' + p, { waitUntil: 'domcontentloaded' });
        await page.waitForTimeout(1200);
        await page.evaluate(() => window.scrollTo(0, 0));
        const before = path.join(out, `${theme}-640x900-${p}-initial.png`);
        await page.screenshot({ path: before });
        const focusables = await page.evaluate(() => {
          const sel = 'a[href], button, input:not([type=hidden]), select, textarea, [tabindex]:not([tabindex="-1"])';
          const main = document.querySelector('#maincontent');
          return [...main.querySelectorAll(sel)].filter(e => {
            const r = e.getBoundingClientRect(); const s = getComputedStyle(e);
            return r.width > 0 && r.height > 0 && s.display !== 'none' && s.visibility !== 'hidden' && !e.disabled;
          }).length;
        });
        await page.evaluate(() => {
          const main = document.querySelector('#maincontent');
          const el = main.querySelector('a[href], button, input:not([type=hidden]), select, textarea, [tabindex]:not([tabindex="-1"])');
          if (el) el.focus();
        });
        const tabs = [];
        const maxTabs = Math.min(12, focusables);
        for (let i = 0; i < maxTabs; i++) {
          await page.keyboard.press('Tab');
          await page.waitForTimeout(250);
          let tab = await page.evaluate(() => {
            const e = document.activeElement;
            const r = e.getBoundingClientRect();
            const s = getComputedStyle(e);
            const ring = (s.outlineStyle !== 'none' && parseFloat(s.outlineWidth) > 0) ||
              (s.boxShadow && s.boxShadow !== 'none') ||
              (s.textDecorationLine && s.textDecorationLine.includes('underline'));
            return {
              tag: e.tagName.toLowerCase(),
              text: (e.innerText || e.value || e.getAttribute('aria-label') || e.getAttribute('name') || '').trim().slice(0, 40),
              name: e.getAttribute('name') || '',
              inViewport: r.top >= 0 && r.bottom <= innerHeight && r.left >= 0 && r.right <= innerWidth,
              ring
            };
          });
          if (!tab.inViewport) {
            await page.evaluate(() => document.activeElement.scrollIntoView({ block: 'center', inline: 'nearest' }));
            await page.waitForTimeout(250);
            const reachable = await page.evaluate(() => {
              const r = document.activeElement.getBoundingClientRect();
              return r.top >= 0 && r.bottom <= innerHeight && r.left >= 0 && r.right <= innerWidth;
            });
            tab.reachableAfterScroll = reachable;
            tab.inViewport = reachable;
          } else {
            tab.reachableAfterScroll = true;
          }
          tabs.push(tab);
        }
        const unique = new Set(tabs.map(t => t.tag + '|' + t.name + '|' + t.text)).size;
        const noRing = tabs.filter(t => !t.ring).length;
        const offscreen = tabs.filter(t => !t.inViewport).length;
        const mid = path.join(out, `${theme}-640x900-${p}-focus.png`);
        await page.screenshot({ path: mid });
        const bottom = await page.evaluate(() => {
          window.scrollTo(0, document.body.scrollHeight);
          return new Promise(resolve => setTimeout(() => {
            const actions = document.querySelector('.cbi-page-actions');
            const hasActions = !!actions;
            const footer = document.querySelector('.ys-tool-footer');
            const ar = actions ? actions.getBoundingClientRect() : null;
            const fr = footer ? footer.getBoundingClientRect() : null;
            resolve({
              scrollY: window.scrollY,
              scrollHeight: document.body.scrollHeight,
              hasActions,
              actionsVisible: !hasActions || (!!ar && ar.bottom > 0 && ar.top < innerHeight),
              footerVisible: !!fr && fr.bottom > 0 && fr.top < innerHeight,
              overflow: document.documentElement.scrollWidth > innerWidth,
              scrollWidth: document.documentElement.scrollWidth
            });
          }, 600));
        });
        await page.screenshot({ path: path.join(out, `${theme}-640x900-${p}-bottom.png`) });
        const pass = focusables >= 5 && unique >= 5 && noRing === 0 && offscreen === 0 &&
          bottom.actionsVisible && bottom.footerVisible && !bottom.overflow;
        report.push({ theme, page: p, viewport: '640x900 (1280@200%)', focusables, tabsTested: tabs.length, unique, noRing, offscreen, bottom, pass, tabs });
      }
    }
  } finally {
    await browser.close();
  }
  fs.writeFileSync(path.join(out, 'keyboard-200.json'), JSON.stringify({ container, base, report }, null, 2) + '\n');
  console.log(report.map(r => `${r.theme}/${r.page}: pass=${r.pass} focus=${r.focusables} uniq=${r.unique} noRing=${r.noRing} offscreen=${r.offscreen} actions=${r.bottom.actionsVisible} footer=${r.bottom.footerVisible} overflow=${r.bottom.overflow}`).join('\n'));
})().catch(e => { console.error(e); process.exit(1); });
