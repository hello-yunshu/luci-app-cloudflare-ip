'use strict';
const fs = require('fs');
const path = require('path');
const { execFileSync } = require('child_process');
const { chromium } = require('playwright');

const container = process.argv[2];
const base = process.argv[3];
const label = process.argv[4] || 'after';
const out = path.join('/tmp/cfip-evidence/contrast', label);
fs.mkdirSync(out, { recursive: true });
const sh = c => execFileSync('docker', ['exec', container, 'sh', '-c', c], { encoding: 'utf8' });

const themes = {
  bootstrap: { media: '/luci-static/bootstrap', storage: null },
  'aurora-light': { media: '/luci-static/aurora', storage: 'light' },
  'aurora-dark': { media: '/luci-static/aurora', storage: 'dark' }
};
const pages = ['overview', 'settings', 'sources', 'intelligence', 'openclash', 'passwall', 'advanced', 'logs'];

async function setTheme(page, name) {
  const t = themes[name];
  sh(`uci set luci.main.mediaurlbase='${t.media}'; uci commit luci; rm -rf /tmp/luci-indexcache* /tmp/luci-modulecache; /etc/init.d/uhttpd restart >/dev/null 2>&1`);
  await page.waitForTimeout(700);
  if (t.storage !== null) {
    await page.goto(base + '/cgi-bin/luci/', { waitUntil: 'domcontentloaded' });
    await page.evaluate(v => localStorage.setItem('aurora.theme', v), t.storage);
  }
}

const auditInPage = () => {
  const canvas = document.createElement('canvas');
  canvas.width = canvas.height = 1;
  const ctx = canvas.getContext('2d', { willReadFrequently: true });
  function rgba(str) {
    if (!str || str === 'transparent') return [0, 0, 0, 0];
    const m = str.match(/^rgba?\(([^)]+)\)$/i);
    if (m) {
      const parts = m[1].split(/[ ,/]+/).filter(Boolean).map(Number);
      return [parts[0], parts[1], parts[2], parts.length > 3 ? parts[3] : 1];
    }
    ctx.clearRect(0, 0, 1, 1);
    ctx.fillStyle = str;
    ctx.fillRect(0, 0, 1, 1);
    const d = ctx.getImageData(0, 0, 1, 1).data;
    return [d[0], d[1], d[2], d[3] / 255];
  }
  function composite(top, bottom) {
    const a = top[3] + bottom[3] * (1 - top[3]);
    if (a === 0) return [0, 0, 0, 0];
    return [
      (top[0] * top[3] + bottom[0] * bottom[3] * (1 - top[3])) / a,
      (top[1] * top[3] + bottom[1] * bottom[3] * (1 - top[3])) / a,
      (top[2] * top[3] + bottom[2] * bottom[3] * (1 - top[3])) / a,
      a
    ].map((v, i) => i === 3 ? v : Math.round(v)) .map((v, i) => i === 3 ? v : v);
  }
  function stopsOf(image) {
    if (!image || image === 'none' || !image.includes('gradient')) return [];
    return (image.match(/(?:rgba?|lab|oklab|color|hsl|hsla)\([^)]*\)/g) || []).map(rgba);
  }
  function bgOf(el) {
    const chain = [];
    for (let node = el; node; node = node.parentElement) chain.unshift(node);
    let candidates = [[255, 255, 255, 1]];
    for (const node of chain) {
      const cs = getComputedStyle(node);
      const solid = rgba(cs.backgroundColor);
      if (solid[3] > 0) candidates = candidates.map(c => composite(solid, c));
      const stops = stopsOf(cs.backgroundImage);
      if (stops.length) {
        const next = [];
        for (const stop of stops) for (const c of candidates) next.push(composite(stop, c));
        candidates = next;
      }
    }
    return candidates;
  }
  function luminance(c) {
    const s = [c[0], c[1], c[2]].map(v => {
      const x = v / 255;
      return x <= 0.03928 ? x / 12.92 : Math.pow((x + 0.05) / 0.055, 2.4);
    });
    return 0.2126 * s[0] + 0.7152 * s[1] + 0.0722 * s[2];
  }
  function ratio(a, b) {
    const la = luminance(a), lb = luminance(b);
    return (Math.max(la, lb) + 0.05) / (Math.min(la, lb) + 0.05);
  }
  function selector(el) {
    if (el.id) return '#' + el.id;
    const cls = Array.from(el.classList).slice(0, 3);
    return el.tagName.toLowerCase() + (cls.length ? '.' + cls.join('.') : '');
  }
  const root = document.querySelector('#maincontent') || document.body;
  const seen = new Set();
  const rows = [];
  const walker = document.createTreeWalker(root, NodeFilter.SHOW_TEXT, {
    acceptNode(node) {
      if (!node.nodeValue || !node.nodeValue.trim()) return NodeFilter.FILTER_REJECT;
      const p = node.parentElement;
      if (!p || /^(SCRIPT|STYLE|NOSCRIPT)$/i.test(p.tagName)) return NodeFilter.FILTER_REJECT;
      if (p.closest('[aria-hidden="true"]')) return NodeFilter.FILTER_REJECT;
      return NodeFilter.FILTER_ACCEPT;
    }
  });
  let node;
  while ((node = walker.nextNode())) {
    const el = node.parentElement;
    if (seen.has(el)) continue;
    seen.add(el);
    const rect = el.getBoundingClientRect();
    const cs = getComputedStyle(el);
    if (rect.width === 0 || rect.height === 0 || cs.visibility === 'hidden' || Number(cs.opacity) === 0) continue;
    if (el.getClientRects().length === 0) continue;
    const fg = rgba(cs.color);
    if (fg[3] === 0) continue;
    const bgs = bgOf(el);
    const size = parseFloat(cs.fontSize);
    const bold = parseInt(cs.fontWeight, 10) >= 700;
    const large = size >= 24 || (size >= 18.66 && bold);
    const r = Math.min(...bgs.map(b => ratio(fg, b)));
    const bg = bgs.reduce((a, b) => ratio(fg, a) < ratio(fg, b) ? a : b);
    const need = large ? 3 : 4.5;
    rows.push({
      selector: selector(el),
      tag: el.tagName.toLowerCase(),
      text: node.nodeValue.trim().slice(0, 80),
      color: cs.color,
      bg: 'rgb(' + bg.slice(0, 3).join(',') + ')',
      ratio: Math.round(r * 100) / 100,
      need,
      large,
      pass: r >= need,
      fontSize: cs.fontSize,
      fontWeight: cs.fontWeight,
      themeOwned: !Array.from(el.classList).some(c => c.startsWith('cfi-') || c.startsWith('ys-tool-footer'))
    });
  }
  return rows;
};

