'use strict';
const { chromium } = require('/tmp/cfip-ui/node_modules/playwright');
const { execSync } = require('node:child_process');
const fs = require('node:fs');
const path = require('node:path');

const BASE = 'http://127.0.0.1:18080';
const OUT = '/tmp/cfip-audit';
const PAGES = ['overview','settings','openclash','sources','passwall','intelligence','advanced','logs'];
const THEMES = {
  bootstrap: { media: '/luci-static/bootstrap', mode: null },
  'aurora-light': { media: '/luci-static/aurora', mode: 'light' },
  'aurora-dark': { media: '/luci-static/aurora', mode: 'dark' }
};
const VIEWPORTS = [
  { name: '375x900', w: 375, h: 900 },
  { name: '768x900', w: 768, h: 900 },
  { name: '1280x900', w: 1280, h: 900 },
  { name: '320x900', w: 320, h: 900 },
  { name: '1280x900-200pct-effective-640', w: 640, h: 900 }
];
fs.mkdirSync(OUT, { recursive: true });

function setTheme(theme) {
  const cfg = THEMES[theme];
  execSync(`docker exec cfip-ui-gate sh -c "uci set luci.main.mediaurlbase='${cfg.media}'; uci commit luci; rm -rf /tmp/luci-indexcache* /tmp/luci-modulecache; /etc/init.d/uhttpd restart >/dev/null 2>&1"`, { stdio: 'ignore' });
}

async function loginIfNeeded(page) {
  if (await page.locator('#luci_username').count()) {
    await page.fill('#luci_username', 'root');
    await page.fill('#luci_password', 'cfip-gate');
    await Promise.all([
      page.waitForNavigation({ waitUntil: 'networkidle' }).catch(() => {}),
      page.click('button:has-text("Log in"), input[type="submit"]')
    ]);
  }
}

async function waitView(page) {
  await page.waitForFunction(() => {
    const m = document.querySelector('#maincontent');
    if (!m) return false;
    const t = m.innerText || '';
    return t.length > 80 && !t.includes('Loading view') && !t.includes('加载视图');
  }, { timeout: 20000 });
  await page.waitForTimeout(600);
}

