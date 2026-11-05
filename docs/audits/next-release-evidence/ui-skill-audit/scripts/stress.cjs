const { chromium } = require('/tmp/cfip-ui/node_modules/playwright');
const { execSync } = require('node:child_process');
(async()=>{
 execSync(`docker exec cfip-ui-gate sh -c "uci set luci.main.mediaurlbase='/luci-static/bootstrap'; uci commit luci; rm -rf /tmp/luci-indexcache*; /etc/init.d/uhttpd restart >/dev/null 2>&1"`,{stdio:'ignore'});
 const b=await chromium.launch({headless:true,executablePath:'/Users/yunshu/Library/Caches/ms-playwright/chromium-1243/chrome-mac-arm64/Google Chrome for Testing.app/Contents/MacOS/Google Chrome for Testing'});
 const c=await b.newContext({viewport:{width:375,height:900}}); const p=await c.newPage();
 await p.goto('http://127.0.0.1:18080/cgi-bin/luci/',{waitUntil:'domcontentloaded'});
 if(await p.locator('#luci_username').count()){await p.fill('#luci_username','root');await p.fill('#luci_password','cfip-gate');await Promise.all([p.waitForNavigation({waitUntil:'domcontentloaded',timeout:15000}).catch(()=>{}),p.click('button:has-text("Log in")')]);}
 await p.goto('http://127.0.0.1:18080/cgi-bin/luci/admin/services/cf_ip/sources',{waitUntil:'domcontentloaded'});
 await p.waitForFunction(()=>{const m=document.querySelector('#maincontent');return m&&m.innerText.length>80&&!m.innerText.includes('Loading view')},{timeout:20000});
 await p.waitForTimeout(500);
 console.log(await p.evaluate(()=>{
  const cells=[...document.querySelectorAll('.cfi-source-table .td')];
  const last=cells[cells.length-1]; if(!last)return 'no cell';
  last.textContent='https://example.com/very/long/path/that/keeps/going?'+('x'.repeat(120));
  const table=document.querySelector('.cfi-source-table'); const row=last.parentElement;
  const r=x=>{const q=x.getBoundingClientRect();return {w:Math.round(q.width),sw:x.scrollWidth,cw:x.clientWidth,right:Math.round(q.right)}};
  return JSON.stringify({cell:r(last),row:r(row),table:r(table),docW:document.documentElement.scrollWidth,innerW:innerWidth});
 }));
 await p.screenshot({path:'/tmp/cfip-audit-final/sources-long-error-375.png',fullPage:true});
 // openclash table with a backup row: create a backup file and reload
 execSync(`docker exec cfip-ui-gate sh -c 'printf "proxies: []\\n" > /etc/openclash/config/config.yaml.bak.20261104120000; chmod 600 /etc/openclash/config/config.yaml.bak.20261104120000'`);
 await p.goto('http://127.0.0.1:18080/cgi-bin/luci/admin/services/cf_ip/openclash',{waitUntil:'domcontentloaded'});
 await p.waitForTimeout(800);
 console.log(await p.evaluate(()=>{const t=document.querySelector('#oc-backups-section table'); if(!t)return 'no table'; const w=t.parentElement; return JSON.stringify({docW:document.documentElement.scrollWidth,innerW:innerWidth,tableW:t.getBoundingClientRect().width,wrapW:w.getBoundingClientRect().width,rows:t.querySelectorAll('tbody tr').length});}));
 await p.screenshot({path:'/tmp/cfip-audit-final/openclash-backup-375.png',fullPage:true});
 execSync(`docker exec cfip-ui-gate sh -c 'rm -f /etc/openclash/config/config.yaml.bak.20261104120000'`);
 await b.close();
})();