(async () => {
  const browser = await chromium.launch({ headless: true });
  const ctx = await browser.newContext({ viewport: { width: 1280, height: 900 } });
  const page = await ctx.newPage();
  const results = [];
  try {
    await page.goto(base + '/cgi-bin/luci/', { waitUntil: 'domcontentloaded' });
    const user = page.locator('input[name="luci_username"]');
    if (await user.count()) {
      await user.fill('root');
      await page.locator('input[name="luci_password"]').fill('cfip-gate');
      await page.locator('button:has-text("Log in"), button:has-text("Login"), input[type="submit"]').first().click();
      await page.waitForTimeout(2500);
    }
    sh('printf "#!/bin/sh\\nexit 1\\n" > /etc/init.d/openclash; printf "#!/bin/sh\\nexit 1\\n" > /etc/init.d/passwall; chmod +x /etc/init.d/openclash /etc/init.d/passwall; rm -rf /tmp/luci-indexcache* /tmp/luci-modulecache');
    sh('rm -rf /tmp/luci-indexcache* /tmp/luci-modulecache');
    for (const theme of Object.keys(themes)) {
      await setTheme(page, theme);
      for (const p of pages) {
        await page.goto(base + '/cgi-bin/luci/admin/services/cf_ip/' + p, { waitUntil: 'domcontentloaded' });
        await page.waitForFunction(() => {
          const text = (document.querySelector('#maincontent') || document.body).innerText;
          return text.length > 100 && !/Loading view/.test(text);
        }, null, { timeout: 60000 }).catch(() => {});
        await page.waitForTimeout(250);
        const rows = await page.evaluate(auditInPage);
        results.push({ theme, page: p, url: page.url(), rows });
      }
    }
  } finally {
    try { sh('rm -f /etc/init.d/openclash /etc/init.d/passwall; rm -rf /tmp/luci-indexcache* /tmp/luci-modulecache'); } catch (e) {}
    await browser.close();
  }
  const flat = results.flatMap(r => r.rows.map(x => ({ theme: r.theme, page: r.page, ...x })));
  const failures = flat.filter(x => !x.pass);
  fs.writeFileSync(path.join(out, 'contrast.json'), JSON.stringify({ container, base, label, results, failures }, null, 2) + '\n');
  const summary = { pages: results.length, elements: flat.length, failures: failures.length, byTheme: {}, byPage: {} };
  for (const f of failures) { summary.byTheme[f.theme] = (summary.byTheme[f.theme] || 0) + 1; summary.byPage[f.page] = (summary.byPage[f.page] || 0) + 1; }
  fs.writeFileSync(path.join(out, 'summary.json'), JSON.stringify(summary, null, 2) + '\n');
  console.log(JSON.stringify(summary, null, 2));
  console.log(failures.slice(0, 25).map(f => `${f.theme}/${f.page} ${f.selector} ${f.ratio}<${f.need} ${f.color} on ${f.bg} :: ${f.text}`).join('\n'));
})().catch(e => { console.error(e); process.exit(1); });
