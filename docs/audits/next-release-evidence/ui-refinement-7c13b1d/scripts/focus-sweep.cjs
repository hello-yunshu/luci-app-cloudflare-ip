'use strict';
const fs = require('fs');
const path = require('path');
const { execFileSync } = require('child_process');
const { chromium } = require('playwright');

const container = process.argv[2];
const base = process.argv[3];
const out = '/tmp/cfip-evidence/focus-sweep';
fs.mkdirSync(out, { recursive: true });
const sh = c => execFileSync('docker', ['exec', container, 'sh', '-c', c], { encoding: 'utf8' });
const pages = ['overview', 'settings', 'sources', 'intelligence', 'openclash', 'passwall', 'advanced', 'logs'];
const themes = { bootstrap: { media: '/luci-static/bootstrap', storage: null }, 'aurora-dark': { media: '/luci-static/aurora', storage: 'dark' } };

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
  const ctx = await browser.newContext({ viewport: { width: 1280, height: 900 } });
  const page = await ctx.newPage();
  const results = [];
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
        await page.screenshot({ path: path.join(out, `${theme}-${p}-normal.png`) });
        const controls = await page.evaluate(() => {
          const sel = 'a[href], button, input:not([type=hidden]), select, textarea, [tabindex]:not([tabindex="-1"])';
          const main = document.querySelector('#maincontent');
          const all = [...main.querySelectorAll(sel)];
          all.forEach((e, i) => e.setAttribute('data-cfi-audit-id', String(i)));
          return all.map((e, i) => {
            const r = e.getBoundingClientRect(); const s = getComputedStyle(e);
            const visible = r.width > 0 && r.height > 0 && s.display !== 'none' && s.visibility !== 'hidden' && !e.disabled;
            return { i, visible, tag: e.tagName.toLowerCase(), text: (e.innerText || e.value || e.getAttribute('name') || '').trim().slice(0, 32) };
          }).filter(x => x.visible);
        });
        const tested = [];
        await page.evaluate(() => {
          const main = document.querySelector('#maincontent');
          const first = main.querySelector('[data-cfi-audit-id]');
          if (first) first.focus();
        });
        const firstRec = await page.evaluate(() => {
          const e = document.activeElement; const s = getComputedStyle(e);
          return { tag: e.tagName.toLowerCase(), text: (e.innerText || e.value || '').trim().slice(0, 32), focus: (s.outlineStyle !== 'none' && parseFloat(s.outlineWidth) > 0) || (s.boxShadow && s.boxShadow !== 'none'), method: 'programmatic' };
        });
        tested.push(firstRec);
        for (let i = 1; i < controls.length; i++) {
          await page.keyboard.press('Tab');
          await page.waitForTimeout(300);
          tested.push(await page.evaluate(() => {
            const e = document.activeElement; const s = getComputedStyle(e);
            const r = e.getBoundingClientRect();
            return {
              tag: e.tagName.toLowerCase(),
              text: (e.innerText || e.value || '').trim().slice(0, 32),
              focus: (s.outlineStyle !== 'none' && parseFloat(s.outlineWidth) > 0) || (s.boxShadow && s.boxShadow !== 'none'),
              visible: r.width > 0 && r.height > 0,
              method: 'tab'
            };
          }));
        }
        for (const c of controls) {
          const target = page.locator(`[data-cfi-audit-id="${c.i}"]`);
          try { await target.hover({ timeout: 2000 }); tested.find(t => t.text === c.text).hover = true; } catch (e) { }
        }
        const tabbed = tested.filter(x => x.method === 'tab' && x.tag !== 'body');
        const focusPass = tabbed.filter(x => x.focus === true).length;
        const hoverPass = tested.filter(x => x.hover === true).length;
        const focusFail = tabbed.filter(x => x.focus === false).length;
        await page.locator('#maincontent').screenshot({ path: path.join(out, `${theme}-${p}-focused.png`) }).catch(() => {});
        results.push({ theme, page: p, controls: controls.length, focusPass, hoverPass, focusFail, tested });
      }
    }
  } finally {
    await browser.close();
  }
  fs.writeFileSync(path.join(out, 'focus-sweep.json'), JSON.stringify({ container, base, results }, null, 2) + '\n');
  console.log(results.map(r => `${r.theme}/${r.page}: controls=${r.controls} focusPass=${r.focusPass} hoverPass=${r.hoverPass} focusFail=${r.focusFail}`).join('\n'));
})().catch(e => { console.error(e); process.exit(1); });
