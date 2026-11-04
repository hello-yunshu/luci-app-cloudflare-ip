'use strict';
const { chromium } = require('/tmp/cfip-ui/node_modules/playwright');
const { execSync } = require('node:child_process');
const Color = require('/tmp/cfip-ui/node_modules/colorjs.io').default;
const fs = require('node:fs');

const BASE = 'http://127.0.0.1:18080';
const PAGES = ['overview','settings','openclash','sources','passwall','intelligence','advanced','logs'];
const THEMES = { bootstrap:'/luci-static/bootstrap', 'aurora-light':'/luci-static/aurora', 'aurora-dark':'/luci-static/aurora' };

function setTheme(theme) {
  execSync(`docker exec cfip-ui-gate sh -c "uci set luci.main.mediaurlbase='${THEMES[theme]}'; uci commit luci; rm -rf /tmp/luci-indexcache* /tmp/luci-modulecache; /etc/init.d/uhttpd restart >/dev/null 2>&1"`, { stdio:'ignore' });
}
async function login(page) {
  if (await page.locator('#luci_username').count()) {
    await page.fill('#luci_username','root'); await page.fill('#luci_password','cfip-gate');
    await Promise.all([page.waitForNavigation({waitUntil:'domcontentloaded',timeout:15000}).catch(()=>{}), page.click('button:has-text("Log in")')]);
  }
}
async function waitView(page) {
  await page.waitForFunction(() => { const m=document.querySelector('#maincontent'); return m && m.innerText.length>80 && !m.innerText.includes('Loading view'); }, {timeout:20000});
  await page.waitForTimeout(500);
}

const COLLECT = () => {
  const vis = el => { const r=el.getBoundingClientRect(); const cs=getComputedStyle(el); return r.width>2&&r.height>2&&cs.display!=='none'&&cs.visibility!=='hidden'&&parseFloat(cs.opacity)>.05; };
  const txt = el => (el.innerText||el.value||'').trim().replace(/\s+/g,' ').slice(0,60);
  const path = el => { const parts=[]; let n=el; while(n&&n!==document.body&&parts.length<4){ let s=n.tagName.toLowerCase(); if(n.id)s+='#'+n.id; else if(n.className&&typeof n.className==='string')s+='.'+n.className.trim().split(/\s+/).slice(0,2).join('.'); parts.unshift(s); n=n.parentElement;} return parts.join('>'); };
  const items=[];
  document.querySelectorAll('body *').forEach(el=>{
    if(!vis(el))return;
    const direct=[...(el.childNodes||[])].filter(n=>n.nodeType===3&&n.textContent.trim()).map(n=>n.textContent.trim()).join(' ');
    if(!direct)return;
    const cs=getComputedStyle(el);
    const chain=[]; let n=el;
    while(n){ chain.unshift(n); n=n.parentElement; }
    const bgs=chain.map(x=>getComputedStyle(x).backgroundColor).filter(c=>c&&c!=='rgba(0, 0, 0, 0)');
    items.push({tag:el.tagName,cls:String(el.className).slice(0,70),text:txt(el),path:path(el),fg:cs.color,bgs,fs:parseFloat(cs.fontSize),fw:parseInt(cs.fontWeight,10)||400});
  });
  return {dark:document.documentElement.getAttribute('data-darkmode')==='true', items};
};

const FOCUS = async (page) => {
  await page.evaluate(()=>document.body.focus());
  const out=[];
  for(let i=0;i<18;i++){
    await page.keyboard.press('Tab');
    const r=await page.evaluate(()=>{ const a=document.activeElement; if(!a||a===document.body)return null; const cs=getComputedStyle(a); const rr=a.getBoundingClientRect(); return {tag:a.tagName,text:(a.innerText||a.value||'').trim().replace(/\s+/g,' ').slice(0,40),cls:String(a.className).slice(0,50),outlineW:cs.outlineWidth,outlineStyle:cs.outlineStyle,outlineColor:cs.outlineColor,boxShadow:cs.boxShadow,borderColor:cs.borderColor,w:Math.round(rr.width),h:Math.round(rr.height)}; });
    if(r) out.push(r);
  }
  return out;
};

(async()=>{
  const browser=await chromium.launch({headless:true,executablePath:'/Users/yunshu/Library/Caches/ms-playwright/chromium-1243/chrome-mac-arm64/Google Chrome for Testing.app/Contents/MacOS/Google Chrome for Testing'});
  const ctx=await browser.newContext({viewport:{width:1280,height:900}}); const page=await ctx.newPage();
  const raw=[]; const focus=[];
  try{
    for(const theme of Object.keys(THEMES)){
      setTheme(theme);
      await page.goto(BASE+'/cgi-bin/luci/',{waitUntil:'domcontentloaded'});
      if(theme!=='bootstrap') await page.evaluate(m=>localStorage.setItem('aurora.theme',m==='aurora-dark'?'dark':'light'),theme);
      await page.reload({waitUntil:'domcontentloaded'}); await login(page);
      for(const name of PAGES){
        await page.goto(`${BASE}/cgi-bin/luci/admin/services/cf_ip/${name}`,{waitUntil:'domcontentloaded'}); await login(page); await waitView(page);
        const c=await page.evaluate(COLLECT); c.theme=theme; c.page=name; raw.push(c);
        focus.push({theme,page:name,seq:await FOCUS(page)});
      }
    }
  }finally{
    fs.writeFileSync('/tmp/cfip-audit/contrast-raw.json',JSON.stringify(raw));
    fs.writeFileSync('/tmp/cfip-audit/focus.json',JSON.stringify(focus,null,2));
    await browser.close();
  }
})();