const METRICS = () => {
  const parse = c => {
    const m = c.match(/rgba?\(([^)]+)\)/);
    if (!m) return [0,0,0,0];
    const p = m[1].split(',').map(Number);
    return [p[0],p[1],p[2],p.length > 3 ? p[3] : 1];
  };
  const comp = (fg, bg) => {
    const a = fg[3] + bg[3]*(1-fg[3]);
    if (a === 0) return [0,0,0,0];
    return [
      (fg[0]*fg[3] + bg[0]*bg[3]*(1-fg[3]))/a,
      (fg[1]*fg[3] + bg[1]*bg[3]*(1-fg[3]))/a,
      (fg[2]*fg[3] + bg[2]*bg[3]*(1-fg[3]))/a,
      a
    ];
  };
  const lum = c => {
    const f = v => { v = v/255; return v <= .03928 ? v/12.92 : Math.pow((v+.055)/1.055, 2.4); };
    return .2126*f(c[0]) + .7152*f(c[1]) + .0722*f(c[2]);
  };
  const ratio = (a,b) => { const l1=lum(a), l2=lum(b); return (Math.max(l1,l2)+.05)/(Math.min(l1,l2)+.05); };
  const bgOf = el => {
    const chain = []; let n = el;
    while (n && n !== document.documentElement) { chain.unshift(n); n = n.parentElement; }
    chain.unshift(document.documentElement);
    let bg = [255,255,255,1];
    for (const x of chain) {
      const cs = getComputedStyle(x);
      const c = parse(cs.backgroundColor);
      if (c[3] > 0) bg = comp(c, bg);
    }
    return bg;
  };
  const vis = el => {
    const r = el.getBoundingClientRect();
    const cs = getComputedStyle(el);
    return r.width > 2 && r.height > 2 && cs.display !== 'none' && cs.visibility !== 'hidden' && parseFloat(cs.opacity) > .05;
  };
  const rect = el => { const r = el.getBoundingClientRect(); return { x:Math.round(r.x), y:Math.round(r.y), w:Math.round(r.width), h:Math.round(r.height) }; };
  const txt = el => (el.innerText || el.value || '').trim().replace(/\s+/g,' ').slice(0,100);

  const overflowEls = [];
  const clipped = [];
  const scrolls = [];
  const interactive = [];
  const textEls = [];

  document.querySelectorAll('body *').forEach(el => {
    if (!vis(el)) return;
    const r = el.getBoundingClientRect();
    if (r.right > innerWidth + 1 || r.left < -1) {
      if (overflowEls.length < 12) overflowEls.push({ tag: el.tagName, cls: String(el.className).slice(0,80), text: txt(el), ...rect(el) });
    }
    const cs = getComputedStyle(el);
    if ((cs.overflowX === 'hidden' || cs.overflowX === 'clip' || cs.whiteSpace === 'nowrap') && el.scrollWidth > el.clientWidth + 1 && el.clientWidth > 0) {
      if (clipped.length < 12) clipped.push({ tag: el.tagName, cls: String(el.className).slice(0,80), text: txt(el), clientW: el.clientWidth, scrollW: el.scrollWidth });
    }
    if ((cs.overflowX === 'auto' || cs.overflowX === 'scroll') && el.scrollWidth > el.clientWidth + 1) {
      if (scrolls.length < 12) scrolls.push({ tag: el.tagName, cls: String(el.className).slice(0,80), text: txt(el), clientW: el.clientWidth, scrollW: el.scrollWidth });
    }
    if (['A','BUTTON','INPUT','SELECT','TEXTAREA','SUMMARY'].includes(el.tagName)) {
      interactive.push({ tag: el.tagName, text: txt(el), ...rect(el) });
    }
    if (el.children.length === 0 && (el.textContent || '').trim()) {
      const cs2 = getComputedStyle(el);
      const fg = parse(cs2.color);
      const bg = bgOf(el);
      const rr = ratio(fg, bg);
      const fs = parseFloat(cs2.fontSize);
      const bold = parseInt(cs2.fontWeight,10) >= 700;
      const need = (fs >= 24 || (fs >= 18.66 && bold)) ? 3 : 4.5;
      if (rr < need && textEls.length < 20) textEls.push({ tag: el.tagName, cls: String(el.className).slice(0,80), text: txt(el).slice(0,60), fg: cs2.color, bg: `rgb(${bg.slice(0,3).map(Math.round).join(',')})`, ratio: +rr.toFixed(2), need, fs });
    }
  });

  const tiny = interactive.filter(x => x.w < 24 || x.h < 24);
  const small = interactive.filter(x => x.w < 44 || x.h < 44);
  const footer = document.querySelector('.ys-tool-footer');
  const footerRect = footer ? rect(footer) : null;
  const tabMenu = document.querySelector('#tabmenu');
  const tabRect = tabMenu ? rect(tabMenu) : null;
  const firstSection = document.querySelector('#maincontent .cbi-section');
  const sectionStyle = firstSection ? (() => { const cs = getComputedStyle(firstSection); return { bg: cs.backgroundColor, border: cs.borderColor, shadow: cs.boxShadow, radius: cs.borderRadius }; })() : null;

  return {
    url: location.href,
    title: document.title,
    w: innerWidth,
    h: innerHeight,
    docW: document.documentElement.scrollWidth,
    bodyW: document.body.scrollWidth,
    overflowX: document.documentElement.scrollWidth > innerWidth + 1 || document.body.scrollWidth > innerWidth + 1,
    overflowEls,
    clipped,
    scrolls,
    tiny: tiny.slice(0,10),
    tinyCount: tiny.length,
    smallCount: small.length,
    interactiveCount: interactive.length,
    contrast: textEls,
    footerRect,
    tabRect,
    sectionStyle,
    textLen: (document.querySelector('#maincontent')||document.body).innerText.length,
    mainText: (document.querySelector('#maincontent')||document.body).innerText.replace(/\s+/g,' ').slice(0,220)
  };
};

(async () => {
  const browser = await chromium.launch({ headless: true, executablePath: '/Users/yunshu/Library/Caches/ms-playwright/chromium-1243/chrome-mac-arm64/Google Chrome for Testing.app/Contents/MacOS/Google Chrome for Testing' });
  const context = await browser.newContext({ viewport: { width: 1280, height: 900 } });
  const page = await context.newPage();
  const metrics = [];
  try {
    for (const theme of Object.keys(THEMES)) {
      setTheme(theme);
      await page.goto(BASE + '/cgi-bin/luci/', { waitUntil: 'domcontentloaded' });
      if (THEMES[theme].mode) await page.evaluate(m => localStorage.setItem('aurora.theme', m), THEMES[theme].mode);
      await page.reload({ waitUntil: 'domcontentloaded' });
      await loginIfNeeded(page);
      for (const vp of VIEWPORTS) {
        await page.setViewportSize({ width: vp.w, height: vp.h });
        for (const name of PAGES) {
          await page.goto(`${BASE}/cgi-bin/luci/admin/services/cf_ip/${name}`, { waitUntil: 'domcontentloaded' });
          await loginIfNeeded(page);
          await waitView(page);
          const dir = path.join(OUT, theme, vp.name);
          fs.mkdirSync(dir, { recursive: true });
          await page.screenshot({ path: path.join(dir, name + '.png'), fullPage: true });
          const m = await page.evaluate(METRICS);
          m.theme = theme; m.viewport = vp.name; m.page = name;
          metrics.push(m);
          console.log('captured', theme, vp.name, name, m.overflowX ? 'OVERFLOW' : 'ok', 'tiny=' + m.tinyCount, 'contrast=' + m.contrast.length);
        }
      }
    }
  } finally {
    fs.writeFileSync(path.join(OUT, 'metrics.jsonl'), metrics.map(x => JSON.stringify(x)).join('\n') + '\n');
    await browser.close();
  }
})().catch(e => { console.error(e); process.exit(1); });
