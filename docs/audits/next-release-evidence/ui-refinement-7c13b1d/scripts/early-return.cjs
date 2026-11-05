'use strict';
const fs = require('fs');
const path = require('path');
const { execFileSync } = require('child_process');
const { chromium } = require('playwright');

const base = process.argv[2];
const container = process.argv[3];
const label = process.argv[4];
const out = path.join('/tmp/cfip-evidence/early-return', label);
fs.mkdirSync(out, { recursive: true });

const sh = (cmd) => execFileSync('docker', ['exec', container, 'sh', '-c', cmd], { encoding: 'utf8' });

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

async function waitState(page, text) {
  try {
    await page.locator('.cfi-empty-state').waitFor({ timeout: 30000 });
  } catch (e) {
    console.error('NO EMPTY STATE', page.url(), (await page.locator('#maincontent').innerText()).slice(0, 180));
    throw e;
  }
  if (text) await page.locator('.cfi-empty-state', { hasText: text }).waitFor({ timeout: 30000 });
}

async function capture(page, pageName, state, viewport) {
  const file = path.join(out, `${pageName}-${state}-${viewport}.png`);
  await page.setViewportSize(viewport === '375' ? { width: 375, height: 900 } : { width: 1280, height: 900 });
  await page.goto(base + '/cgi-bin/luci/admin/services/cf_ip/' + pageName, { waitUntil: 'domcontentloaded' });
  await waitState(page);
  await page.waitForTimeout(400);
  await page.screenshot({ path: file, fullPage: false });
  const metrics = await page.evaluate(() => {
    const box = document.querySelector('.cfi-empty-state');
    const cs = getComputedStyle(box);
    return {
      cssLink: !!document.getElementById('cfi-shared-css'),
      borderStyle: cs.borderTopStyle,
      borderWidth: cs.borderTopWidth,
      borderRadius: cs.borderTopLeftRadius,
      backgroundColor: cs.backgroundColor,
      padding: cs.paddingTop,
      footer: document.querySelectorAll('.ys-tool-footer').length,
      overflow: document.documentElement.scrollWidth > innerWidth,
      heading: (box.querySelector('h3') || {}).textContent || '',
      text: (box.innerText || '').slice(0, 160)
    };
  });
  return { page: pageName, state, viewport: viewport + 'x900', file, ...metrics };
}

(async () => {
  const browser = await chromium.launch({ headless: true });
  const ctx = await browser.newContext({ viewport: { width: 1280, height: 900 } });
  const page = await ctx.newPage();
  const results = [];
  try {
    await login(page);
    sh('printf "#!/bin/sh\\nexit 1\\n" > /etc/init.d/openclash; printf "#!/bin/sh\\nexit 1\\n" > /etc/init.d/passwall; chmod +x /etc/init.d/openclash /etc/init.d/passwall; rm -rf /tmp/luci-indexcache* /tmp/luci-modulecache');
    await page.goto(base + '/cgi-bin/luci/admin/services/cf_ip/openclash', { waitUntil: 'domcontentloaded' });
    await page.locator('.cfi-form-map').waitFor({ timeout: 30000 });
    await page.waitForTimeout(800);
    sh('rm -f /etc/init.d/openclash /etc/init.d/passwall');
    for (const p of ['openclash', 'passwall']) {
      for (const vp of ['1280', '375']) results.push(await capture(page, p, 'not-installed', vp));
    }

    sh('mv /usr/libexec/rpcd/cf_ip /tmp/cf_ip.disabled; /etc/init.d/rpcd restart >/dev/null 2>&1');
    await page.waitForTimeout(1500);
    await login(page);
    for (const p of ['openclash', 'passwall']) {
      for (const vp of ['1280', '375']) results.push(await capture(page, p, 'rpc-failure', vp));
    }
  } finally {
    try { sh('if [ -f /tmp/cf_ip.disabled ]; then mv /tmp/cf_ip.disabled /usr/libexec/rpcd/cf_ip; /etc/init.d/rpcd restart >/dev/null 2>&1; fi; rm -f /etc/init.d/openclash /etc/init.d/passwall; rm -rf /tmp/luci-indexcache* /tmp/luci-modulecache'); } catch (e) { console.error('restore failed', e.message); }
    await browser.close();
  }
  fs.writeFileSync(path.join(out, 'metrics.json'), JSON.stringify({ base, container, label, results }, null, 2) + '\n');
  console.log(results.map(r => `${r.page}/${r.state}/${r.viewport}: css=${r.cssLink} border=${r.borderStyle}/${r.borderWidth} radius=${r.borderRadius} bg=${r.backgroundColor} footer=${r.footer} overflow=${r.overflow}`).join('\n'));
})().catch(e => { console.error(e); process.exit(1); });
